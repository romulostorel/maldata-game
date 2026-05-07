-- Monster definitions (Goblin, Orc, Slime) with fixed v1 stats.
-- Factory builds a monster entity at a given tile.

local M = {}

M.GOBLIN = "goblin"
M.ORC    = "orc"
M.SLIME  = "slime"

-- Stats locked per the v1 design sheet. Colors picked to be distinct
-- from the dungeon palette (entrance cyan, treasure gold).
M.TYPES = {
    [M.GOBLIN] = { hp = 5,  atk = 2, range = 1, color = { 0.40, 0.85, 0.30 } },
    [M.ORC]    = { hp = 10, atk = 4, range = 1, color = { 0.85, 0.30, 0.30 } },
    [M.SLIME]  = { hp = 8,  atk = 3, range = 1, color = { 0.65, 0.40, 0.95 } },
}

function M.new(type_key, x, y)
    local t = M.TYPES[type_key]
    return {
        type = type_key,
        x = x, y = y,
        hp = t.hp, max_hp = t.hp,
        atk = t.atk,
        range = t.range,
        alive = true,
    }
end

return M
