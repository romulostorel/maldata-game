-- Procedural dungeon generator: deterministic given a seed.
-- v1 layout: a single rectangular room with a walled perimeter, one door
-- (non-corner perimeter tile carved to floor), and a treasure on an
-- interior floor tile at least MIN_DOOR_TREASURE_DIST manhattan steps
-- away from the door.
-- Pure logic — no LÖVE calls, runs headless under busted.

local grid = require("src.grid")
local rand = require("src.rand")

local M = {}

M.FLOOR = 0
M.WALL = 1
M.MIN_DOOR_TREASURE_DIST = 6

local function build_room(W, H)
    local g = {}
    for y = 1, H do
        g[y] = {}
        for x = 1, W do
            local on_border = (x == 1 or x == W or y == 1 or y == H)
            g[y][x] = on_border and M.WALL or M.FLOOR
        end
    end
    return g
end

-- Random non-corner perimeter tile.
local function random_door(rng, W, H)
    local edge = rng(4) -- 1=top 2=right 3=bottom 4=left
    if edge == 1 then return rng(W - 2) + 1, 1 end
    if edge == 2 then return W, rng(H - 2) + 1 end
    if edge == 3 then return rng(W - 2) + 1, H end
    return 1, rng(H - 2) + 1
end

local function random_interior(rng, W, H)
    return rng(W - 2) + 1, rng(H - 2) + 1
end

function M.generate(seed)
    local rng = rand.new(seed)
    local W, H = grid.WIDTH, grid.HEIGHT

    local g = build_room(W, H)

    local dx, dy = random_door(rng, W, H)
    g[dy][dx] = M.FLOOR -- carve the door

    local tx, ty = random_interior(rng, W, H)
    for _ = 1, 100 do
        if grid.manhattan(dx, dy, tx, ty) >= M.MIN_DOOR_TREASURE_DIST then
            break
        end
        tx, ty = random_interior(rng, W, H)
    end

    return {
        seed = seed,
        grid = g,
        entrance = { x = dx, y = dy },
        treasure = { x = tx, y = ty },
    }
end

return M
