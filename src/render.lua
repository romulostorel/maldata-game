-- Rendering: draws the dungeon grid, entrance/treasure markers, placed
-- monsters, the live hero, the planned A* path, and the build-phase
-- placement cursor. Sole consumer of love.graphics for the world view.

local grid    = require("src.grid")
local dungeon = require("src.dungeon")
local monster = require("src.monster")
local hero    = require("src.hero")
local state   = require("src.state")
local assets  = require("src.assets")

local M = {}

local COLOR_CURSOR_OK   = { 0.40, 1.00, 0.50, 0.30 }
local COLOR_CURSOR_BAD  = { 1.00, 0.40, 0.40, 0.30 }
local COLOR_HERO_BORDER = { 1.00, 1.00, 1.00 }
local COLOR_PATH_DOT    = { 1.00, 1.00, 1.00, 0.20 }

function M.draw_dungeon(d)
    love.graphics.setColor(1, 1, 1, 1)

    local floor_imgs = assets.tiles.floor
    local wall_imgs  = assets.tiles.wall
    local n_floor    = #floor_imgs
    local n_wall     = #wall_imgs

    for ty = 1, grid.HEIGHT do
        for tx = 1, grid.WIDTH do
            local px, py = grid.tile_to_pixel(tx, ty)
            local img

            if tx == d.entrance.x and ty == d.entrance.y then
                img = assets.tiles.door
            elseif tx == d.treasure.x and ty == d.treasure.y then
                img = assets.tiles.treasure
            elseif d.grid[ty][tx] == dungeon.WALL then
                img = wall_imgs[assets.tile_variation(tx, ty, n_wall)]
            else
                img = floor_imgs[assets.tile_variation(tx, ty, n_floor)]
            end

            love.graphics.draw(img, px, py)
        end
    end
end

function M.draw_monsters(monsters)
    for _, m in ipairs(monsters) do
        if m.alive then
            local px, py = grid.tile_to_pixel(m.x, m.y)
            love.graphics.setColor(monster.TYPES[m.type].color)
            love.graphics.circle("fill",
                px + grid.TILE / 2, py + grid.TILE / 2,
                grid.TILE * 0.35)
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

function M.draw_path(game)
    if game.phase ~= state.PHASE_INVASION then return end
    local path = state.hero_path(game)
    if not path then return end
    love.graphics.setColor(COLOR_PATH_DOT)
    for _, p in ipairs(path) do
        local px, py = grid.tile_to_pixel(p.x, p.y)
        love.graphics.circle("fill",
            px + grid.TILE / 2, py + grid.TILE / 2,
            grid.TILE * 0.10)
    end
    love.graphics.setColor(1, 1, 1, 1)
end

function M.draw_hero(h)
    if not h or not h.alive then return end
    local px, py = grid.tile_to_pixel(h.x, h.y)
    local cx, cy = px + grid.TILE / 2, py + grid.TILE / 2
    local r = grid.TILE * 0.40

    love.graphics.setColor(hero.CLASSES[h.class].color)
    love.graphics.circle("fill", cx, cy, r)

    love.graphics.setColor(COLOR_HERO_BORDER)
    love.graphics.setLineWidth(2)
    love.graphics.circle("line", cx, cy, r)
    love.graphics.setLineWidth(1)
end

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
