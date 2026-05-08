-- Combat resolution: range checks (Manhattan + optional wall LoS) and
-- damage application. Pure functions — no side effects beyond the
-- entities passed in.

local grid    = require("src.grid")
local dungeon = require("src.dungeon")

local M = {}

-- Wall LoS check for ranged attacks. Only invoked when manhattan is 2
-- (the only ranged distance in v1.5 — Archer + Mage have range 2).
--   Cardinal (one axis aligned): the single intermediate cell must be
--     FLOOR for the shot to pass.
--   Diagonal (|dx|=|dy|=1, manhattan=2): two L-shaped paths are possible;
--     a clear shot needs at least ONE corner cell to be FLOOR. (Both
--     corners walled = the target is walled into a pocket.)
-- Monsters and peer heroes do NOT block — heroes shoot past their
-- teammates and through enemy lines; only walls obstruct.
local function los_clear(ax, ay, tx, ty, d)
    local dx, dy = tx - ax, ty - ay
    if dx == 0 then
        local mid_y = ay + (dy > 0 and 1 or -1)
        return d.grid[mid_y] and d.grid[mid_y][ax] == dungeon.FLOOR
    end
    if dy == 0 then
        local mid_x = ax + (dx > 0 and 1 or -1)
        return d.grid[ay] and d.grid[ay][mid_x] == dungeon.FLOOR
    end
    -- Diagonal manhattan-2 case.
    local c1 = d.grid[ay] and d.grid[ay][tx] or dungeon.WALL
    local c2 = d.grid[ty] and d.grid[ty][ax] or dungeon.WALL
    return c1 == dungeon.FLOOR or c2 == dungeon.FLOOR
end

-- in_range(attacker, target [, dungeon])
-- The optional `dungeon` arg enables wall LoS for ranged attacks. Callers
-- that don't pass it (e.g., monsters, which are all melee) get the
-- pre-LoS behavior — adjacent monsters always reach their target.
function M.in_range(attacker, target, dungeon_data)
    local d = grid.manhattan(attacker.x, attacker.y,
                             target.x, target.y)
    if d > attacker.range then return false end
    if d <= 1 then return true end
    if not dungeon_data then return true end
    return los_clear(attacker.x, attacker.y,
                     target.x, target.y, dungeon_data)
end

-- damage defaults to attacker.atk; pass an explicit value when a passive
-- modifies the swing (e.g., goblin cluster bonus). Returns the dealt damage
-- so the caller can route it to the visual/audio bridge accurately.
function M.attack(attacker, target, damage)
    damage = damage or attacker.atk
    target.hp = target.hp - damage
    if target.hp <= 0 then
        target.hp = 0
        target.alive = false
    end
    return damage
end

return M
