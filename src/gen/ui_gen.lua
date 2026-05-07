-- UI element generators (HP bar, button, phase icon, panel). Same pipeline
-- as the rest of /gen: paint into a canvas with sprite_base primitives, bake
-- to an Image at the end. ui.lua draws the baked Images and overlays text /
-- HP fill on top.
--
-- Sizes are caller-driven so ui.lua can tune dimensions without changing
-- this module.

local sprite  = require("src.gen.sprite_base")
local palette = require("src.palette")

local M = {}

-- 1-px void perimeter on a w×h canvas. Helper used by every chrome element.
local function void_border(c, w, h)
    sprite.fill_rect(c, 1, 1, w, 1, palette.void)
    sprite.fill_rect(c, 1, h, w, 1, palette.void)
    sprite.fill_rect(c, 1, 1, 1, h, palette.void)
    sprite.fill_rect(c, w, 1, 1, h, palette.void)
end

-- HP bar chrome: void border around a stone_dark interior. ui.lua paints
-- the colored fill rect on top, inset by 1 px (the inner area is w-2 × h-2).
function M.gen_hp_bar(w, h)
    local c = sprite.new_canvas(w, h)
    sprite.fill_rect(c, 2, 2, w - 2, h - 2, palette.stone_dark)
    void_border(c, w, h)
    return sprite.to_image(c)
end

-- Beveled button. `hovered` brightens the face; bevels stay the same so the
-- button doesn't shift visually when you hover.
function M.gen_button(w, h, hovered)
    local c = sprite.new_canvas(w, h)
    local face = hovered and palette.stone_light or palette.stone

    sprite.fill_rect(c, 2, 2, w - 2, h - 2, face)
    sprite.fill_rect(c, 2, 2, w - 2, 1, palette.bone)         -- top highlight
    sprite.fill_rect(c, 2, 2, 1, h - 2, palette.bone)         -- left highlight
    sprite.fill_rect(c, 2, h - 1, w - 2, 1, palette.void)     -- bottom shadow
    sprite.fill_rect(c, w - 1, 2, 1, h - 2, palette.void)     -- right shadow

    void_border(c, w, h)
    return sprite.to_image(c)
end

-- Decorative panel: stone_dark interior with a bone bevel on top/left and a
-- stone shadow on bottom/right. Gold corner pixels mark it as "important
-- chrome" (used for the result screen card).
function M.gen_panel(w, h)
    local c = sprite.new_canvas(w, h)

    sprite.fill_rect(c, 2, 2, w - 2, h - 2, palette.stone_dark)
    sprite.fill_rect(c, 2, 2, w - 2, 1, palette.bone)
    sprite.fill_rect(c, 2, 2, 1, h - 2, palette.bone)
    sprite.fill_rect(c, 2, h - 1, w - 2, 1, palette.stone)
    sprite.fill_rect(c, w - 1, 2, 1, h - 2, palette.stone)

    void_border(c, w, h)

    sprite.set_pixel(c, 2, 2, palette.gold_accent)
    sprite.set_pixel(c, w - 1, 2, palette.gold_accent)
    sprite.set_pixel(c, 2, h - 1, palette.gold_accent)
    sprite.set_pixel(c, w - 1, h - 1, palette.gold_accent)

    return sprite.to_image(c)
end

-- ----------------------------------------------------------------------------
-- Phase icons (24×24). Each has its own silhouette so the active phase reads
-- at a glance from the HUD corner.
-- ----------------------------------------------------------------------------

local ICON_SIZE = 24

-- Hammer = build phase: vertical handle, broad horizontal head on top.
local function gen_build_icon()
    local c = sprite.new_canvas(ICON_SIZE, ICON_SIZE)

    sprite.fill_rect(c, 11,  8, 2, 13, palette.rust_dark)
    sprite.fill_rect(c, 11,  8, 1, 13, palette.rust)
    sprite.fill_rect(c, 11, 18, 2, 1, palette.gold_accent)

    sprite.fill_rect(c,  8,  4, 8, 4, palette.bone)
    sprite.fill_rect(c,  8,  4, 8, 1, palette.paper)
    sprite.fill_rect(c,  8,  7, 8, 1, palette.stone)

    sprite.outline(c, palette.void)
    return sprite.to_image(c)
end

-- Sword = invasion phase: blade pointing up with crossguard + grip.
local function gen_invasion_icon()
    local c = sprite.new_canvas(ICON_SIZE, ICON_SIZE)

    sprite.fill_rect(c, 11,  4, 2, 13, palette.bone)
    sprite.fill_rect(c, 11,  4, 1, 13, palette.paper)

    sprite.fill_rect(c,  8, 17, 8, 1, palette.gold_accent)

    sprite.fill_rect(c, 11, 18, 2, 4, palette.rust)
    sprite.fill_rect(c, 11, 21, 2, 1, palette.rust_dark)

    sprite.outline(c, palette.void)
    return sprite.to_image(c)
end

-- Skull = result phase: dome + jaw + sockets.
local function gen_result_icon()
    local c = sprite.new_canvas(ICON_SIZE, ICON_SIZE)

    sprite.fill_rect(c,  9,  6, 6, 8, palette.bone)
    sprite.fill_rect(c,  8,  7, 1, 6, palette.bone)
    sprite.fill_rect(c, 15,  7, 1, 6, palette.bone)
    sprite.fill_rect(c, 10, 14, 4, 3, palette.bone)

    sprite.fill_rect(c, 10,  9, 1, 2, palette.void)
    sprite.fill_rect(c, 13,  9, 1, 2, palette.void)
    sprite.fill_rect(c, 11, 12, 2, 1, palette.void)
    sprite.set_pixel(c, 11, 15, palette.void)
    sprite.set_pixel(c, 13, 15, palette.void)

    sprite.outline(c, palette.void)
    return sprite.to_image(c)
end

function M.gen_phase_icons()
    return {
        build    = gen_build_icon(),
        invasion = gen_invasion_icon(),
        result   = gen_result_icon(),
    }
end

return M
