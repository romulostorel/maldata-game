-- Hero classes (Warrior, Archer, Mage) and procgen of stats with the
-- per-class variance defined in v1. Factory rolls a class and HP/ATK
-- using a caller-provided rand fn, so determinism is the caller's choice.
--
-- Class identity is two-fold:
--   * Stat tradeoffs: tanky (Warrior), balanced (Archer), glass cannon (Mage).
--   * Behavioral passives (resolved in state.step_invasion):
--       Warrior — leads the wave; retaliates `retaliate` dmg to any
--                 adjacent attacker that hit it.
--       Archer  — focus-fires the monster with the lowest HP in range
--                 (vs. the default "first found").
--       Mage    — splash damage on every attack: half (floor) of `atk` to
--                 each cardinal-adjacent monster around the main target.
-- The behaviors are encoded in state.lua, but the per-class numbers (e.g.,
-- retaliate amount) live here so balance lives next to stats.

local M = {}

M.WARRIOR = "warrior"
M.ARCHER  = "archer"
M.MAGE    = "mage"

-- v1.5 stat sheet: hp / hp_var / atk / atk_var / range / retaliate / color.
-- Warrior is the lone melee tank. Archer + Mage are range 2 with wall
-- line-of-sight — they get one free swing before the lead monster reaches
-- adjacency, which the player counterbalances by walling chokepoints
-- so the bolt/arrow path is broken. retaliate > 0 means "deal N dmg back
-- when struck adjacent"; only Warrior has it.
--
-- HP nudges from the all-melee era: Archer 10→9 and Mage 8→7 to offset
-- the free-tick advantage of range 2.
M.CLASSES = {
    [M.WARRIOR] = { hp = 15, hp_var = 3, atk = 4, atk_var = 1, range = 1,
                    retaliate = 1,
                    color = { 1.00, 0.55, 0.20 } },
    [M.ARCHER]  = { hp = 9,  hp_var = 2, atk = 5, atk_var = 1, range = 2,
                    retaliate = 0,
                    color = { 0.80, 0.95, 1.00 } },
    [M.MAGE]    = { hp = 7,  hp_var = 2, atk = 6, atk_var = 2, range = 2,
                    retaliate = 0,
                    color = { 0.95, 0.50, 0.90 } },
}

-- Mage AoE divisor: splash damage = floor(atk / MAGE_SPLASH_DIVISOR).
-- Each cardinal-adjacent alive monster around the main target takes the
-- splash. Snapshotted before application so chain reactions (e.g., a
-- splashed slime splits) don't double-dip in the same attack.
M.MAGE_SPLASH_DIVISOR = 2

local CLASS_KEYS = { M.WARRIOR, M.ARCHER, M.MAGE }

-- Uniform integer in [base - var, base + var].
local function roll(rand, base, var)
    return base + rand(2 * var + 1) - var - 1
end

-- rand: function(n) -> integer in 1..n. Use rand.new(seed) for determinism
-- or math.random for arbitrary variation.
-- buff (optional, default 0): added uniformly to base hp and atk before
-- the per-class variance roll. State.lua scales this with the wave count
-- to keep the run pressure rising once the wave-size cap kicks in.
function M.new(rand, x, y, buff)
    buff = buff or 0
    local class_key = CLASS_KEYS[rand(#CLASS_KEYS)]
    local c = M.CLASSES[class_key]
    local hp = roll(rand, c.hp + buff, c.hp_var)
    local atk = roll(rand, c.atk + buff, c.atk_var)
    return {
        class = class_key,
        x = x, y = y,
        hp = hp, max_hp = hp,
        atk = atk,
        range = c.range,
        retaliate = c.retaliate,
        alive = true,
    }
end

return M
