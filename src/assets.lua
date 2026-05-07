-- Central asset registry. All procgen images are baked once at startup and
-- then handed out by reference — the rest of the engine never calls a
-- generator directly. Variation seeds are fixed so the visual identity of
-- the game is reproducible across runs.

local tile_gen = require("src.gen.tile_gen")

local M = {}

M.tiles = {
    floor = {},
    wall  = {},
    door  = nil,
    treasure = nil,
}

local FLOOR_VARIATIONS = 3
local WALL_VARIATIONS  = 3

function M.load()
    for i = 1, FLOOR_VARIATIONS do
        M.tiles.floor[i] = tile_gen.gen_floor(1000 + i)
    end
    for i = 1, WALL_VARIATIONS do
        M.tiles.wall[i] = tile_gen.gen_wall(2000 + i)
    end
    M.tiles.door     = tile_gen.gen_door(3000)
    M.tiles.treasure = tile_gen.gen_treasure(4000)
end

-- Stable per-position variation index. Multipliers are coprime with the
-- variation counts so the pattern never falls into a visible stripe.
function M.tile_variation(tx, ty, count)
    return ((tx * 7 + ty * 13) % count) + 1
end

return M
