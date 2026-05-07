-- Rendering: draws the grid, dungeon tiles, and entities.
-- The only module (besides ui.lua) allowed to call love.graphics.

local grid = require("src.grid")

local M = {}

-- Palette tuned against the #1a1a2e background.
local COLOR_TILE_FILL = { 0.13, 0.13, 0.22 }
local COLOR_TILE_LINE = { 0.22, 0.22, 0.34 }

function M.draw_grid()
    for ty = 1, grid.HEIGHT do
        for tx = 1, grid.WIDTH do
            local px, py = grid.tile_to_pixel(tx, ty)

            love.graphics.setColor(COLOR_TILE_FILL)
            love.graphics.rectangle("fill", px, py, grid.TILE, grid.TILE)

            love.graphics.setColor(COLOR_TILE_LINE)
            love.graphics.rectangle("line", px, py, grid.TILE, grid.TILE)
        end
    end

    love.graphics.setColor(1, 1, 1, 1) -- reset for callers downstream
end

return M
