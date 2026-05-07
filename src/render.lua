-- Rendering: draws the dungeon grid (walls/floor) and the entrance/treasure
-- markers. The only module (besides ui.lua) allowed to call love.graphics.

local grid = require("src.grid")
local dungeon = require("src.dungeon")

local M = {}

-- Palette tuned against the #1a1a2e background.
local COLOR_FLOOR_FILL = { 0.13, 0.13, 0.22 }
local COLOR_FLOOR_LINE = { 0.22, 0.22, 0.34 }
local COLOR_WALL_FILL  = { 0.20, 0.20, 0.34 }
local COLOR_WALL_LINE  = { 0.32, 0.32, 0.46 }
local COLOR_ENTRANCE   = { 0.40, 0.85, 1.00 }
local COLOR_TREASURE   = { 1.00, 0.84, 0.20 }

function M.draw_dungeon(d)
    for ty = 1, grid.HEIGHT do
        for tx = 1, grid.WIDTH do
            local px, py = grid.tile_to_pixel(tx, ty)
            local is_wall = (d.grid[ty][tx] == dungeon.WALL)

            love.graphics.setColor(is_wall and COLOR_WALL_FILL or COLOR_FLOOR_FILL)
            love.graphics.rectangle("fill", px, py, grid.TILE, grid.TILE)

            love.graphics.setColor(is_wall and COLOR_WALL_LINE or COLOR_FLOOR_LINE)
            love.graphics.rectangle("line", px, py, grid.TILE, grid.TILE)
        end
    end

    -- Entrance: cyan ring on the door tile.
    do
        local px, py = grid.tile_to_pixel(d.entrance.x, d.entrance.y)
        love.graphics.setColor(COLOR_ENTRANCE)
        love.graphics.circle("line",
            px + grid.TILE / 2, py + grid.TILE / 2,
            grid.TILE * 0.35)
    end

    -- Treasure: gold diamond.
    do
        local px, py = grid.tile_to_pixel(d.treasure.x, d.treasure.y)
        local cx, cy = px + grid.TILE / 2, py + grid.TILE / 2
        local r = grid.TILE * 0.4
        love.graphics.setColor(COLOR_TREASURE)
        love.graphics.polygon("fill",
            cx, cy - r,
            cx + r, cy,
            cx, cy + r,
            cx - r, cy)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

return M
