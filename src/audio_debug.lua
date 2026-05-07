-- Audio debug overlay (F4). Five buttons, one per waveform. Clicking a
-- button bakes (lazy, once) the waveform shaped by the default ADSR and
-- plays it. Lets us validate the synth pipeline before any real SFX exist.
--
-- Lives outside src/gen/ on purpose: gen/ is for pure generators, this is
-- a control panel that uses them.

local waveform = require("src.gen.waveform")
local envelope = require("src.gen.envelope")
local palette  = require("src.palette")

local M = {}

local FREQ = 440
local DUR  = 0.5
local ADSR = { attack = 0.01, decay = 0.1, sustain = 0.7, release = 0.2 }
local NOISE_SEED = 9999

local sources = {}
local buttons = {}
local loaded  = false

local function build()
    for _, kind in ipairs(waveform.KINDS) do
        local samples
        if kind == "noise" then
            samples = waveform.noise(FREQ, DUR, waveform.SAMPLE_RATE, NOISE_SEED)
        else
            samples = waveform[kind](FREQ, DUR, waveform.SAMPLE_RATE)
        end
        envelope.adsr(samples, waveform.SAMPLE_RATE,
            ADSR.attack, ADSR.decay, ADSR.sustain, ADSR.release)
        sources[kind] = waveform.to_source(samples, waveform.SAMPLE_RATE)
    end

    local W       = love.graphics.getWidth()
    local btn_w   = 130
    local btn_h   = 90
    local gap     = 14
    local count   = #waveform.KINDS
    local total_w = count * btn_w + (count - 1) * gap
    local x0      = math.floor((W - total_w) / 2)
    local y0      = 260
    for i, kind in ipairs(waveform.KINDS) do
        buttons[i] = {
            kind = kind,
            x = x0 + (i - 1) * (btn_w + gap),
            y = y0,
            w = btn_w,
            h = btn_h,
        }
    end
    loaded = true
end

local function ensure_loaded()
    if not loaded then build() end
end

local function play(kind)
    local s = sources[kind]
    if s then
        s:stop()
        s:play()
    end
end

local function point_in(b, x, y)
    return x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h
end

function M.draw()
    ensure_loaded()
    local W, H = love.graphics.getWidth(), love.graphics.getHeight()
    local font = love.graphics.getFont()

    love.graphics.setColor(palette.void[1], palette.void[2], palette.void[3], 0.96)
    love.graphics.rectangle("fill", 0, 0, W, H)

    love.graphics.setColor(palette.paper)
    love.graphics.print("AUDIO WAVEFORMS — (F4 to toggle)", 16, 12)

    love.graphics.setColor(palette.bone)
    love.graphics.print(
        ("click a button to play %.2fs @ %dHz with default ADSR"):format(DUR, FREQ),
        16, 28)
    love.graphics.print(
        ("attack=%.2fs  decay=%.2fs  sustain=%.2f  release=%.2fs")
            :format(ADSR.attack, ADSR.decay, ADSR.sustain, ADSR.release),
        16, 44)

    local mx, my = love.mouse.getPosition()
    for _, b in ipairs(buttons) do
        local hovered = point_in(b, mx, my)
        love.graphics.setColor(hovered and palette.stone or palette.stone_dark)
        love.graphics.rectangle("fill", b.x, b.y, b.w, b.h)
        love.graphics.setColor(hovered and palette.bone or palette.stone_light)
        love.graphics.rectangle("line", b.x, b.y, b.w, b.h)

        love.graphics.setColor(palette.paper)
        local label    = b.kind
        local scale    = 2
        local label_w  = font:getWidth(label) * scale
        local label_h  = font:getHeight() * scale
        love.graphics.print(label,
            b.x + math.floor((b.w - label_w) / 2),
            b.y + math.floor((b.h - label_h) / 2),
            0, scale, scale)
    end

    love.graphics.setColor(palette.bone)
    love.graphics.print(
        "pipeline: waveform.<kind>() → envelope.adsr() → waveform.to_source() → :play()",
        16, H - 28)
    love.graphics.setColor(1, 1, 1, 1)
end

-- Returns true if the click was consumed by the debug panel.
function M.mousepressed(x, y, button)
    if button ~= 1 then return true end
    ensure_loaded()
    for _, b in ipairs(buttons) do
        if point_in(b, x, y) then
            play(b.kind)
            return true
        end
    end
    return true
end

return M
