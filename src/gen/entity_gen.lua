-- Entity sprite generators (24×24). Each gen function takes (pose, seed)
-- where pose ∈ { "idle_a", "idle_b", "walk_a", "walk_b" }.
--
-- Pipeline per entity:
--   1. paint_<x>_body(c, dy)        -- head/torso/arms (above legs)
--   2. mirror_x  (skipped for slime: highlight is intentionally asymmetric)
--   3. paint_<x>_legs(c, lifted)    -- legs/feet, asymmetric for walk poses
--   4. outline (in `void`)
--   5. paint_<x>_weapon(c)          -- asymmetric prop, drawn after outline
--                                      so 1-px elements (string, glints) stay crisp
--
-- Pose handling differs by entity:
--   * Bipeds with leg-lifting walk (goblin, warrior, archer):
--       idle_b bobs the body up 1 px; walk_a/walk_b lift one foot.
--   * "Bobbers" (orc, slime, mage) — legs are a single block or hidden under
--       robe — both _b poses bob the whole body; walk == idle.

local rand    = require("src.rand")
local sprite  = require("src.gen.sprite_base")
local palette = require("src.palette")

local M = {}

M.SIZE = 24
M.POSES = { "idle_a", "idle_b", "walk_a", "walk_b" }

-- Pose helpers -------------------------------------------------------------
local function biped_dy(pose)
    return (pose == "idle_b") and -1 or 0
end

local function biped_lifted(pose)
    if pose == "walk_a" then return "left" end
    if pose == "walk_b" then return "right" end
    return nil
end

local function bobber_dy(pose)
    -- No leg motion: both _b poses bob the body.
    return (pose == "idle_b" or pose == "walk_b") and -1 or 0
end

-- ============================================================================
-- Goblin (biped, leg-lifting walk)
-- ============================================================================

local function paint_goblin_body(c, dy)
    local body  = palette.moss
    local shade = palette.moss_dark
    local eye   = palette.gold_accent
    local belt  = palette.rust_dark

    sprite.set_pixel(c,  9, 11 + dy, body)         -- ear
    sprite.set_pixel(c, 10, 10 + dy, body)
    sprite.fill_rect(c, 10, 11 + dy, 3, 3, body)   -- skull
    sprite.fill_rect(c, 11, 10 + dy, 2, 1, body)
    sprite.fill_rect(c, 10, 13 + dy, 3, 1, shade)  -- brow
    sprite.set_pixel(c, 11, 12 + dy, eye)
    sprite.fill_rect(c, 10, 14 + dy, 3, 4, body)   -- torso
    sprite.fill_rect(c, 10, 17 + dy, 3, 1, shade)
    sprite.fill_rect(c, 10, 18 + dy, 3, 1, belt)
    sprite.fill_rect(c,  9, 14 + dy, 1, 4, body)   -- arm
end

local function paint_goblin_legs(c, lifted)
    local body  = palette.moss
    local shade = palette.moss_dark

    if lifted == nil then
        sprite.fill_rect(c, 10, 19, 2, 3, body)
        sprite.fill_rect(c, 14, 19, 2, 3, body)
        sprite.fill_rect(c,  9, 22, 3, 1, shade)
        sprite.fill_rect(c, 13, 22, 3, 1, shade)
    elseif lifted == "left" then
        sprite.fill_rect(c, 10, 20, 2, 2, body)
        sprite.fill_rect(c, 14, 19, 2, 3, body)
        sprite.fill_rect(c,  9, 21, 3, 1, shade)
        sprite.fill_rect(c, 13, 22, 3, 1, shade)
    else  -- "right"
        sprite.fill_rect(c, 10, 19, 2, 3, body)
        sprite.fill_rect(c, 14, 20, 2, 2, body)
        sprite.fill_rect(c,  9, 22, 3, 1, shade)
        sprite.fill_rect(c, 13, 21, 3, 1, shade)
    end
end

local function paint_goblin_weapon(c)
    sprite.fill_rect(c, 17, 14, 2, 5, palette.rust)
    sprite.set_pixel(c, 18, 13, palette.rust_dark)
end

