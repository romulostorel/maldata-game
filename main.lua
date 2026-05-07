-- Entry point: wires LÖVE callbacks to the game's state machine.

local render = require("src.render")
local dungeon = require("src.dungeon")

local BG_R, BG_G, BG_B = 26 / 255, 26 / 255, 46 / 255 -- #1a1a2e

local current_dungeon

local function fresh_dungeon()
    return dungeon.generate(math.random(1, 2147483646))
end

function love.load()
    love.graphics.setBackgroundColor(BG_R, BG_G, BG_B)
    love.graphics.setDefaultFilter("nearest", "nearest")
    love.keyboard.setKeyRepeat(false)

    -- Stage 4 will own the seed source; for now reseed from wall-clock time
    -- so each launch shows a different dungeon.
    math.randomseed(os.time())
    current_dungeon = fresh_dungeon()
end

function love.update(dt)
    -- Logic update hook. Future stages: state:update(dt).
end

function love.draw()
    render.draw_dungeon(current_dungeon)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(
        ("FPS: %d   seed: %d   [R] regen   [ESC] quit")
            :format(love.timer.getFPS(), current_dungeon.seed),
        8, 8)
end

function love.keypressed(key)
    if key == "escape" then
        love.event.quit()
    elseif key == "r" then
        current_dungeon = fresh_dungeon()
    end
end
