-- Grid system: tile <-> pixel coordinate conversion, bounds checks, neighbor lookup.
-- Single source of truth for tile size and grid dimensions. Pure logic, no rendering.

local M = {}

M.WIDTH = 20      -- tiles
M.HEIGHT = 15     -- tiles
M.TILE = 32       -- pixels per tile

-- Pixel offsets so the 640x480 grid is centered horizontally and sits
-- *below* the 76 px HUD chrome strip with a 4 px breathing gap. Bottom of
-- the grid lands at y = 80 + 480 = 560, leaving 40 px of canvas tail for
-- the wave-preview card row.
M.OFFSET_X = math.floor((800 - M.WIDTH * M.TILE) / 2)  -- 80
M.OFFSET_Y = 80

-- 1-indexed tile coords (Lua convention). (1,1) is top-left.

function M.tile_to_pixel(tx, ty)
    return M.OFFSET_X + (tx - 1) * M.TILE,
           M.OFFSET_Y + (ty - 1) * M.TILE
end

function M.pixel_to_tile(px, py)
    local tx = math.floor((px - M.OFFSET_X) / M.TILE) + 1
    local ty = math.floor((py - M.OFFSET_Y) / M.TILE) + 1
    if not M.in_bounds(tx, ty) then return nil end
    return tx, ty
end

function M.in_bounds(tx, ty)
    return tx >= 1 and tx <= M.WIDTH
       and ty >= 1 and ty <= M.HEIGHT
end

-- 4-directional cardinal neighbors. Diagonals intentionally excluded:
-- keeps A* paths predictable and combat adjacency unambiguous.
local DIRS = { { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } }

function M.neighbors(tx, ty)
    local out = {}
    for i = 1, #DIRS do
        local nx, ny = tx + DIRS[i][1], ty + DIRS[i][2]
        if M.in_bounds(nx, ny) then
            out[#out + 1] = { nx, ny }
        end
    end
    return out
end

function M.manhattan(ax, ay, bx, by)
    return math.abs(ax - bx) + math.abs(ay - by)
end

return M
