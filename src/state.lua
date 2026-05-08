-- Game state: phase machine (build -> invasion -> result -> build), the
-- current dungeon, placed monsters, the active monster selection, the
-- live hero (during invasion), and the run RNG used for procgen of
-- entity stats. Logic-only — combat visuals are routed through an
-- on_event callback so this module stays free of love.graphics. The
-- single audio dependency is the phase_transition cue, fired directly
-- whenever state.phase changes via set_phase().

local dungeon = require("src.dungeon")
local monster = require("src.monster")
local hero    = require("src.hero")
local ai      = require("src.ai")
local rand    = require("src.rand")
local combat  = require("src.combat")
local audio   = require("src.audio")

local M = {}

M.PHASE_BUILD    = "build"
M.PHASE_INVASION = "invasion"
M.PHASE_RESULT   = "result"

-- Build-phase economy. Each monster type has a cost in monster.TYPES; the
-- player can spend up to BUDGET total. Picked from playtest sims at
-- ~40% defender win rate against a 3-hero wave — high enough that
-- placement matters, low enough that the player has real agency.
M.BUDGET = 14

-- Walls also draw from the budget: cheap (1) so a maze is still affordable,
-- but every carved tile is one fewer goblin. Without a cost the wall tool
-- dominates: free walls can fully serpentine the path without any tradeoff.
M.WALL_COST = 1

-- One invasion = a wave of N heroes. The first marches in immediately;
-- the rest queue up and step onto the entrance one per tick once it's
-- clear, so the wave staggers naturally without needing tile stacking.
-- Tests can override per-state via `state.num_heroes = 1`.
M.DEFAULT_NUM_HEROES = 3

M.TOOL_MONSTER = "monster"
M.TOOL_WALL    = "wall"

M.OUTCOME_TREASURE_STOLEN = "treasure_stolen"
M.OUTCOME_HERO_DEAD       = "hero_dead"

-- Orc passive: a slain orc leaves a corpse that blocks its tile for this
-- many invasion ticks. Decremented at the END of each tick, so a corpse
-- born in tick N blocks tick N+1 and N+2, then is cleared at the end of
-- N+2 (tile free again from tick N+3 onward).
M.ORC_CORPSE_TURNS = 2

-- Slime passive: number of mini-slimes spawned on death. Cardinal-adjacent
-- free tiles only; if fewer than this are free, only that many spawn.
M.SLIME_SPLIT_COUNT = 2

-- Player-placed walls live in a set keyed by wall_key(x, y); the dungeon
-- grid is updated in lockstep so A* sees them as impassable. Tracking which
-- walls are player-placed (vs. the original perimeter) lets right-click
-- only remove what the player actually built.
local function wall_key(x, y)
    return y * 100 + x
end

-- Auto-step cadence during invasion. Tweak here to change the default
-- watch-the-run pacing.
M.STEP_INTERVAL = 0.25

local PHASE_ORDER = {
    M.PHASE_BUILD,
    M.PHASE_INVASION,
    M.PHASE_RESULT,
}

-- Pre-roll the next wave so the player sees the heroes they'll face during
-- BUILD. The same hero objects are promoted to heroes/queue at invasion
-- start (no re-roll), so what you see is exactly what shows up.
local function roll_wave(state)
    state.wave_preview = {}
    local entrance = state.dungeon.entrance
    for _ = 1, state.num_heroes do
        table.insert(state.wave_preview,
            hero.new(state.rng, entrance.x, entrance.y))
    end
end

function M.new(seed)
    local s = {
        seed = seed,
        rng = rand.new(seed),
        dungeon = dungeon.generate(seed),
        phase = M.PHASE_BUILD,
        monsters = {},
        placed_walls = {},
        selected_monster_type = monster.GOBLIN,
        selected_tool = M.TOOL_MONSTER,
        num_heroes = M.DEFAULT_NUM_HEROES,
        heroes = {},      -- alive (and recently dead) heroes inside the dungeon
        hero_queue = {},  -- pre-rolled heroes still waiting to enter
        wave_preview = {}, -- next wave's heroes, shown during BUILD
        -- Orc-death corpses: { x, y, ttl } entries that block pathing for
        -- ORC_CORPSE_TURNS ticks. Lives only during INVASION; cleared on
        -- advance back to BUILD and on reset.
        corpses = {},
        outcome = nil,
        auto_step = true,
        step_timer = 0,
        -- Session counters span the program run, NOT a single dungeon.
        -- state.reset preserves them so "new dungeon" still tallies.
        session = { wins = 0, losses = 0 },
    }
    roll_wave(s)
    return s
