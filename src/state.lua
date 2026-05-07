-- Game state: phase machine (build -> invasion -> result -> build) plus
-- the current dungeon and seed. Pure logic; no LÖVE calls.

local dungeon = require("src.dungeon")

local M = {}

M.PHASE_BUILD    = "build"
M.PHASE_INVASION = "invasion"
M.PHASE_RESULT   = "result"

local PHASE_ORDER = {
    M.PHASE_BUILD,
    M.PHASE_INVASION,
    M.PHASE_RESULT,
}

function M.new(seed)
    return {
        seed = seed,
        dungeon = dungeon.generate(seed),
        phase = M.PHASE_BUILD,
    }
end

local function index_of(phase)
    for i, p in ipairs(PHASE_ORDER) do
        if p == phase then return i end
    end
end

function M.advance(state)
    local i = index_of(state.phase)
    state.phase = PHASE_ORDER[(i % #PHASE_ORDER) + 1]
end

function M.reset(state, seed)
    state.seed = seed
    state.dungeon = dungeon.generate(seed)
    state.phase = M.PHASE_BUILD
end

return M
