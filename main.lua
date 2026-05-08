-- Entry point: wires LÖVE callbacks to the game state, input router,
-- world renderer, and HUD.

local render      = require("src.render")
local state       = require("src.state")
local input       = require("src.input")
local ui          = require("src.ui")
local palette     = require("src.palette")
local sprite_base = require("src.gen.sprite_base")
local anim_gen    = require("src.gen.anim_gen")
local assets      = require("src.assets")
local effects     = require("src.effects")
local audio       = require("src.audio")
local audio_debug = require("src.audio_debug")
local viewport    = require("src.viewport")

local BG_R, BG_G, BG_B = 26 / 255, 26 / 255, 46 / 255 -- #1a1a2e

local game
local show_palette     = false
local show_sprite_base = false
local show_entities    = false
local show_audio       = false

local function rand_seed()
    return math.random(1, 2147483646)
end

-- Combat → animation+effects+audio bridge. state.lua emits these events; we
-- stamp the entity with a timestamp the renderer reads to pick attack/death
-- frames, spawn matching one-shot visual effects (sparks, scatter, damage
-- number), and route the matching SFX.
local function on_combat_event(kind, attacker, target)
    local now = love.timer.getTime()
    if kind == "attack" then
        attacker._attack_at = now
        local color = target.class and palette.blood or palette.paper
        effects.spawn_hit(target.x, target.y)
        effects.spawn_damage(target.x, target.y, attacker.atk, color)
        if attacker.class then
            audio.play("hero_attack_" .. attacker.class)
        elseif attacker.type then
            audio.play("monster_attack_" .. attacker.type)
        end
        audio.play("hit_impact")
    elseif kind == "death" then
        attacker._death_at = now  -- "attacker" arg holds the dying entity here
        effects.spawn_scatter(attacker.x, attacker.y)
        if attacker.type then
            audio.play("monster_death_" .. attacker.type)
        elseif attacker.class then
            audio.play("hero_death")
        end
    elseif kind == "move" then
        if attacker.class then audio.play("hero_footstep") end
    end
end

function love.load()
    love.graphics.setDefaultFilter("nearest", "nearest")
    love.keyboard.setKeyRepeat(false)

    -- Resize the boot window from the conf.lua default (800×600) to the
    -- largest integer scale that fits the desktop. Cheap on a fresh boot
    -- and means the user sees a properly-sized window from frame 1.
    local sw, sh = viewport.suggest_initial_size()
    love.window.setMode(sw, sh, { vsync = 1, resizable = true })
    love.graphics.setBackgroundColor(BG_R, BG_G, BG_B)

    assets.load()
    audio.load()
    viewport.init()

    math.randomseed(os.time())
    game = state.new(rand_seed())
    -- M.new doesn't go through set_phase, so prime the build drone manually
    -- on first boot. Subsequent transitions are driven by set_phase.
    audio.set_ambient("ambient_build")
end

function love.resize()
    viewport.recompute_layout()
end

function love.update(dt)
    state.update(game, dt, on_combat_event)
    effects.update(dt)
end

function love.draw()
    -- Render every game element into the fixed 800×600 viewport canvas.
    -- Game logic and UI never know the actual window size — they always
    -- work in canvas coords.
    love.graphics.setCanvas(viewport.canvas())
    love.graphics.clear(BG_R, BG_G, BG_B)

    render.draw_dungeon(game.dungeon)
    render.draw_monsters(game.monsters)
    render.draw_path(game)
    render.draw_heroes(game.heroes)
    render.draw_build_cursor(game)

    effects.draw()

    ui.draw_hp_bars(game)
    ui.draw_hud(game)
    ui.draw_result(game)
    ui.draw_tutorial(game)

    if show_palette then palette.draw_debug() end
    if show_sprite_base then sprite_base.draw_debug() end
    if show_entities then anim_gen.draw_debug() end
    if show_audio then audio_debug.draw() end

    -- Blit the canvas to the actual window: scaled, centered, with
    -- letterbox bars when window aspect ≠ canvas aspect.
    love.graphics.setCanvas()
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.setColor(1, 1, 1, 1)
    local s = viewport.scale()
    local ox, oy = viewport.offset()
    love.graphics.draw(viewport.canvas(), ox, oy, 0, s, s)
end

function love.keypressed(key)
    ui.dismiss_tutorial()
    if key == "escape" then
        love.event.quit()
    elseif key == "f11" then
        love.window.setFullscreen(not love.window.getFullscreen(), "desktop")
        viewport.recompute_layout()
    elseif key == "f1" then
        show_palette = not show_palette
    elseif key == "f2" then
        show_sprite_base = not show_sprite_base
    elseif key == "f3" then
        show_entities = not show_entities
    elseif key == "f4" then
        show_audio = not show_audio
    elseif key == "r" then
        state.reset(game, rand_seed())
        effects.clear()
    elseif game.phase == state.PHASE_INVASION then
        if key == "space" then
            state.toggle_auto_step(game)
        elseif key == "." or key == "right" then
            state.step_invasion(game, on_combat_event)
        end
    else
        if key == "space" then
            state.advance(game)
        else
            input.handle_key(game, key)
        end
    end
end

function love.mousepressed(x, y, button)
    -- Left = place / confirm, right = undo placement. Anything else ignored.
    if button ~= 1 and button ~= 2 then return end

    -- Convert window coords to canvas coords; everything downstream works
    -- in canvas (800×600) space.
    x, y = viewport.window_to_canvas(x, y)

    ui.dismiss_tutorial()

    if show_audio then
        if button == 1 then audio_debug.mousepressed(x, y, button) end
        return
    end

    if game.phase == state.PHASE_RESULT then
        if button == 1 and ui.is_retry_clicked(x, y) then
            audio.play("ui_click")
            state.advance(game)  -- result -> build, same dungeon
            effects.clear()
        elseif button == 1 and ui.is_new_dungeon_clicked(x, y) then
            audio.play("ui_click")
            state.reset(game, rand_seed())
            effects.clear()
        end
        return
    end

    -- Build-phase toolbar: clicking a cell selects the same tool a number
    -- key would. Routed before tile placement so a click inside the chrome
    -- never falls through to the world.
    if game.phase == state.PHASE_BUILD and button == 1 then
        local tool = ui.tool_at(x, y)
        if tool then
            audio.play("ui_click")
            if tool.kind == state.TOOL_MONSTER then
                state.select_tool(game, state.TOOL_MONSTER)
                state.select_monster_type(game, tool.type_key)
            else
                state.select_tool(game, state.TOOL_WALL)
            end
            return
        end
    end

    input.handle_mouse(game, x, y, button)
end
