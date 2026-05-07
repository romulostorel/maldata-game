-- Entry point: wires LÖVE callbacks to the game state and input router.

local render = require("src.render")
local state = require("src.state")
local input = require("src.input")

local BG_R, BG_G, BG_B = 26 / 255, 26 / 255, 46 / 255 -- #1a1a2e

local game

local function rand_seed()
    return math.random(1, 2147483646)
end

function love.load()
    love.graphics.setBackgroundColor(BG_R, BG_G, BG_B)
    love.graphics.setDefaultFilter("nearest", "nearest")
    love.keyboard.setKeyRepeat(false)

    math.randomseed(os.time())
    game = state.new(rand_seed())
end

function love.update(dt)
    -- Logic update hook. Future stages: state:update(dt).
end

function love.draw()
    render.draw_dungeon(game.dungeon)
    render.draw_monsters(game.monsters)
    render.draw_build_cursor(game)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(
        ("PHASE: %s    seed: %d    FPS: %d")
            :format(game.phase:upper(), game.seed, love.timer.getFPS()),
        8, 8)
    love.graphics.print(
        ("[1] goblin   [2] orc   [3] slime    selected: %s    placed: %d/%d")
            :format(game.selected_monster_type, #game.monsters, state.MAX_MONSTERS),
        8, 24)
    love.graphics.print(
        "[CLICK] place    [SPACE] next phase    [R] new dungeon    [ESC] quit",
        8, 40)
end

function love.keypressed(key)
    if key == "escape" then
        love.event.quit()
    elseif key == "space" then
        state.advance(game)
    elseif key == "r" then
        state.reset(game, rand_seed())
    else
        input.handle_key(game, key)
    end
end

function love.mousepressed(x, y, button)
    input.handle_mouse(game, x, y, button)
end
