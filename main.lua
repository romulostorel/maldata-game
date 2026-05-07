-- Entry point: wires LÖVE callbacks to the game state, input router,
-- world renderer, and HUD.

local render      = require("src.render")
local state       = require("src.state")
local input       = require("src.input")
local ui          = require("src.ui")
local palette     = require("src.palette")
local sprite_base = require("src.gen.sprite_base")
local entity_gen  = require("src.gen.entity_gen")
local assets      = require("src.assets")

local BG_R, BG_G, BG_B = 26 / 255, 26 / 255, 46 / 255 -- #1a1a2e

local game
local show_palette     = false
local show_sprite_base = false
local show_entities    = false

local function rand_seed()
    return math.random(1, 2147483646)
end

function love.load()
    love.graphics.setBackgroundColor(BG_R, BG_G, BG_B)
    love.graphics.setDefaultFilter("nearest", "nearest")
    love.keyboard.setKeyRepeat(false)

    assets.load()

    math.randomseed(os.time())
    game = state.new(rand_seed())
end

function love.update(dt)
    state.update(game, dt)
end

function love.draw()
    render.draw_dungeon(game.dungeon)
    render.draw_monsters(game.monsters)
    render.draw_path(game)
    render.draw_hero(game.hero)
    render.draw_build_cursor(game)

    ui.draw_hp_bars(game)
    ui.draw_hud(game)
    ui.draw_result(game)

    if show_palette then palette.draw_debug() end
    if show_sprite_base then sprite_base.draw_debug() end
    if show_entities then entity_gen.draw_debug() end
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
    elseif key == "r" then
        state.reset(game, rand_seed())
    elseif game.phase == state.PHASE_INVASION then
        if key == "space" then
            state.toggle_auto_step(game)
        elseif key == "." or key == "right" then
            state.step_invasion(game)
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

    if game.phase == state.PHASE_RESULT then
        if ui.is_restart_clicked(x, y) then
            state.reset(game, rand_seed())
        end
        return
    end

    input.handle_mouse(game, x, y, button)
end
