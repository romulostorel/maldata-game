-- Game state: phase machine (build -> invasion -> result -> build), the
-- current dungeon and seed, placed monsters, and the active monster
-- selection used for placement. Pure logic; no LÖVE calls.

local dungeon = require("src.dungeon")
local monster = require("src.monster")

local M = {}

M.PHASE_BUILD    = "build"
M.PHASE_INVASION = "invasion"
M.PHASE_RESULT   = "result"
M.MAX_MONSTERS   = 3

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
        monsters = {},
        selected_monster_type = monster.GOBLIN,
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
    state.monsters = {}
    state.selected_monster_type = monster.GOBLIN
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

return M
