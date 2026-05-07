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

-- Mix b into a at the start, scaled. a[i] = a[i] * a_scale + b[i] * b_scale
-- for i in [1, #b]. Anything past #b in `a` keeps its original value, so
-- `b` works as a transient stamped on top of a longer body.
local function layer_head(a, a_scale, b, b_scale)
    for i = 1, #b do
        a[i] = a[i] * a_scale + b[i] * b_scale
    end
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

-- 200ms placement thunk. Low triangle body provides weight; a 12ms noise
-- tick at the head reads as the moment of contact. Mix scales chosen so
-- the peak (body 0.65 + tick 0.35 = 1.0) doesn't clip when baked.
function M.monster_place()
    local body = waveform.triangle(110, 0.20, SR)
    envelope.adsr(body, SR, 0.005, 0.05, 0.55, 0.145)

    local tick = waveform.noise(0, 0.012, SR, 7777)
    envelope.adsr(tick, SR, 0.001, 0.004, 0.0, 0.007)

    return layer_head(body, 0.65, tick, 0.35)
end

-- 70ms footstep tap. Quiet by design — fires on every hero step. A short
-- noise burst (the contact) layered on a low triangle (the foot weight).
function M.hero_footstep()
    local body = waveform.triangle(180, 0.07, SR)
    envelope.adsr(body, SR, 0.005, 0.020, 0.30, 0.045)

    local tap = waveform.noise(0, 0.040, SR, 4242)
    envelope.adsr(tap, SR, 0.002, 0.010, 0.0, 0.028)

    return layer_head(body, 0.5, tap, 0.5)
end

-- 200ms swoosh-style hero attack. Shaped noise reads as the swing arc;
-- a brief mid triangle accent gives it tonal presence so it doesn't
-- disappear into ambient noise once that exists.
function M.hero_attack()
    local swoosh = waveform.noise(0, 0.20, SR, 1357)
    envelope.adsr(swoosh, SR, 0.008, 0.040, 0.30, 0.152)

    local accent = waveform.triangle(440, 0.08, SR)
    envelope.adsr(accent, SR, 0.002, 0.020, 0.50, 0.058)

    return layer_head(swoosh, 0.55, accent, 0.45)
end

-- 150ms impact punch. Same transient+body recipe as monster_place but
-- tighter and pitched a bit higher — reads as "ow" rather than "thud".
function M.hit_impact()
    local body = waveform.triangle(220, 0.15, SR)
    envelope.adsr(body, SR, 0.001, 0.030, 0.50, 0.119)

    local crack = waveform.noise(0, 0.020, SR, 9090)
    envelope.adsr(crack, SR, 0.001, 0.005, 0.0, 0.014)

    return layer_head(body, 0.55, crack, 0.45)
end

return M
