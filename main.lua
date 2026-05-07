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
        if attacker.class then audio.play("hero_attack") end
        audio.play("hit_impact")
    elseif kind == "death" then
        attacker._death_at = now  -- "attacker" arg holds the dying entity here
        effects.spawn_scatter(attacker.x, attacker.y)
    elseif kind == "move" then
        if attacker.class then audio.play("hero_footstep") end
    end
end

function love.load()
    love.graphics.setBackgroundColor(BG_R, BG_G, BG_B)
    love.graphics.setDefaultFilter("nearest", "nearest")
    love.keyboard.setKeyRepeat(false)

    assets.load()
    audio.load()

    math.randomseed(os.time())
    game = state.new(rand_seed())
end

function love.update(dt)
    state.update(game, dt, on_combat_event)
    effects.update(dt)
end

function love.draw()
    render.draw_dungeon(game.dungeon)
    render.draw_monsters(game.monsters)
    render.draw_path(game)
    render.draw_hero(game.hero)
    render.draw_build_cursor(game)

    effects.draw()

    ui.draw_hp_bars(game)
    ui.draw_hud(game)
    ui.draw_result(game)

    if show_palette then palette.draw_debug() end
    if show_sprite_base then sprite_base.draw_debug() end
    if show_entities then anim_gen.draw_debug() end
    if show_audio then audio_debug.draw() end
end

function love.keypressed(key)
    if key == "escape" then
        love.event.quit()
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
    if button ~= 1 then return end

    if show_audio then
        audio_debug.mousepressed(x, y, button)
        return
    end

    if game.phase == state.PHASE_RESULT then
        if ui.is_restart_clicked(x, y) then
            audio.play("ui_click")
            state.reset(game, rand_seed())
            effects.clear()
        end
        return
    end

    input.handle_mouse(game, x, y, button)
end