end

local function index_of(phase)
    for i, p in ipairs(PHASE_ORDER) do
        if p == phase then return i end
    end
end

local PHASE_AMBIENT = {
    [M.PHASE_BUILD]    = "ambient_build",
    [M.PHASE_INVASION] = "ambient_invasion",
    -- result: nil → drone silenced so the sting plays uncluttered
}

-- Single chokepoint for phase changes. Plays the generic phase_transition
-- stinger on every real change, except when entering RESULT — there the
-- outcome-specific sting (victory if the hero died, defeat if the treasure
-- was stolen) replaces it. state.outcome must already be set before
-- transitioning to RESULT for the right sting to fire. Also swaps the
-- looping ambient drone to match the destination phase.
local function set_phase(state, new_phase)
    if state.phase == new_phase then return end
    if new_phase == M.PHASE_RESULT and state.outcome == M.OUTCOME_HERO_DEAD then
        audio.play("victory_sting")
        state.session.wins = state.session.wins + 1
    elseif new_phase == M.PHASE_RESULT and state.outcome == M.OUTCOME_TREASURE_STOLEN then
        audio.play("defeat_sting")
        state.session.losses = state.session.losses + 1
    else
        audio.play("phase_transition")
    end
    audio.set_ambient(PHASE_AMBIENT[new_phase])
    state.phase = new_phase
end

