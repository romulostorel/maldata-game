-- Combat resolution: range checks (Manhattan, matching the 4-cardinal
-- movement) and damage application. Pure functions — no side effects
-- beyond the entities passed in.

local grid = require("src.grid")

local M = {}

function M.in_range(attacker, target)
    return grid.manhattan(attacker.x, attacker.y, target.x, target.y) <= attacker.range
end

function M.attack(attacker, target)
    target.hp = target.hp - attacker.atk
    if target.hp <= 0 then
        target.hp = 0
        target.alive = false
    end
end

return M
