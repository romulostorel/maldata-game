-- Hero classes (Warrior, Archer, Mage) and procgen of stats with the
-- per-class variance defined in v1. Factory rolls a class and HP/ATK
-- using a caller-provided rand fn, so determinism is the caller's choice.

local M = {}

M.WARRIOR = "warrior"
M.ARCHER  = "archer"
M.MAGE    = "mage"

-- v1 stat sheet: hp / hp_var / atk / atk_var / range / placeholder color.
M.CLASSES = {
    [M.WARRIOR] = { hp = 15, hp_var = 3, atk = 4, atk_var = 1, range = 1,
                    color = { 1.00, 0.55, 0.20 } },
    [M.ARCHER]  = { hp = 10, hp_var = 2, atk = 5, atk_var = 1, range = 3,
                    color = { 0.80, 0.95, 1.00 } },
    [M.MAGE]    = { hp = 8,  hp_var = 2, atk = 6, atk_var = 2, range = 4,
                    color = { 0.95, 0.50, 0.90 } },
}

local CLASS_KEYS = { M.WARRIOR, M.ARCHER, M.MAGE }

-- Uniform integer in [base - var, base + var].
local function roll(rand, base, var)
    return base + rand(2 * var + 1) - var - 1
end

-- rand: function(n) -> integer in 1..n. Use rand.new(seed) for determinism
-- or math.random for arbitrary variation.
function M.new(rand, x, y)
    local class_key = CLASS_KEYS[rand(#CLASS_KEYS)]
    local c = M.CLASSES[class_key]
    local hp = roll(rand, c.hp, c.hp_var)
    local atk = roll(rand, c.atk, c.atk_var)
    return {
        class = class_key,
        x = x, y = y,
        hp = hp, max_hp = hp,
        atk = atk,
        range = c.range,
        alive = true,
    }
end

return M
