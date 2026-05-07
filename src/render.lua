-- Rendering: draws the dungeon grid, entrance/treasure markers, placed
-- monsters, and the build-phase placement cursor. The only module
-- (besides ui.lua) allowed to call love.graphics.

local grid = require("src.grid")
local dungeon = require("src.dungeon")
local monster = require("src.monster")
local state = require("src.state")

local M = {}

-- Palette tuned against the #1a1a2e background.
local COLOR_FLOOR_FILL = { 0.13, 0.13, 0.22 }
local COLOR_FLOOR_LINE = { 0.22, 0.22, 0.34 }
local COLOR_WALL_FILL  = { 0.20, 0.20, 0.34 }
local COLOR_WALL_LINE  = { 0.32, 0.32, 0.46 }
local COLOR_ENTRANCE   = { 0.40, 0.85, 1.00 }
local COLOR_TREASURE   = { 1.00, 0.84, 0.20 }
local COLOR_CURSOR_OK  = { 0.40, 1.00, 0.50, 0.30 }
local COLOR_CURSOR_BAD = { 1.00, 0.40, 0.40, 0.30 }

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

    do
        local px, py = grid.tile_to_pixel(d.entrance.x, d.entrance.y)
        love.graphics.setColor(COLOR_ENTRANCE)
        love.graphics.circle("line",
            px + grid.TILE / 2, py + grid.TILE / 2,
            grid.TILE * 0.35)
    end

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

function M.draw_monsters(monsters)
    for _, m in ipairs(monsters) do
        local px, py = grid.tile_to_pixel(m.x, m.y)
        love.graphics.setColor(monster.TYPES[m.type].color)
        love.graphics.circle("fill",
            px + grid.TILE / 2, py + grid.TILE / 2,
            grid.TILE * 0.35)
    end
    love.graphics.setColor(1, 1, 1, 1)
end

-- Translucent overlay on the tile under the mouse, green when placement
-- would succeed and red when it would be rejected. Build phase only.
function M.draw_build_cursor(game)
    if game.phase ~= state.PHASE_BUILD then return end
    local mx, my = love.mouse.getPosition()
    local tx, ty = grid.pixel_to_tile(mx, my)
    if not tx then return end

    local px, py = grid.tile_to_pixel(tx, ty)
    local ok = state.can_place_monster(game, tx, ty)
    love.graphics.setColor(ok and COLOR_CURSOR_OK or COLOR_CURSOR_BAD)
    love.graphics.rectangle("fill", px, py, grid.TILE, grid.TILE)
    love.graphics.setColor(1, 1, 1, 1)
end

return M
