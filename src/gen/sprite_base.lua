-- Sprite generation primitives. Pure functions over an in-memory pixel grid
-- (Lua tables, not ImageData — much faster to mutate during generation).
-- Bake to a love.graphics.Image at the end with to_image.
--
-- Conventions:
--   * 1-indexed coordinates: (1,1) is top-left.
--   * A pixel is either nil (transparent) or {r, g, b, a?} normalized 0-1.
--   * Pixel colors are stored by reference; helpers in palette.lua return new
--     tables so this is safe. Don't mutate a palette color after assigning it.

local palette = require("src.palette")

local M = {}

function M.new_canvas(w, h)
    local c = { w = w, h = h, pixels = {} }
    for y = 1, h do
        c.pixels[y] = {}
    end
    return c
end

function M.set_pixel(c, x, y, color)
    if x < 1 or x > c.w or y < 1 or y > c.h then return end
    c.pixels[y][x] = color
end

function M.get_pixel(c, x, y)
    if x < 1 or x > c.w or y < 1 or y > c.h then return nil end
    return c.pixels[y][x]
end

function M.clear(c)
    for y = 1, c.h do
        for x = 1, c.w do
            c.pixels[y][x] = nil
        end
    end
end

function M.fill_rect(c, x, y, w, h, color)
    local x1 = math.max(1, x)
    local y1 = math.max(1, y)
    local x2 = math.min(c.w, x + w - 1)
    local y2 = math.min(c.h, y + h - 1)
    for yy = y1, y2 do
        for xx = x1, x2 do
            c.pixels[yy][xx] = color
        end
    end
end

-- Mirror the left half onto the right half (vertical-axis symmetry).
-- For odd widths the center column is preserved untouched.
function M.mirror_x(c)
    local half = math.floor(c.w / 2)
    for y = 1, c.h do
        local row = c.pixels[y]
        for x = 1, half do
            row[c.w - x + 1] = row[x]
        end
    end
end

-- Trace a 1-pixel outline in `color` around every opaque pixel of `c`.
-- Operates on a snapshot so freshly-painted outline pixels don't seed more
-- outline (otherwise the silhouette would expand by 2 px on diagonals).
function M.outline(c, color)
    local snapshot = {}
    for y = 1, c.h do
        snapshot[y] = {}
        for x = 1, c.w do
            snapshot[y][x] = c.pixels[y][x]
        end
    end
    for y = 1, c.h do
        for x = 1, c.w do
            if not snapshot[y][x] then
                local n = (snapshot[y - 1] and snapshot[y - 1][x])
                       or (snapshot[y + 1] and snapshot[y + 1][x])
                       or snapshot[y][x - 1]
                       or snapshot[y][x + 1]
                if n then
                    c.pixels[y][x] = color
                end
            end
        end
    end
end

function M.to_image(c)
    local data = love.image.newImageData(c.w, c.h)
    for y = 1, c.h do
        local row = c.pixels[y]
        for x = 1, c.w do
            local p = row[x]
            if p then
                data:setPixel(x - 1, y - 1, p[1], p[2], p[3], p[4] or 1)
            end
        end
    end
    local img = love.graphics.newImage(data)
    img:setFilter("nearest", "nearest")
    return img
end

-- ---------------------------------------------------------------------------
-- Debug screen (F2). Shows a 4-step progression of the primitives applied to
-- a contrived "half-creature" shape so we can validate that fill_rect,
-- mirror_x and outline behave correctly on a real silhouette.
-- ---------------------------------------------------------------------------

local function paint_demo_half(c)
    local body  = palette.moss
    local shade = palette.moss_dark
    local eye   = palette.gold_accent
    local fang  = palette.bone

    -- Skull
    M.fill_rect(c, 7, 5, 5, 4, body)
    M.set_pixel(c, 6, 6, body)
    M.set_pixel(c, 6, 7, body)
    -- Brow shadow
    M.fill_rect(c, 7, 9, 5, 1, shade)
    -- Body
    M.fill_rect(c, 6, 10, 6, 7, body)
    M.fill_rect(c, 6, 13, 6, 1, shade)
    -- Pointy ear
    M.set_pixel(c, 5, 7, body)
    M.set_pixel(c, 4, 8, body)
    -- Eye + fang
    M.set_pixel(c, 9, 7, eye)
    M.set_pixel(c, 10, 12, fang)
    -- Foot
    M.fill_rect(c, 6, 17, 3, 2, shade)
end

local debug_cache = nil

local function build_debug_cache()
    local cache = { images = {}, labels = {} }

    local c1 = M.new_canvas(24, 24)
    local c2 = M.new_canvas(24, 24); paint_demo_half(c2)
    local c3 = M.new_canvas(24, 24); paint_demo_half(c3); M.mirror_x(c3)
    local c4 = M.new_canvas(24, 24); paint_demo_half(c4); M.mirror_x(c4)
    M.outline(c4, palette.void)

    cache.images = { M.to_image(c1), M.to_image(c2), M.to_image(c3), M.to_image(c4) }
    cache.labels = { "blank", "half (left)", "+ mirror_x", "+ outline" }
    return cache
end

function M.draw_debug()
    if not debug_cache then debug_cache = build_debug_cache() end

    local W, H = love.graphics.getWidth(), love.graphics.getHeight()

    love.graphics.setColor(palette.void[1], palette.void[2], palette.void[3], 0.96)
    love.graphics.rectangle("fill", 0, 0, W, H)

    love.graphics.setColor(palette.paper)
    love.graphics.print("SPRITE BASE PRIMITIVES — (F2 to toggle)", 16, 12)
    love.graphics.setColor(palette.bone)
    love.graphics.print("each canvas is 24x24, rendered 6x; transparent shows panel bg",
        16, 28)

    local scale       = 6
    local sprite_size = 24 * scale
    local pad         = 4
    local panel_size  = sprite_size + pad * 2
    local gap         = 24
    local total_w     = 4 * panel_size + 3 * gap
    local x0          = math.floor((W - total_w) / 2)
    local y0          = 80

    for i = 1, 4 do
        local x = x0 + (i - 1) * (panel_size + gap)

        love.graphics.setColor(palette.stone_dark)
        love.graphics.rectangle("fill", x, y0, panel_size, panel_size)
        love.graphics.setColor(palette.stone)
        love.graphics.rectangle("line", x, y0, panel_size, panel_size)

        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(debug_cache.images[i], x + pad, y0 + pad, 0, scale, scale)

        love.graphics.setColor(palette.paper)
        love.graphics.print(debug_cache.labels[i], x, y0 + panel_size + 8)
    end

    love.graphics.setColor(palette.bone)
    love.graphics.print(
        "primitives: new_canvas / set_pixel / fill_rect / mirror_x / outline / to_image",
        16, H - 28)
end

return M