function M.gen_goblin(pose, seed)
    pose = pose or "idle_a"
    rand.new(seed or 0)
    local c = sprite.new_canvas(M.SIZE, M.SIZE)
    paint_goblin_body(c, biped_dy(pose))
    sprite.mirror_x(c)
    paint_goblin_legs(c, biped_lifted(pose))
    sprite.outline(c, palette.void)
    paint_goblin_weapon(c)
    return sprite.to_image(c)
end

-- ============================================================================
-- Orc (biped, but legs are a single block — bobber-style walk)
-- ============================================================================

local function paint_orc_body(c, dy)
    local body  = palette.rust
    local shade = palette.rust_dark
    local eye   = palette.blood
    local tusk  = palette.bone

    sprite.fill_rect(c,  8,  6 + dy, 5, 5, body)
    sprite.fill_rect(c,  8, 10 + dy, 5, 1, shade)
    sprite.set_pixel(c, 10,  8 + dy, eye)
    sprite.set_pixel(c, 11, 11 + dy, tusk)
    sprite.set_pixel(c, 11, 12 + dy, tusk)
    sprite.fill_rect(c,  9, 11 + dy, 4, 1, body)
    sprite.fill_rect(c,  7, 12 + dy, 6, 5, body)
    sprite.fill_rect(c,  7, 15 + dy, 6, 1, shade)
    sprite.fill_rect(c,  6, 13 + dy, 1, 5, body)
    sprite.fill_rect(c,  8, 17 + dy, 5, 1, palette.void)
end

local function paint_orc_legs(c)
    local body  = palette.rust
    local shade = palette.rust_dark

    sprite.fill_rect(c,  8, 18, 10, 4, body)
    sprite.fill_rect(c,  8, 20, 10, 1, shade)
    sprite.fill_rect(c,  7, 22, 3, 1, palette.void)
    sprite.fill_rect(c, 16, 22, 3, 1, palette.void)
end

function M.gen_orc(pose, seed)
    pose = pose or "idle_a"
    rand.new(seed or 0)
    local c = sprite.new_canvas(M.SIZE, M.SIZE)
    paint_orc_body(c, bobber_dy(pose))
    sprite.mirror_x(c)
    paint_orc_legs(c)
    sprite.outline(c, palette.void)
    return sprite.to_image(c)
end

-- ============================================================================
-- Slime (no legs, no mirror — highlight is asymmetric on purpose)
-- ============================================================================

local function paint_slime_body(c, dy)
    local body  = palette.ice
    local belly = palette.arcane
    local hi    = palette.paper
    local eye   = palette.void

    sprite.fill_rect(c,  9, 12 + dy, 7, 1, body)
    sprite.fill_rect(c,  8, 13 + dy, 9, 1, body)
    sprite.fill_rect(c,  7, 14 + dy, 11, 6, body)
    sprite.fill_rect(c,  8, 20 + dy, 9, 1, body)
    sprite.fill_rect(c,  9, 21 + dy, 7, 1, body)

    sprite.fill_rect(c,  8, 19 + dy, 9, 1, belly)

    sprite.fill_rect(c, 10, 15 + dy, 1, 2, eye)
    sprite.fill_rect(c, 14, 15 + dy, 1, 2, eye)

    sprite.set_pixel(c,  9, 14 + dy, hi)
    sprite.set_pixel(c, 10, 13 + dy, hi)

    sprite.set_pixel(c,  8, 22 + dy, body)
    sprite.set_pixel(c, 16, 22 + dy, body)
end

function M.gen_slime(pose, seed)
    pose = pose or "idle_a"
    rand.new(seed or 0)
    local c = sprite.new_canvas(M.SIZE, M.SIZE)
    paint_slime_body(c, bobber_dy(pose))
    sprite.outline(c, palette.void)
    return sprite.to_image(c)
end

-- ============================================================================
-- Warrior (biped, leg-lifting walk; sword + shield post-outline)
-- ============================================================================