function M.advance(state)
    local i = index_of(state.phase)
    local next_phase = PHASE_ORDER[(i % #PHASE_ORDER) + 1]

    if next_phase == M.PHASE_INVASION then
        state.heroes = {}
        state.hero_queue = {}
        state.corpses = {}
        -- Promote the pre-rolled wave: first hero takes the entrance, the
        -- rest sit in the queue and step in one per tick. Same identities
        -- the player saw during BUILD — no re-roll here.
        for n, h in ipairs(state.wave_preview) do
            if n == 1 then
                table.insert(state.heroes, h)
            else
                table.insert(state.hero_queue, h)
            end
        end
        state.wave_preview = {}
        state.outcome = nil
        state.auto_step = true
        state.step_timer = 0
    elseif next_phase == M.PHASE_BUILD then
        state.heroes = {}
        state.hero_queue = {}
        state.corpses = {}
        state.outcome = nil
        -- Retry semantics: dungeon stays the same, but the build is wiped
        -- so the player gets a full budget back to react to the lesson.
        -- The rng keeps moving (no reset) so each retry rolls a new wave.
        state.monsters = {}
        for k in pairs(state.placed_walls) do
            local y = math.floor(k / 100)
            local x = k - y * 100
            state.dungeon.grid[y][x] = dungeon.FLOOR
        end
        state.placed_walls = {}
        roll_wave(state)
    end

    set_phase(state, next_phase)
end

function M.reset(state, seed)
    state.seed = seed
    state.rng = rand.new(seed)
    state.dungeon = dungeon.generate(seed)
    state.monsters = {}
    state.placed_walls = {}
    state.selected_monster_type = monster.GOBLIN
    state.selected_tool = M.TOOL_MONSTER
    state.num_heroes = M.DEFAULT_NUM_HEROES
    state.heroes = {}
    state.hero_queue = {}
    state.corpses = {}
    state.outcome = nil
    state.auto_step = true
    state.step_timer = 0
    roll_wave(state)
    set_phase(state, M.PHASE_BUILD)
end

local function tile_is_free(state, x, y)
    if not state.dungeon.grid[y] then return false end
    if state.dungeon.grid[y][x] ~= dungeon.FLOOR then return false end
    if x == state.dungeon.entrance.x and y == state.dungeon.entrance.y then return false end
    if x == state.dungeon.treasure.x and y == state.dungeon.treasure.y then return false end
    for _, m in ipairs(state.monsters) do
        if m.x == x and m.y == y then return false end
    end
    return true
end

function M.spent_budget(state)
    local sum = 0
    for _, m in ipairs(state.monsters) do
        sum = sum + m.cost
    end
    for _ in pairs(state.placed_walls) do
        sum = sum + M.WALL_COST
    end
    return sum
end

function M.remaining_budget(state)
    return M.BUDGET - M.spent_budget(state)
end

function M.can_place_monster(state, x, y)
    if state.phase ~= M.PHASE_BUILD then return false end
    if not tile_is_free(state, x, y) then return false end
    local cost = monster.TYPES[state.selected_monster_type].cost
    return cost <= M.remaining_budget(state)
end

function M.try_place_monster(state, x, y)
    if not M.can_place_monster(state, x, y) then return false end
    table.insert(state.monsters, monster.new(state.selected_monster_type, x, y))
    audio.play("monster_place")
    return true
end

-- Right-click undo. Build phase only — pulling a monster mid-invasion
-- would let the player rewrite the fight reactively, breaking the v1
-- design where placement is committed once invasion starts.
function M.try_remove_monster(state, x, y)
    if state.phase ~= M.PHASE_BUILD then return false end
    for i, m in ipairs(state.monsters) do
        if m.x == x and m.y == y then
            table.remove(state.monsters, i)
            audio.play("monster_remove")
            return true
        end
    end
    return false
end

function M.select_monster_type(state, type_key)
    if not monster.TYPES[type_key] then return false end
    state.selected_monster_type = type_key
    return true
end

function M.select_tool(state, tool)
    if tool ~= M.TOOL_MONSTER and tool ~= M.TOOL_WALL then return false end
    state.selected_tool = tool
    return true
end

-- Connectivity guard: simulating the wall as an extra A* blocker (instead of
-- mutating the grid) keeps this pure. Monsters are *not* counted as blockers
-- here — heroes can kill them, so a wall layout that funnels through a
-- monster is still legal.
local function path_survives_wall(state, x, y)
    local function blocker(bx, by)
        return bx == x and by == y
    end
    return ai.find_path(state.dungeon,
        state.dungeon.entrance.x, state.dungeon.entrance.y,
        state.dungeon.treasure.x, state.dungeon.treasure.y,
        blocker) ~= nil
end

function M.can_place_wall(state, x, y)
    if state.phase ~= M.PHASE_BUILD then return false end
    if not tile_is_free(state, x, y) then return false end
    if M.WALL_COST > M.remaining_budget(state) then return false end
    return path_survives_wall(state, x, y)
end

function M.try_place_wall(state, x, y)
    if not M.can_place_wall(state, x, y) then return false end
    state.dungeon.grid[y][x] = dungeon.WALL
    state.placed_walls[wall_key(x, y)] = true
    audio.play("monster_place")
    return true
end

-- Right-click on a placed wall reverts it. Only player-placed walls are
-- removable; the perimeter stays.
function M.can_remove_wall(state, x, y)
    if state.phase ~= M.PHASE_BUILD then return false end
    return state.placed_walls[wall_key(x, y)] == true
end

function M.try_remove_wall(state, x, y)
    if not M.can_remove_wall(state, x, y) then return false end
    state.dungeon.grid[y][x] = dungeon.FLOOR
    state.placed_walls[wall_key(x, y)] = nil
    audio.play("monster_remove")
    return true
end

-- Combined blocker for hero pathfinding: alive monsters AND alive peer
-- heroes (excluding `self`) block movement. Orc corpses are also blockers
-- — that is the orc's whole death-passive payoff. Without the peer block,
-- heroes would happily step onto each other's tiles; the queue/spawn logic
-- assumes the entrance can hold at most one hero at a time.
local function path_blocker(state, self_hero)
    return function(x, y)
        for _, m in ipairs(state.monsters) do
            if m.alive and m.x == x and m.y == y then return true end
        end
        for _, h in ipairs(state.heroes) do
            if h ~= self_hero and h.alive and h.x == x and h.y == y then
                return true
            end
        end
        for _, c in ipairs(state.corpses) do
            if c.x == x and c.y == y then return true end
        end
        return false
    end
end

-- Spawn-tile predicate for slime split: a tile is eligible if it is FLOOR,
-- not entrance/treasure, not occupied by a live monster or hero, and not
-- held by an orc corpse. Stricter than tile_is_free (which is build-phase)
-- because heroes and corpses only exist mid-invasion.
local function is_spawn_tile(state, x, y)
    if not state.dungeon.grid[y] then return false end
    if state.dungeon.grid[y][x] ~= dungeon.FLOOR then return false end
    if x == state.dungeon.entrance.x and y == state.dungeon.entrance.y then return false end
    if x == state.dungeon.treasure.x and y == state.dungeon.treasure.y then return false end
    for _, m in ipairs(state.monsters) do
        if m.alive and m.x == x and m.y == y then return false end
    end
    for _, h in ipairs(state.heroes) do
        if h.alive and h.x == x and h.y == y then return false end
    end
    for _, c in ipairs(state.corpses) do
        if c.x == x and c.y == y then return false end
    end
    return true
end

-- Slime split: spawn up to SLIME_SPLIT_COUNT mini-slimes on cardinal-adjacent
-- free tiles. Direction order is fixed (up/right/down/left) so the spawn
-- pattern is deterministic per seed even though no rng is consumed.
local SPLIT_DIRS = { { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } }
local function spawn_split_slimes(state, parent)
    local spawned = 0
    for _, d in ipairs(SPLIT_DIRS) do
        if spawned >= M.SLIME_SPLIT_COUNT then break end
        local nx, ny = parent.x + d[1], parent.y + d[2]
        if is_spawn_tile(state, nx, ny) then
            table.insert(state.monsters, monster.new_mini_slime(nx, ny))
            spawned = spawned + 1
        end
    end
end

-- Per-type death payoff. Orc → corpse on its tile; slime (non-mini) →
-- splits into mini-slimes. Mini-slimes and goblins have no death effect.
-- Called immediately after a hero kills the monster, so subsequent path
-- queries this tick already see the new blockers/spawns.
local function on_monster_death(state, m)
    if m.type == monster.ORC then
        table.insert(state.corpses,
            { x = m.x, y = m.y, ttl = M.ORC_CORPSE_TURNS })
    elseif m.type == monster.SLIME and not m.is_mini then
        spawn_split_slimes(state, m)
    end
end

-- Returns the path the given hero would take this tick. With no `h`,
-- defaults to the lead hero (preserves backward compat for callers that
-- only know about a single hero).
function M.hero_path(state, h)
    h = h or state.heroes[1]
    if not h or not h.alive then return nil end
    local goal = state.dungeon.treasure
    return ai.find_path(state.dungeon,
        h.x, h.y, goal.x, goal.y,
        path_blocker(state, h))
end

local function find_monster_in_range(state, h)
    for _, m in ipairs(state.monsters) do
        if m.alive and combat.in_range(h, m) then return m end
    end
    return nil
end

local function find_hero_in_range(state, m)
    for _, h in ipairs(state.heroes) do
        if h.alive and combat.in_range(m, h) then return h end
    end
    return nil
end

local function entrance_occupied(state)
    local e = state.dungeon.entrance
    for _, h in ipairs(state.heroes) do
        if h.alive and h.x == e.x and h.y == e.y then return true end
    end
    return false
end

local function any_hero_alive(state)
    for _, h in ipairs(state.heroes) do
        if h.alive then return true end
    end
    return false
end

-- Try to step the next queued hero onto the (clear) entrance tile.
local function spawn_from_queue(state)
    if #state.hero_queue == 0 then return end
    if entrance_occupied(state) then return end
    local h = table.remove(state.hero_queue, 1)
    h.x = state.dungeon.entrance.x
    h.y = state.dungeon.entrance.y
    table.insert(state.heroes, h)
end

-- on_event is an optional callback used by the host (main.lua) to react to
-- combat without coupling state.lua to LÖVE — e.g., kicking off the attack
-- flash and death silhouette anims, and routing footstep/swing/impact SFX.
-- Signatures:
--   on_event("attack", attacker, target)
--   on_event("death",  who)
--   on_event("move",   who)            -- fired after a successful step
function M.step_invasion(state, on_event)
    if state.phase ~= M.PHASE_INVASION then return end

    -- Snapshot monsters BEFORE the hero turn. Mini-slimes pushed during
    -- hero swings (slime split) land in state.monsters but NOT in the
    -- snapshot, so they wait one full tick before acting — same fairness
    -- contract as a queued hero waiting on the entrance for a turn.
    local pre_monsters = {}
    for i, m in ipairs(state.monsters) do pre_monsters[i] = m end

    -- Snapshot corpses so a corpse spawned this tick is not decremented
    -- until next tick; it should block for ORC_CORPSE_TURNS *future* ticks.
    local pre_corpses = {}
    for i, c in ipairs(state.corpses) do pre_corpses[i] = c end

    -- Hero turns: each alive hero attacks the first monster in range, or
    -- steps along its own path. Iterating a snapshot keeps the order
    -- deterministic even if state.heroes is mutated mid-loop.
    local snapshot = {}
    for i, h in ipairs(state.heroes) do snapshot[i] = h end
    for _, h in ipairs(snapshot) do
        if h.alive then
            local target = find_monster_in_range(state, h)
            if target then
                local dmg = combat.attack(h, target)
                if on_event then
                    on_event("attack", h, target, dmg)
                    if not target.alive then on_event("death", target) end
                end
                if not target.alive then on_monster_death(state, target) end
            else
                local path = M.hero_path(state, h)
                if path and #path > 0 then
                    h.x = path[1].x
                    h.y = path[1].y
                    if on_event then on_event("move", h) end
                end
                local goal = state.dungeon.treasure
                if h.x == goal.x and h.y == goal.y then
                    state.outcome = M.OUTCOME_TREASURE_STOLEN
                    set_phase(state, M.PHASE_RESULT)
                    return
                end
            end
        end
    end

    -- Monster turn: each monster swings at the first alive hero in range.
    -- Iterates the pre-hero snapshot so freshly split mini-slimes don't
    -- swing the same tick they spawn. Goblin cluster bonus is computed at
    -- swing time against state.monsters (post-hero), so a goblin loses its
    -- bonus the moment a neighbor falls.
    for _, m in ipairs(pre_monsters) do
        if m.alive then
            local target = find_hero_in_range(state, m)
            if target then
                local dmg = combat.attack(m, target,
                    monster.effective_atk(m, state.monsters))
                if on_event then
                    on_event("attack", m, target, dmg)
                    if not target.alive then on_event("death", target) end
                end
            end
        end
    end

    -- Decrement TTL on corpses that existed at the start of this tick. New
    -- corpses (orc died this tick) keep their fresh TTL until next tick.
    for _, c in ipairs(pre_corpses) do
        c.ttl = c.ttl - 1
    end
    for i = #state.corpses, 1, -1 do
        if state.corpses[i].ttl <= 0 then
            table.remove(state.corpses, i)
        end
    end

    -- New heroes step onto the entrance only AFTER existing entities act,
    -- so a freshly spawned hero spends one tick safely on the threshold
    -- before being targeted or moving. Keeps turn flow predictable for the
    -- player watching the wave roll in.
    spawn_from_queue(state)

    -- End of wave: queue empty AND no living hero left in the dungeon.
    if #state.hero_queue == 0 and not any_hero_alive(state) then
        state.outcome = M.OUTCOME_HERO_DEAD
        set_phase(state, M.PHASE_RESULT)
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
function M.update(state, dt, on_event)
    if state.phase ~= M.PHASE_INVASION then return end
    if not state.auto_step then return end
    -- Idle ticks once the wave is over — wait for the player to advance.
    if #state.hero_queue == 0 and not any_hero_alive(state) then return end

    state.step_timer = state.step_timer + dt
    while state.step_timer >= M.STEP_INTERVAL do
        state.step_timer = state.step_timer - M.STEP_INTERVAL
        M.step_invasion(state, on_event)
        if state.phase ~= M.PHASE_INVASION then
            state.step_timer = 0
            break
        end
    end
end

return M
