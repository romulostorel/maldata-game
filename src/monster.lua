-- Monster definitions (Goblin, Orc, Slime) with fixed v1 stats and the
-- per-type passives that give each species a strategic identity:
--   Goblin  → cluster bonus (+1 ATK per cardinal-adjacent alive goblin)
--   Orc     → corpse blocks the tile for ORC_CORPSE_TURNS (state.lua)
--   Slime   → splits into MINI_SLIME_COUNT mini-slimes on death (state.lua)
-- Factory builds a monster entity at a given tile.

local M = {}

M.GOBLIN = "goblin"
M.ORC    = "orc"
M.SLIME  = "slime"

-- Goblin cluster cap: 4 cardinal neighbors → up to +4 ATK. Caps naturally
-- because Manhattan-1 has only four cells.
M.GOBLIN_CLUSTER_BONUS = 1

-- Stats locked per the v1 design sheet. `cost` feeds the build budget
-- (state.BUDGET); it's the only knob that lets the player trade quantity
-- against quality. Colors picked to be distinct from the dungeon palette
-- (entrance cyan, treasure gold).
M.TYPES = {
    [M.GOBLIN] = { hp = 5,  atk = 2, range = 1, cost = 2, color = { 0.40, 0.85, 0.30 } },
    [M.ORC]    = { hp = 10, atk = 4, range = 1, cost = 4, color = { 0.85, 0.30, 0.30 } },
    [M.SLIME]  = { hp = 8,  atk = 3, range = 1, cost = 3, color = { 0.65, 0.40, 0.95 } },
}

-- Mini-slime spawned by a slime's death. Halved HP and reduced ATK so a
-- slime + its pair of splits beats a single orc on positional disruption,
-- not raw stats. Marked is_mini so a chain split is impossible.
M.MINI_SLIME = { hp = 3, atk = 2 }

function M.new(type_key, x, y)
    local t = M.TYPES[type_key]
    return {
        type = type_key,
        x = x, y = y,
        hp = t.hp, max_hp = t.hp,
        atk = t.atk,
        range = t.range,
        cost = t.cost,
        alive = true,
    }
end

-- Slime split factory. Cost = 0: minis are not paid for, they spawn as a
-- death payoff. is_mini = true gates the next split from recursing.
function M.new_mini_slime(x, y)
    return {
        type = M.SLIME,
        x = x, y = y,
        hp = M.MINI_SLIME.hp,
        max_hp = M.MINI_SLIME.hp,
        atk = M.MINI_SLIME.atk,
        range = 1,
        cost = 0,
        alive = true,
        is_mini = true,
    }
end

-- Goblin cluster passive. Each cardinal-adjacent alive goblin (NOT counting
-- self) adds GOBLIN_CLUSTER_BONUS to atk. Non-goblins return their base atk.
-- Iterates the full monsters list — fine at v1 grid size (< 200 monsters).
function M.effective_atk(self, monsters)
    if self.type ~= M.GOBLIN then return self.atk end
    local bonus = 0
    for _, other in ipairs(monsters) do
        if other ~= self
           and other.alive
           and other.type == M.GOBLIN
           and math.abs(other.x - self.x) + math.abs(other.y - self.y) == 1
        then
            bonus = bonus + M.GOBLIN_CLUSTER_BONUS
        end
    end
    return self.atk + bonus
end

return M
