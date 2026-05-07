-- Entry point: wires LÖVE callbacks to the game state.

local render = require("src.render")
local state = require("src.state")

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

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(
        ("PHASE: %s    seed: %d    FPS: %d")
            :format(game.phase:upper(), game.seed, love.timer.getFPS()),
        8, 8)
    love.graphics.print(
        "[SPACE] next phase    [R] new dungeon    [ESC] quit",
        8, 24)
end

function love.keypressed(key)
    if key == "escape" then
        love.event.quit()
    elseif key == "space" then
        state.advance(game)
    elseif key == "r" then
        state.reset(game, rand_seed())
    end
end
