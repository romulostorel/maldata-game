-- Combat resolution: range checks (Manhattan, matching the 4-cardinal
-- movement) and damage application. Pure functions — no side effects
-- beyond the entities passed in.

local grid = require("src.grid")

local M = {}

function M.in_range(attacker, target)
    return grid.manhattan(attacker.x, attacker.y, target.x, target.y) <= attacker.range
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
