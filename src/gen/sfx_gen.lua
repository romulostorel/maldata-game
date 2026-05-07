-- SFX generators. Each function returns a sample table built by composing
-- waveform.lua + envelope.lua — no LÖVE calls. audio.lua bakes the result
-- into a Source on load.
--
-- These are not just "play a wave"; the envelope shape is what gives each
-- cue its character (snappy hover vs. punchy click vs. sustained stinger).

local waveform = require("src.gen.waveform")
local envelope = require("src.gen.envelope")

local SR = waveform.SAMPLE_RATE

local M = {}

-- Append b's samples after a's, in-place. Returns a.
local function concat(a, b)
    local n = #a
    for i = 1, #b do a[n + i] = b[i] end
    return a
end

-- Subtle 30ms triangle blip — high enough to read as "hover", short enough
-- to not feel like a notification.
function M.ui_hover()
    local s = waveform.triangle(1200, 0.030, SR)
    envelope.adsr(s, SR, 0.002, 0.010, 0.0, 0.018)
    return s
end

-- 70ms square click. Square gives a more "tactile / 8-bit button" feel than
-- a sine; quick attack + small sustain + soft release reads as a press.
function M.ui_click()
    local s = waveform.square(660, 0.070, SR)
    envelope.adsr(s, SR, 0.003, 0.020, 0.4, 0.047)
    return s
end

-- 400ms two-note ascending stinger (E4 → B4, perfect 5th). Triangle keeps
-- it warm rather than chiptune-shrill. The two segments are concatenated;
-- n1's release ends well before n2 begins so they don't muddy.
function M.phase_transition()
    local n1 = waveform.triangle(330, 0.18, SR)
    envelope.adsr(n1, SR, 0.005, 0.04, 0.6, 0.135)
    local n2 = waveform.triangle(495, 0.22, SR)
    envelope.adsr(n2, SR, 0.005, 0.05, 0.5, 0.165)
    return concat(n1, n2)
end

return M
