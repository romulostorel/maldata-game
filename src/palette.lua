-- Master palette: 16 named colors (dark fantasy) + tone helpers (lighten/darken/mix)
-- + a debug overlay (SWATCHES grid, see draw_debug). Every procgen asset must
-- pull from here so the whole game stays chromatically coherent.

local M = {}

local function rgb(r, g, b)
    return { r / 255, g / 255, b / 255 }
end

-- Neutrals: shadow → highlight ramp.
M.void          = rgb( 10,  11,  20)  -- near-black, outlines & deepest shadow
M.stone_dark    = rgb( 26,  28,  44)  -- wall body / dungeon background
M.stone         = rgb( 46,  49,  72)  -- floor body / mid-stone
M.stone_light   = rgb( 74,  78, 110)  -- stone highlight / cool light
M.bone          = rgb(184, 178, 160)  -- pale grey-cream, hero highlight & UI text
M.paper         = rgb(232, 224, 200)  -- lightest neutral, headings & emphasis

-- Creatures & flesh.
M.moss_dark     = rgb( 31,  51,  38)  -- goblin shadow / forest dark
M.moss          = rgb( 77, 122,  69)  -- goblin body / vegetal mid
M.rust_dark     = rgb( 58,  31,  21)  -- orc shadow / leather dark
M.rust          = rgb(138,  74,  44)  -- orc body / leather mid
M.flesh         = rgb(192, 133,  96)  -- warm skin tone (heroes)

-- Cool / arcane.
M.ice           = rgb( 74, 120, 150)  -- slime body / cold magic
M.arcane        = rgb( 90,  58, 130)  -- mage robe / dark purple

-- Warm / accent (use sparingly — these draw the eye).
M.ember         = rgb(215, 109,  51)  -- fire glow / attack flash
M.gold_accent   = rgb(232, 193,  74)  -- treasure / objective marker
M.blood         = rgb(176,  58,  58)  -- damage / HP / danger

-- Ordered list for the debug swatch grid. 4×4 layout:
--   row 1: neutral ramp dark→light
--   row 2: warm mid-tones (skin, paper, gold)
--   row 3: monster greens & browns
--   row 4: cools and accents
M.SWATCHES = {
    { "void",        M.void,        "#0a0b14" },
    { "stone_dark",  M.stone_dark,  "#1a1c2c" },
    { "stone",       M.stone,       "#2e3148" },
    { "stone_light", M.stone_light, "#4a4e6e" },

    { "bone",        M.bone,        "#b8b2a0" },
    { "paper",       M.paper,       "#e8e0c8" },
    { "flesh",       M.flesh,       "#c08560" },
    { "gold_accent", M.gold_accent, "#e8c14a" },

    { "moss_dark",   M.moss_dark,   "#1f3326" },
    { "moss",        M.moss,        "#4d7a45" },
    { "rust_dark",   M.rust_dark,   "#3a1f15" },
    { "rust",        M.rust,        "#8a4a2c" },

    { "ice",         M.ice,         "#4a7896" },
    { "arcane",      M.arcane,      "#5a3a82" },
    { "ember",       M.ember,       "#d76d33" },
    { "blood",       M.blood,       "#b03a3a" },
}

local function clamp01(v)
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

-- Move a color toward white. amount in [0,1]; 0 = no change, 1 = full white.
function M.lighten(c, amount)
    local t = amount or 0.2
    return {
        clamp01(c[1] + (1 - c[1]) * t),
        clamp01(c[2] + (1 - c[2]) * t),
        clamp01(c[3] + (1 - c[3]) * t),
    }
end

-- Move a color toward black. amount in [0,1]; 0 = no change, 1 = full black.
function M.darken(c, amount)
    local t = 1 - (amount or 0.2)
    return {
        clamp01(c[1] * t),
        clamp01(c[2] * t),
        clamp01(c[3] * t),
    }
end

-- Linear interpolate from a to b. t in [0,1].
function M.mix(a, b, t)
    return {
        clamp01(a[1] + (b[1] - a[1]) * t),
        clamp01(a[2] + (b[2] - a[2]) * t),
        clamp01(a[3] + (b[3] - a[3]) * t),
    }
end

-- Full-screen overlay showing the 16 swatches in a 4×4 grid with name + hex.
-- Drawn on top of everything; main.lua toggles it with F1.
function M.draw_debug()
    local viewport = require("src.viewport")
    local W, H = viewport.CANVAS_W, viewport.CANVAS_H

    love.graphics.setColor(M.void[1], M.void[2], M.void[3], 0.96)
    love.graphics.rectangle("fill", 0, 0, W, H)

    love.graphics.setColor(M.paper)
    love.graphics.print("PALETTE — 16 colors  (F1 to toggle)", 16, 12)

    love.graphics.setColor(M.bone)
    love.graphics.print("base for every procgen tile, sprite, effect & UI element", 16, 28)

    local cols, rows = 4, 4
    local cell_w, cell_h = 150, 110
    local swatch_h = 70
    local gap = 10
    local grid_w = cols * cell_w + (cols - 1) * gap
    local grid_h = rows * cell_h + (rows - 1) * gap
    local x0 = math.floor((W - grid_w) / 2)
    local y0 = math.floor((H - grid_h) / 2) + 12

    for i, sw in ipairs(M.SWATCHES) do
        local name, color, hex = sw[1], sw[2], sw[3]
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local x = x0 + col * (cell_w + gap)
        local y = y0 + row * (cell_h + gap)

        love.graphics.setColor(color)
        love.graphics.rectangle("fill", x, y, cell_w, swatch_h)

        love.graphics.setColor(M.paper[1], M.paper[2], M.paper[3], 0.35)
        love.graphics.rectangle("line", x, y, cell_w, swatch_h)

        love.graphics.setColor(M.paper)
        love.graphics.print(name, x + 4, y + swatch_h + 4)

        love.graphics.setColor(M.bone)
        love.graphics.print(hex, x + 4, y + swatch_h + 20)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

return M
