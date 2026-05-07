-- Tile sprite generators (32×32). Each function is pure: same seed → same
-- image. Variations come from the seed; the registry in assets.lua decides
-- how many variations to bake.
--
-- All four tile types share the same stone floor base so adjacent tiles tile
-- visually without seams; the door and treasure draw their motif on top.

local rand    = require("src.rand")
local sprite  = require("src.gen.sprite_base")
local palette = require("src.palette")

local M = {}

M.SIZE = 32

local function speckle(c, rng, color, count)
    for _ = 1, count do
        local x, y = rng(c.w), rng(c.h)
        c.pixels[y][x] = color
    end
end

-- Like speckle, but only repaints cells that currently hold `over_color` —
-- preserves brick mortar / structural lines.
local function speckle_over(c, rng, color, over_color, count)
    for _ = 1, count do
        local x, y = rng(c.w), rng(c.h)
        if c.pixels[y][x] == over_color then
            c.pixels[y][x] = color
        end
    end
end

local function paint_floor_base(c, rng)
    sprite.fill_rect(c, 1, 1, M.SIZE, M.SIZE, palette.stone)
    speckle(c, rng, palette.stone_dark, 28)
    speckle(c, rng, palette.stone_light, 4)
end

function M.gen_floor(seed)
    local rng = rand.new(seed)
    local c = sprite.new_canvas(M.SIZE, M.SIZE)
    paint_floor_base(c, rng)
    return sprite.to_image(c)
end

function M.gen_wall(seed)
    local rng = rand.new(seed)
    local c = sprite.new_canvas(M.SIZE, M.SIZE)

    sprite.fill_rect(c, 1, 1, M.SIZE, M.SIZE, palette.stone_light)

    -- Three brick rows separated by horizontal mortar at y=11 and y=22.
    -- Vertical joints stagger between rows for a real masonry look.
    sprite.fill_rect(c, 1, 11, M.SIZE, 1, palette.stone_dark)
    sprite.fill_rect(c, 1, 22, M.SIZE, 1, palette.stone_dark)
    sprite.fill_rect(c, 16, 1, 1, 10, palette.stone_dark)   -- top row joint
    sprite.fill_rect(c,  8, 12, 1, 10, palette.stone_dark)  -- mid offset
    sprite.fill_rect(c, 24, 12, 1, 10, palette.stone_dark)
    sprite.fill_rect(c, 16, 23, 1, 10, palette.stone_dark)  -- bottom row joint

    -- Top-edge highlight (1 px) so walls catch a hint of light.
    sprite.fill_rect(c, 1, 1, M.SIZE, 1, palette.stone)

    speckle_over(c, rng, palette.stone, palette.stone_light, 22)
    speckle_over(c, rng, palette.stone_dark, palette.stone_light, 6)

    return sprite.to_image(c)
end

function M.gen_door(seed)
    local rng = rand.new(seed)
    local c = sprite.new_canvas(M.SIZE, M.SIZE)
    paint_floor_base(c, rng)

    -- Stone arch / dark recess behind the door.
    sprite.fill_rect(c, 4, 1, 24, 30, palette.void)

    -- Wood door body, vertical planks with rust grain stripes.
    sprite.fill_rect(c, 6, 3, 20, 27, palette.rust_dark)
    sprite.fill_rect(c, 10, 3, 1, 27, palette.rust)
    sprite.fill_rect(c, 16, 3, 1, 27, palette.rust)
    sprite.fill_rect(c, 22, 3, 1, 27, palette.rust)

    -- Iron straps top and bottom, plus a top highlight on the lintel.
    sprite.fill_rect(c, 6, 3, 20, 1, palette.rust)
    sprite.fill_rect(c, 6, 9, 20, 1, palette.void)
    sprite.fill_rect(c, 6, 22, 20, 1, palette.void)

    -- Brass knob.
    sprite.fill_rect(c, 22, 16, 2, 2, palette.gold_accent)
    sprite.set_pixel(c, 23, 16, palette.paper)

    return sprite.to_image(c)
end

function M.gen_treasure(seed)
    local rng = rand.new(seed)
    local c = sprite.new_canvas(M.SIZE, M.SIZE)
    paint_floor_base(c, rng)

    -- Drop-shadow under the chest so it sits on the floor.
    sprite.fill_rect(c, 9, 26, 16, 1, palette.void)

    -- Chest body + lighter top (lid).
    sprite.fill_rect(c, 9, 14, 16, 12, palette.rust_dark)
    sprite.fill_rect(c, 9, 14, 16, 4, palette.rust)
    sprite.fill_rect(c, 9, 18, 16, 1, palette.void)        -- lid seam
    sprite.fill_rect(c, 9, 14, 1, 12, palette.rust)         -- left highlight
    sprite.fill_rect(c, 24, 14, 1, 12, palette.rust_dark)   -- right shadow

    -- Lock plate with keyhole.
    sprite.fill_rect(c, 15, 19, 3, 4, palette.gold_accent)
    sprite.set_pixel(c, 16, 21, palette.void)

    -- Glints on the lid.
    sprite.set_pixel(c, 12, 15, palette.paper)
    sprite.set_pixel(c, 13, 16, palette.gold_accent)

    -- Sparkles around the chest to reinforce "objective".
    sprite.set_pixel(c,  5,  9, palette.gold_accent)
    sprite.set_pixel(c, 28,  7, palette.paper)
    sprite.set_pixel(c,  4, 28, palette.paper)
    sprite.set_pixel(c, 29, 24, palette.gold_accent)

    return sprite.to_image(c)
end

return M
