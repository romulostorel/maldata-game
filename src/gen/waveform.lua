-- Pure waveform sample generators. Each function returns a 1-indexed table of
-- floats in [-1, 1] for `dur` seconds at `sample_rate` Hz. No LÖVE dependency
-- in the generators themselves; only `to_source` touches love.sound/love.audio.
--
-- Convention: every generator takes (freq, dur, sample_rate). `noise` ignores
-- freq (white noise has no fundamental) but keeps the signature for symmetry,
-- plus an extra `seed` so different instances of the same noise SFX can vary.

local M = {}

local TWO_PI = 2 * math.pi

local function num_samples(dur, sample_rate)
    return math.floor(dur * sample_rate + 0.5)
end

function M.sine(freq, dur, sample_rate)
    local n = num_samples(dur, sample_rate)
    local samples = {}
    local k = TWO_PI * freq / sample_rate
    for i = 1, n do
        samples[i] = math.sin((i - 1) * k)
    end
    return samples
end

function M.square(freq, dur, sample_rate)
    local n = num_samples(dur, sample_rate)
    local samples = {}
    local period = sample_rate / freq
    local half   = period * 0.5
    for i = 1, n do
        samples[i] = (((i - 1) % period) < half) and 1 or -1
    end
    return samples
end

function M.sawtooth(freq, dur, sample_rate)
    local n = num_samples(dur, sample_rate)
    local samples = {}
    local period = sample_rate / freq
    for i = 1, n do
        local p = ((i - 1) % period) / period
        samples[i] = p * 2 - 1
    end
    return samples
end

-- /\ shape. First half ramps -1 → 1, second half ramps 1 → -1.
function M.triangle(freq, dur, sample_rate)
    local n = num_samples(dur, sample_rate)
    local samples = {}
    local period = sample_rate / freq
    for i = 1, n do
        local p = ((i - 1) % period) / period
        samples[i] = (p < 0.5) and (p * 4 - 1) or (3 - p * 4)
    end
    return samples
end

-- Triangle wave with linear frequency sweep f0 → f1 over the buffer.
-- Phase accumulates sample-by-sample so the slide stays continuous (no
-- audible discontinuity even with steep sweeps). Used for tonal descent
-- in death SFX and any future "drop" cue.
function M.triangle_sweep(f0, f1, dur, sample_rate)
    local n = num_samples(dur, sample_rate)
    local samples = {}
    local phase = 0
    local denom = math.max(1, n - 1)
    for i = 1, n do
        local t = (i - 1) / denom
        local f = f0 + (f1 - f0) * t
        phase = phase + f / sample_rate
        local p = phase - math.floor(phase)
        samples[i] = (p < 0.5) and (p * 4 - 1) or (3 - p * 4)
    end
    return samples
end

-- White noise via Park-Miller MINSTD (same family as src/rand.lua, kept inline
-- so this file stays a self-contained sample-generation module).
function M.noise(_freq, dur, sample_rate, seed)
    local n = num_samples(dur, sample_rate)
    local samples = {}
    local state = (seed or 1) % 2147483647
    if state <= 0 then state = state + 2147483646 end
    for i = 1, n do
        state = (state * 16807) % 2147483647
        samples[i] = (state / 2147483647) * 2 - 1
    end
    return samples
end

-- Bake a sample table into a static love.audio.Source (mono, 16-bit).
-- Clamps to [-1, 1] so an over-sum in later stages can't wrap.
function M.to_source(samples, sample_rate)
    local n = #samples
    local data = love.sound.newSoundData(n, sample_rate, 16, 1)
    for i = 1, n do
        local v = samples[i]
        if v > 1 then v = 1 elseif v < -1 then v = -1 end
        data:setSample(i - 1, v)
    end
    return love.audio.newSource(data, "static")
end

M.SAMPLE_RATE = 44100
M.KINDS = { "sine", "square", "sawtooth", "triangle", "noise" }

return M
