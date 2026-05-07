-- Entry point: wires LÖVE callbacks to the game's state machine.

local render = require("src.render")

local BG_R, BG_G, BG_B = 26 / 255, 26 / 255, 46 / 255 -- #1a1a2e

function love.load()
    love.graphics.setBackgroundColor(BG_R, BG_G, BG_B)
    love.graphics.setDefaultFilter("nearest", "nearest")
    love.keyboard.setKeyRepeat(false)
end

function love.update(dt)
    -- Logic update hook. Future stages: state:update(dt).
end

function love.draw()
    render.draw_grid()

    -- HUD overlay.
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(("FPS: %d"):format(love.timer.getFPS()), 8, 8)
end

function love.keypressed(key)
    if key == "escape" then
        love.event.quit()
    end
end
