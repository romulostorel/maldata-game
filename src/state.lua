-- Game state: phase machine (build -> invasion -> result -> build), the
-- current dungeon, placed monsters, the active monster selection, the
-- live hero (during invasion), and the run RNG used for procgen of
-- entity stats. Pure logic; no LÖVE calls.

local dungeon = require("src.dungeon")
local monster = require("src.monster")
local hero    = require("src.hero")
local ai      = require("src.ai")
local rand    = require("src.rand")

local M = {}

M.PHASE_BUILD    = "build"
M.PHASE_INVASION = "invasion"
M.PHASE_RESULT   = "result"
M.MAX_MONSTERS   = 3

M.OUTCOME_TREASURE_STOLEN = "treasure_stolen"
-- Stage 7 will add OUTCOME_HERO_DEAD.

local PHASE_ORDER = {
    M.PHASE_BUILD,
    M.PHASE_INVASION,
    M.PHASE_RESULT,
}

function M.new(seed)
    return {
        seed = seed,
        rng = rand.new(seed),
        dungeon = dungeon.generate(seed),
        phase = M.PHASE_BUILD,
        monsters = {},
        selected_monster_type = monster.GOBLIN,
        hero = nil,
        outcome = nil,
    }
end

local function index_of(phase)
    for i, p in ipairs(PHASE_ORDER) do
        if p == phase then return i end
    end
end

function M.advance(state)
    local i = index_of(state.phase)
    local next_phase = PHASE_ORDER[(i % #PHASE_ORDER) + 1]

    if next_phase == M.PHASE_INVASION then
        state.hero = hero.new(state.rng,
            state.dungeon.entrance.x, state.dungeon.entrance.y)
        state.outcome = nil
    elseif next_phase == M.PHASE_BUILD then
        -- Hero only exists during invasion + the result it produced;
        -- a fresh build starts clean.
        state.hero = nil
        state.outcome = nil
    end

    state.phase = next_phase
end

function M.reset(state, seed)
    state.seed = seed
    state.rng = rand.new(seed)
    state.dungeon = dungeon.generate(seed)
    state.phase = M.PHASE_BUILD
    state.monsters = {}
    state.selected_monster_type = monster.GOBLIN
    state.hero = nil
    state.outcome = nil
end

local function tile_is_free(state, x, y)
    if state.dungeon.grid[y][x] ~= dungeon.FLOOR then return false end
    if x == state.dungeon.entrance.x and y == state.dungeon.entrance.y then return false end
    if x == state.dungeon.treasure.x and y == state.dungeon.treasure.y then return false end
    for _, m in ipairs(state.monsters) do
        if m.x == x and m.y == y then return false end
    end
    return true
end

function M.can_place_monster(state, x, y)
    return state.phase == M.PHASE_BUILD
        and #state.monsters < M.MAX_MONSTERS
        and tile_is_free(state, x, y)
end

function M.try_place_monster(state, x, y)
    if not M.can_place_monster(state, x, y) then return false end
    table.insert(state.monsters, monster.new(state.selected_monster_type, x, y))
    return true
end

function M.select_monster_type(state, type_key)
    if not monster.TYPES[type_key] then return false end
    state.selected_monster_type = type_key
    return true
end

local function monster_blocker(state)
    return function(x, y)
        for _, m in ipairs(state.monsters) do
            if m.alive and m.x == x and m.y == y then return true end
        end
        return false
    end
end

-- Recompute the path each call so monster movement and combat (Stage 7)
-- are reflected. Returns nil when the hero is gone or the goal is
-- unreachable.
function M.hero_path(state)
    if not state.hero or not state.hero.alive then return nil end
    local goal = state.dungeon.treasure
    return ai.find_path(state.dungeon,
        state.hero.x, state.hero.y, goal.x, goal.y,
        monster_blocker(state))
end

function M.step_invasion(state)
    if state.phase ~= M.PHASE_INVASION then return end
    if not state.hero or not state.hero.alive then return end

    local path = M.hero_path(state)
    if not path or #path == 0 then return end -- already on goal or unreachable

    local next_tile = path[1]
    state.hero.x = next_tile.x
    state.hero.y = next_tile.y

    local goal = state.dungeon.treasure
    if state.hero.x == goal.x and state.hero.y == goal.y then
        state.phase = M.PHASE_RESULT
        state.outcome = M.OUTCOME_TREASURE_STOLEN
    end
end

return M