local function paint_warrior_body(c, dy)
    local armor = palette.bone
    local shade = palette.stone_light
    local skin  = palette.flesh
    local plume = palette.blood
    local trim  = palette.gold_accent

    sprite.set_pixel(c, 12, 4 + dy, plume)
    sprite.set_pixel(c, 11, 5 + dy, plume)
    sprite.set_pixel(c, 12, 5 + dy, plume)
    sprite.fill_rect(c,  9,  6 + dy, 4, 4, armor)
    sprite.fill_rect(c,  9,  6 + dy, 4, 1, shade)
    sprite.fill_rect(c,  9,  8 + dy, 4, 1, palette.void)
    sprite.fill_rect(c, 10, 10 + dy, 3, 1, skin)
    sprite.set_pixel(c,  7, 11 + dy, armor)
    sprite.set_pixel(c,  8, 11 + dy, armor)
    sprite.fill_rect(c,  8, 12 + dy, 5, 5, armor)
    sprite.fill_rect(c,  8, 12 + dy, 5, 1, shade)
    sprite.set_pixel(c, 12, 13 + dy, trim)
    sprite.set_pixel(c, 12, 14 + dy, trim)
    sprite.fill_rect(c,  7, 13 + dy, 1, 4, armor)
    sprite.fill_rect(c,  9, 17 + dy, 4, 1, palette.void)
end

local function paint_warrior_legs(c, lifted)
    local armor = palette.bone
    local shade = palette.stone_light
    local foot  = palette.void

    if lifted == nil then
        sprite.fill_rect(c, 9, 18, 8, 4, armor)
        sprite.fill_rect(c, 9, 18, 8, 1, shade)
        sprite.fill_rect(c, 9, 22, 8, 1, foot)
    elseif lifted == "left" then
        sprite.fill_rect(c,  9, 19, 3, 2, armor)
        sprite.fill_rect(c, 14, 18, 3, 4, armor)
        sprite.fill_rect(c,  9, 19, 3, 1, shade)
        sprite.fill_rect(c, 14, 18, 3, 1, shade)
        sprite.fill_rect(c,  9, 21, 3, 1, foot)
        sprite.fill_rect(c, 14, 22, 3, 1, foot)
    else  -- "right"
        sprite.fill_rect(c,  9, 18, 3, 4, armor)
        sprite.fill_rect(c, 14, 19, 3, 2, armor)
        sprite.fill_rect(c,  9, 18, 3, 1, shade)
        sprite.fill_rect(c, 14, 19, 3, 1, shade)
        sprite.fill_rect(c,  9, 22, 3, 1, foot)
        sprite.fill_rect(c, 14, 21, 3, 1, foot)
    end
end

local function paint_warrior_weapon(c)
    sprite.fill_rect(c, 4, 13, 2, 6, palette.rust_dark)
    sprite.fill_rect(c, 4, 13, 2, 1, palette.bone)
    sprite.set_pixel(c, 5, 16, palette.gold_accent)

    sprite.fill_rect(c, 19,  8, 2, 9, palette.bone)
    sprite.set_pixel(c, 20,  7, palette.paper)
    sprite.fill_rect(c, 18, 17, 4, 1, palette.gold_accent)
    sprite.fill_rect(c, 19, 18, 2, 2, palette.rust)
end

function M.gen_warrior(pose, seed)
    pose = pose or "idle_a"
    rand.new(seed or 0)
    local c = sprite.new_canvas(M.SIZE, M.SIZE)
    paint_warrior_body(c, biped_dy(pose))
    sprite.mirror_x(c)
    paint_warrior_legs(c, biped_lifted(pose))
    sprite.outline(c, palette.void)
    paint_warrior_weapon(c)
    return sprite.to_image(c)
end

-- ============================================================================
-- Archer (biped, leg-lifting walk; bow post-outline)
-- ============================================================================

local function paint_archer_body(c, dy)
    local hood  = palette.moss_dark
    local skin  = palette.flesh
    local tunic = palette.moss
    local belt  = palette.rust_dark

    sprite.fill_rect(c, 10, 6 + dy, 3, 1, hood)
    sprite.fill_rect(c,  9, 7 + dy, 4, 4, hood)
    sprite.fill_rect(c, 10, 8 + dy, 3, 2, palette.void)
    sprite.set_pixel(c, 11, 9 + dy, skin)
    sprite.set_pixel(c, 12, 9 + dy, skin)
    sprite.fill_rect(c, 11, 10 + dy, 2, 1, skin)
    sprite.fill_rect(c,  8, 11 + dy, 5, 4, hood)
    sprite.fill_rect(c,  9, 15 + dy, 4, 1, belt)
    sprite.fill_rect(c,  9, 16 + dy, 4, 3, tunic)
