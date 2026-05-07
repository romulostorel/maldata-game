-- Game state: phase machine (build -> invasion -> result -> build), the
-- current dungeon, placed monsters, the active monster selection, the
-- live hero (during invasion), and the run RNG used for procgen of
-- entity stats. Pure logic; no LÖVE calls.

local dungeon = require("src.dungeon")
local monster = require("src.monster")
local hero    = require("src.hero")
local ai      = require("src.ai")
local rand    = require("src.rand")
local combat  = require("src.combat")

local M = {}

M.PHASE_BUILD    = "build"
M.PHASE_INVASION = "invasion"
M.PHASE_RESULT   = "result"
M.MAX_MONSTERS   = 3

M.OUTCOME_TREASURE_STOLEN = "treasure_stolen"
M.OUTCOME_HERO_DEAD       = "hero_dead"

-- Auto-step cadence during invasion. Tweak here to change the default
-- watch-the-run pacing.
M.STEP_INTERVAL = 0.25

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
        auto_step = true,
        step_timer = 0,
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
        state.auto_step = true
        state.step_timer = 0
    elseif next_phase == M.PHASE_BUILD then
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
    state.auto_step = true
    state.step_timer = 0
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

function M.hero_path(state)
    if not state.hero or not state.hero.alive then return nil end
    local goal = state.dungeon.treasure
    return ai.find_path(state.dungeon,
        state.hero.x, state.hero.y, goal.x, goal.y,
        monster_blocker(state))
end

local function find_target_for_hero(state)
    for _, m in ipairs(state.monsters) do
        if m.alive and combat.in_range(state.hero, m) then
            return m
        end
    end
    return nil
end

function M.step_invasion(state)
    if state.phase ~= M.PHASE_INVASION then return end
    if not state.hero or not state.hero.alive then return end

    -- Hero turn: attack a monster in range, otherwise step along the path.
    local target = find_target_for_hero(state)
    if target then
        combat.attack(state.hero, target)
    else
        local path = M.hero_path(state)
        if path and #path > 0 then
            state.hero.x = path[1].x
            state.hero.y = path[1].y
        end
        local goal = state.dungeon.treasure
        if state.hero.x == goal.x and state.hero.y == goal.y then
            state.phase = M.PHASE_RESULT
            state.outcome = M.OUTCOME_TREASURE_STOLEN
            return
        end
    end

    -- Monster turn: every alive monster in range of the hero attacks back.
    for _, m in ipairs(state.monsters) do
        if m.alive and state.hero.alive and combat.in_range(m, state.hero) then
            combat.attack(m, state.hero)
        end
    end

    if not state.hero.alive then
        state.phase = M.PHASE_RESULT
        state.outcome = M.OUTCOME_HERO_DEAD
    end
end

function M.toggle_auto_step(state)
    state.auto_step = not state.auto_step
    -- Reset accumulator so the next resume waits a fresh interval, not
    -- whatever sliver of dt was leftover when we paused.
    state.step_timer = 0
end

-- Drives auto-stepping during invasion. Accumulates dt; once it crosses
-- STEP_INTERVAL, runs step_invasion (possibly multiple times if dt is
-- huge — frame hitch fast-forward). No-op outside invasion or while
-- paused; bails out of the inner loop the instant phase leaves invasion
-- so a kill/treasure transition can't be over-stepped.
function M.update(state, dt)
    if state.phase ~= M.PHASE_INVASION then return end
    if not state.auto_step then return end
    if not state.hero or not state.hero.alive then return end

    state.step_timer = state.step_timer + dt
    while state.step_timer >= M.STEP_INTERVAL do
        state.step_timer = state.step_timer - M.STEP_INTERVAL
        M.step_invasion(state)
        if state.phase ~= M.PHASE_INVASION
           or not state.hero or not state.hero.alive then
            state.step_timer = 0
            break
        end
    end
end

return M
