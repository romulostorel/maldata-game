-- ADSR amplitude envelope. Multiplies a sample table in-place by an
-- attack/decay/sustain/release curve. Durations in seconds; sustain is a
-- level in [0, 1] applied to the steady-state region.
--
--   amp
--    1 |    /\
--      |   /  \____________
--    s |  /                \
--      | /                  \
--    0 |/____________________\___
--        A   D     S          R   time
--
-- If A+D+R is longer than the buffer the sustain region collapses to zero
-- length; release still rolls in over the tail of whatever's left.

local M = {}

function M.adsr(samples, sample_rate, attack, decay, sustain, release)
    local n = #samples
    local a = math.floor(attack  * sample_rate + 0.5)
    local d = math.floor(decay   * sample_rate + 0.5)
    local r = math.floor(release * sample_rate + 0.5)
    local sustain_end = math.max(a + d, n - r)

    for i = 1, n do
        local amp
        if i <= a then
            amp = (a > 0) and (i / a) or 1
        elseif i <= a + d then
            local t = (d > 0) and ((i - a) / d) or 1
            amp = 1 + (sustain - 1) * t
        elseif i <= sustain_end then
            amp = sustain
        else
            local t = (r > 0) and ((i - sustain_end) / r) or 1
            amp = sustain * (1 - t)
            if amp < 0 then amp = 0 end
        end
        samples[i] = samples[i] * amp
    end
    return samples
end

return M