end

local function paint_archer_legs(c, lifted)
    local trousers = palette.rust_dark
    local boots    = palette.void

    if lifted == nil then
        sprite.fill_rect(c, 9, 19, 8, 3, trousers)
        sprite.fill_rect(c, 9, 22, 8, 1, boots)
    elseif lifted == "left" then
        sprite.fill_rect(c,  9, 20, 3, 2, trousers)
        sprite.fill_rect(c, 14, 19, 3, 3, trousers)
        sprite.fill_rect(c,  9, 21, 3, 1, boots)
        sprite.fill_rect(c, 14, 22, 3, 1, boots)
    else  -- "right"
        sprite.fill_rect(c,  9, 19, 3, 3, trousers)
        sprite.fill_rect(c, 14, 20, 3, 2, trousers)
        sprite.fill_rect(c,  9, 22, 3, 1, boots)
        sprite.fill_rect(c, 14, 21, 3, 1, boots)
    end
end

local function paint_archer_weapon(c)
    sprite.set_pixel(c, 18,  7, palette.rust)
    sprite.fill_rect(c, 19,  8, 1, 9, palette.rust)
    sprite.set_pixel(c, 18, 17, palette.rust)
    sprite.fill_rect(c, 18,  9, 1, 7, palette.bone)
    sprite.set_pixel(c, 17, 12, palette.gold_accent)
end

function M.gen_archer(pose, seed)
    pose = pose or "idle_a"
    rand.new(seed or 0)
    local c = sprite.new_canvas(M.SIZE, M.SIZE)
    paint_archer_body(c, biped_dy(pose))
    sprite.mirror_x(c)
    paint_archer_legs(c, biped_lifted(pose))
    sprite.outline(c, palette.void)
    paint_archer_weapon(c)
    return sprite.to_image(c)
end

-- ============================================================================
-- Mage (legs hidden under robe — bobber-style walk; staff post-outline)
-- ============================================================================

local function paint_mage_body(c, dy)
    local robe  = palette.arcane
    local skin  = palette.flesh
    local beard = palette.bone

    sprite.set_pixel(c, 12, 3 + dy, robe)
    sprite.fill_rect(c, 11, 4 + dy, 2, 1, robe)
    sprite.fill_rect(c, 11, 5 + dy, 2, 1, robe)
    sprite.fill_rect(c, 10, 6 + dy, 3, 1, robe)
    sprite.fill_rect(c,  9, 7 + dy, 4, 1, robe)

    sprite.fill_rect(c, 10, 8 + dy, 3, 2, skin)
    sprite.set_pixel(c, 11, 9 + dy, palette.void)

    sprite.fill_rect(c, 10, 10 + dy, 3, 2, beard)

    sprite.fill_rect(c,  9, 12 + dy, 4, 2, robe)
    sprite.fill_rect(c,  9, 14 + dy, 4, 7, robe)
    sprite.fill_rect(c,  8, 21 + dy, 5, 1, robe)
    sprite.fill_rect(c, 12, 14 + dy, 1, 7, palette.void)
end

local function paint_mage_weapon(c)
    sprite.fill_rect(c, 18,  9, 1, 13, palette.rust_dark)
    sprite.fill_rect(c, 17,  6, 3, 3, palette.ember)
    sprite.set_pixel(c, 18,  7, palette.gold_accent)
    sprite.set_pixel(c, 17,  7, palette.paper)
end

function M.gen_mage(pose, seed)
    pose = pose or "idle_a"
    rand.new(seed or 0)
    local c = sprite.new_canvas(M.SIZE, M.SIZE)
    paint_mage_body(c, bobber_dy(pose))
    sprite.mirror_x(c)
    sprite.outline(c, palette.void)
    paint_mage_weapon(c)
    return sprite.to_image(c)
end

-- ============================================================================
-- Type → generator dispatch (used by anim_gen.lua and the registry)
-- ============================================================================

M.GENERATORS = {
    goblin  = M.gen_goblin,
    orc     = M.gen_orc,
    slime   = M.gen_slime,
    warrior = M.gen_warrior,
    archer  = M.gen_archer,
    mage    = M.gen_mage,
}

return M
