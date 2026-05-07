-- Deterministic PRNG (Park-Miller MINSTD).
-- Stable across Lua versions, no bitops needed. Largest intermediate is
-- state * 16807 < 2^45, exact in float64.
-- Each call to rand.new(seed) produces an independent stream.

local M = {}

function M.new(seed)
    local state = seed % 2147483647
    if state <= 0 then state = state + 2147483646 end
    return function(n)
        state = (state * 16807) % 2147483647
        return (state % n) + 1 -- inclusive 1..n
    end
end

return M
