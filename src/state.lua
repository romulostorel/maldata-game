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
local grid    = require("src.grid")

local M = {}

M.PHASE_BUILD    = "build"
M.PHASE_INVASION = "invasion"
M.PHASE_RESULT   = "result"

-- Build-phase economy. Each monster type has a cost in monster.TYPES; the
-- player can spend up to BUDGET (+ wave-survival bonuses) total. Initial
-- value picked from playtest sims at ~40% defender win rate against a
-- 3-hero wave — high enough that placement matters, low enough that the
-- player has real agency.
M.BUDGET = 14

-- Walls also draw from the budget: cheap (1) so a maze is still affordable,
-- but every carved tile is one fewer goblin. Without a cost the wall tool
-- dominates: free walls can fully serpentine the path without any tradeoff.
M.WALL_COST = 1

-- Wave 1 hero count. Each subsequent wave adds 1 more hero up to
-- WAVE_HERO_CAP; once the count caps, surplus waves crank up hero stats
-- via hero_buff_for_wave instead. The cap exists because the entrance
-- queue is single-file: more than ~6 heroes pile up before they finish
-- spawning, and the wave gets crushed by its own latency rather than the
-- defender's design.
M.DEFAULT_NUM_HEROES = 3
M.WAVE_HERO_CAP = 6

-- Refund + reinforcement granted at the end of each cleared wave. Added
-- to the budget pool (state.budget_bonus accumulates across the run) so
-- the player can keep up with escalating waves without having to remove
-- and re-place from scratch every time. Calibrated so a player who
-- survives wave N with most monsters intact has 5-7 extra points to
-- reinforce — enough for an Orc or two Goblins, not a full rebuild.
M.WAVE_BUDGET_BONUS = 5

M.TOOL_MONSTER = "monster"
M.TOOL_WALL    = "wall"

-- Only one outcome ends a multi-wave run: a hero touched the treasure.
-- Heroes-dead is a wave-end signal, handled inline by advance_to_next_wave
-- (it returns to BUILD instead of RESULT).
M.OUTCOME_TREASURE_STOLEN = "treasure_stolen"

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
-- watch-the-run pacing. Slower than a typical turn timer because each
-- tick can fire several events at once (mage AoE damage popups, goblin
-- cluster swings, warrior retaliate, slime split): the player needs to
-- read them all before the next tick lands.
M.STEP_INTERVAL = 0.6

-- Drama-beat slowdowns. After a tick where anything died, the next tick
-- is delayed so the kill has room to land emotionally. After a tick where
-- a hero is within DRAMA_APPROACH_DIST of the treasure, the next tick is
-- delayed for the same reason — the lead-in to the run-ending hit is the
-- most tense moment in the loop. Both add to STEP_INTERVAL (not replace
-- it) and are consumed on the next step. Manual stepping (player presses
-- '.') ignores them — no need to slow down a player-paced read.
M.DRAMA_DEATH_PAUSE    = 0.35
M.DRAMA_APPROACH_PAUSE = 0.30
M.DRAMA_APPROACH_DIST  = 2

-- Hero count for a given wave number, capped so the entrance queue stays
-- spawnable. Wave 1 = DEFAULT_NUM_HEROES; +1 per subsequent wave.
local function hero_count_for_wave(wave)
    return math.min(M.DEFAULT_NUM_HEROES + (wave - 1), M.WAVE_HERO_CAP)
end

-- Stat buff applied uniformly to HP and ATK once the wave count caps.
-- For waves 1..(WAVE_HERO_CAP - DEFAULT_NUM_HEROES + 1) it's 0 — escalation
-- comes from numbers. After that, each extra wave adds +1 to base hp and
-- atk before the per-class variance roll, so the run gets monotonically
-- harder forever (defining the run's natural ceiling).
local function hero_buff_for_wave(wave)
    return math.max(0, wave - (M.WAVE_HERO_CAP - M.DEFAULT_NUM_HEROES + 1))
end

-- Pre-roll the next wave so the player sees the heroes they'll face during
-- BUILD. The same hero objects are promoted to heroes/queue at invasion
-- start (no re-roll), so what you see is exactly what shows up.
--
-- Lead-warrior swap: if any Warrior is rolled, it moves to slot 1 of the
-- preview. Its tank passive (high HP + retaliate) makes it the natural
-- entrance soak; the player sees the new order during BUILD so the preview
-- matches the invasion exactly.
local function roll_wave(state)
    state.wave_preview = {}
    local entrance = state.dungeon.entrance
    local buff = hero_buff_for_wave(state.wave)
    for _ = 1, state.num_heroes do
        table.insert(state.wave_preview,
            hero.new(state.rng, entrance.x, entrance.y, buff))
    end
    if state.wave_preview[1] and state.wave_preview[1].class ~= hero.WARRIOR then
        for i = 2, #state.wave_preview do
            if state.wave_preview[i].class == hero.WARRIOR then
                state.wave_preview[1], state.wave_preview[i] =
                    state.wave_preview[i], state.wave_preview[1]
                break
            end
        end
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
        -- Run progression: wave starts at 1 and increments each time the
        -- player clears a wave (handled inline in step_invasion). num_heroes
        -- + buff are derived from wave so they refresh on every advance.
        wave = 1,
        budget_bonus = 0,
        num_heroes = hero_count_for_wave(1),
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
        -- Carry-over delay applied to the NEXT auto-step interval when a
        -- dramatic event lands (death, hero closing on treasure). Set at
        -- the end of step_invasion, consumed by state.update.
        tension_pause = 0,
        -- Session counters span the program run, NOT a single dungeon.
        -- state.reset preserves them so "new dungeon" still tallies.
        --   best_wave: highest wave the player ever invaded with this run
        --   last_wave: wave reached on the most recent ended run (focal
        --              stat on the result panel)
        --   runs:      total runs ended (i.e., losses, since runs only end
        --              by treasure-stolen)
        session = { best_wave = 0, last_wave = 0, runs = 0 },
    }
    roll_wave(s)
    return s
end

local PHASE_AMBIENT = {
    [M.PHASE_BUILD]    = "ambient_build",
    [M.PHASE_INVASION] = "ambient_invasion",
    -- result: nil → drone silenced so the sting plays uncluttered
}

-- Single chokepoint for phase changes. Plays the generic phase_transition
-- stinger on every real change, except when entering RESULT (treasure
-- stolen) — there the defeat sting replaces it and the run counter ticks.
-- state.outcome must already be set before transitioning to RESULT for
-- the right sting to fire.
local function set_phase(state, new_phase)
    if state.phase == new_phase then return end
    if new_phase == M.PHASE_RESULT and state.outcome == M.OUTCOME_TREASURE_STOLEN then
        audio.play("defeat_sting")
        state.session.runs = state.session.runs + 1
        state.session.last_wave = state.wave
    elseif state.phase == M.PHASE_INVASION and new_phase == M.PHASE_BUILD then
        -- Between-wave: the wave just cleared. Victory cue, then drop
        -- back into the build ambient drone.
        audio.play("victory_sting")
    else
        audio.play("phase_transition")
    end
    audio.set_ambient(PHASE_AMBIENT[new_phase])
    state.phase = new_phase
end

-- Wipe the player's build between runs: dungeon stays the same, but
-- monsters and player-placed walls clear so the next run starts fresh.
local function clear_build(state)
    state.monsters = {}
    for k in pairs(state.placed_walls) do
        local y = math.floor(k / 100)
        local x = k - y * 100
        state.dungeon.grid[y][x] = dungeon.FLOOR
    end
    state.placed_walls = {}
end

-- Reset run-progress state to its wave-1 baseline. Used by RESULT→BUILD
-- (retry) and by M.reset (new dungeon). Session counters intentionally
-- preserved so the W/L tally spans the program run.
local function reset_run(state)
    state.wave = 1
    state.budget_bonus = 0
    state.num_heroes = hero_count_for_wave(1)
    state.heroes = {}
    state.hero_queue = {}
    state.corpses = {}
    state.outcome = nil
    state.auto_step = true
    state.step_timer = 0
    state.tension_pause = 0
    clear_build(state)
    roll_wave(state)
end

-- BUILD → INVASION: promote the pre-rolled wave, snap session counters,
-- and flip the phase. Heroes' identities are preserved by reference so
-- the cards the player saw during BUILD are exactly who steps onto the
-- entrance.
local function start_invasion(state)
    state.heroes = {}
    state.hero_queue = {}
    state.corpses = {}
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
    if state.wave > state.session.best_wave then
        state.session.best_wave = state.wave
    end
    set_phase(state, M.PHASE_INVASION)
end

-- INVASION → BUILD (between waves): the wave just cleared. Bump the wave
-- counter, refund/reinforce the budget, prune dead monsters, restore HP
-- on survivors so they enter the next fight at full strength, and roll
-- the next wave's preview. The player drops back into BUILD with their
-- existing layout intact and N more points to spend on reinforcement.
local function advance_to_next_wave(state)
    state.wave = state.wave + 1
    state.budget_bonus = state.budget_bonus + M.WAVE_BUDGET_BONUS
    state.num_heroes = hero_count_for_wave(state.wave)

    local survivors = {}
    for _, m in ipairs(state.monsters) do
        if m.alive then
            m.hp = m.max_hp
            -- Wipe transient render flags so the next wave's animations
            -- don't reuse stale tween / attack-flash timestamps.
            m._smooth_tx, m._smooth_ty = nil, nil
            m._smooth_px, m._smooth_py = nil, nil
            m._tween_at = nil
            m._attack_at, m._death_at = nil, nil
            table.insert(survivors, m)
        end
    end
    state.monsters = survivors

    state.heroes = {}
    state.hero_queue = {}
    state.corpses = {}
    state.outcome = nil
    state.step_timer = 0
    roll_wave(state)
    set_phase(state, M.PHASE_BUILD)
end

-- The only player-driven phase transitions:
--   BUILD  → INVASION (start the wave)
--   RESULT → BUILD    (retry from wave 1, same dungeon)
-- INVASION transitions are automatic and handled inside step_invasion
-- (next-wave on heroes-dead, run-over on treasure-stolen).
function M.advance(state)
    if state.phase == M.PHASE_BUILD then
        start_invasion(state)
    elseif state.phase == M.PHASE_RESULT then
        reset_run(state)
        set_phase(state, M.PHASE_BUILD)
    end
end

function M.reset(state, seed)
    state.seed = seed
    state.rng = rand.new(seed)
    state.dungeon = dungeon.generate(seed)
    state.selected_monster_type = monster.GOBLIN
    state.selected_tool = M.TOOL_MONSTER
    reset_run(state)
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
    return M.BUDGET + state.budget_bonus - M.spent_budget(state)
end

-- Total budget pool currently available (initial + accumulated wave
-- bonuses). UI shows this so the player sees the pool growing across
-- waves, not just "spent / 14" forever.
function M.total_budget(state)
    return M.BUDGET + state.budget_bonus
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

-- Approach blocker: same as path_blocker but lets monsters be passable.
-- Used as the fallback A* when no strict path exists — the hero needs to
-- close on the monster blockade so it can hit "attack" once adjacent.
-- Peer heroes and orc corpses still block (heroes don't share tiles, and
-- corpses are physically impassable for their TTL).
local function approach_blocker(state, self_hero)
    return function(x, y)
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

-- Returns the path the given hero would take this tick. With no `h`,
-- defaults to the lead hero (preserves backward compat for callers that
-- only know about a single hero).
--
-- Two-stage search: first the strict path that respects monsters as
-- blockers (so the hero routes AROUND them when there's room), and on
-- failure a fallback path that ignores monsters (so a hero stuck behind
-- a 1-tile-wide chokepoint advances toward it instead of standing
-- still). The fallback is safe at step time because find_target_for_hero
-- runs first inside step_invasion: any monster at path[1] is already
-- adjacent and gets attacked before the move resolves.
function M.hero_path(state, h)
    h = h or state.heroes[1]
    if not h or not h.alive then return nil end
    local goal = state.dungeon.treasure
    local path = ai.find_path(state.dungeon,
        h.x, h.y, goal.x, goal.y,
        path_blocker(state, h))
    if path then return path end
    return ai.find_path(state.dungeon,
        h.x, h.y, goal.x, goal.y,
        approach_blocker(state, h))
end

-- Build-phase route preview: A* from entrance to treasure considering ONLY
-- walls (player + perimeter). Monsters are intentionally NOT blockers — at
-- runtime heroes fight through monster tiles, so the route a placed wall
-- creates is the same whether or not monsters sit on it. The build cursor
-- shows this path so the player sees how each wall reshapes it before
-- committing. Returns nil if no path exists (shouldn't happen since
-- can_place_wall guards connectivity).
function M.preview_path(state)
    local e, t = state.dungeon.entrance, state.dungeon.treasure
    return ai.find_path(state.dungeon, e.x, e.y, t.x, t.y)
end

-- Class-aware target selection for heroes:
--   Archer  → focus-fire the lowest-HP monster in range (counters the
--             goblin cluster + slime mini-spam by killing one at a time).
--   default → first monster in range (iteration order).
-- Dungeon is passed to in_range so the wall LoS check kicks in for the
-- ranged classes — heroes can't shoot through player-built walls.
local function find_target_for_hero(state, h)
    local best, best_hp = nil, math.huge
    if h.class == hero.ARCHER then
        for _, m in ipairs(state.monsters) do
            if m.alive and combat.in_range(h, m, state.dungeon) then
                if m.hp < best_hp then
                    best, best_hp = m, m.hp
                end
            end
        end
        return best
    end
    for _, m in ipairs(state.monsters) do
        if m.alive and combat.in_range(h, m, state.dungeon) then return m end
    end
    return nil
end

-- Monsters are all melee in v1.5, so LoS is moot here — adjacency is the
-- whole check. Skipping the dungeon arg keeps this code path zero-overhead.
local function find_hero_in_range(state, m)
    for _, h in ipairs(state.heroes) do
        if h.alive and combat.in_range(m, h) then return h end
    end
    return nil
end

-- Centralized "do an attack and dispatch its events". Routes the dealt
-- damage through on_event, fires the death event, and triggers the
-- monster-side death payoff (orc corpse / slime split). Used by every
-- attack flow: hero swing, mage splash, monster swing, warrior retaliate.
local function apply_attack(state, attacker, target, dmg, on_event)
    local dealt = combat.attack(attacker, target, dmg)
    if on_event then
        on_event("attack", attacker, target, dealt)
        if not target.alive then on_event("death", target) end
    end
    if not target.alive and target.type then
        on_monster_death(state, target)
    end
end

-- Mage AoE: snapshot cardinal-adjacent alive monsters BEFORE the main hit
-- lands, then deal floor(atk/MAGE_SPLASH_DIVISOR) to each surviving entry.
-- Snapshotting before the main hit is the design crux — if the main hit
-- kills a slime, the split spawns mini-slimes at slime's neighbors AND
-- those minis would otherwise be in range of the splash. Pre-snapshotting
-- lets slime split actually counter Mage AoE.
local function gather_splash_candidates(state, target)
    local out = {}
    for _, m in ipairs(state.monsters) do
        if m ~= target and m.alive
           and math.abs(m.x - target.x) + math.abs(m.y - target.y) == 1 then
            table.insert(out, m)
        end
    end
    return out
end

local function apply_mage_splash(state, mage, candidates, on_event)
    local splash = math.floor(mage.atk / hero.MAGE_SPLASH_DIVISOR)
    if splash <= 0 then return end
    for _, m in ipairs(candidates) do
        if m.alive then apply_attack(state, mage, m, splash, on_event) end
    end
end

-- Ranged-damage falloff: any swing landing from d > 1 deals floor(atk/2)
-- to the main target so a ranged hero can't 1-shot a 5-HP goblin from
-- outside engagement range. Adjacent (d=1) attacks stay at full atk.
-- Mage splash uses raw atk via MAGE_SPLASH_DIVISOR — splash damage is
-- the AoE identity and stays consistent regardless of distance.
local function damage_for_distance(h, target)
    local d = grid.manhattan(h.x, h.y, target.x, target.y)
    if d > 1 then return math.floor(h.atk / 2) end
    return h.atk
end

local function hero_attack(state, h, target, on_event)
    local mage_candidates = nil
    if h.class == hero.MAGE then
        mage_candidates = gather_splash_candidates(state, target)
    end
    apply_attack(state, h, target, damage_for_distance(h, target), on_event)
    if mage_candidates then
        apply_mage_splash(state, h, mage_candidates, on_event)
    end
end

-- Close-in: a ranged attacker that swung from d > 1 also takes one step
-- toward the still-alive target on the same tick. Without this, a hero
-- with a target perpetually in range never moves — they kite forever
-- and the player has no chance to engage. With it, the ranged hero is
-- guaranteed to be at d=1 within ~2 ticks, so monsters trade hits back.
-- Strict path (no monster fallback) so a freshly-spawned mini-slime on
-- path[1] doesn't get walked onto; if the lane isn't clear, the hero
-- just attacks again from the same tile next tick.
local function attempt_close_in(state, h, target, on_event)
    if not target.alive then return end
    if grid.manhattan(h.x, h.y, target.x, target.y) <= 1 then return end
    local path = ai.find_path(state.dungeon,
        h.x, h.y, target.x, target.y,
        path_blocker(state, h))
    if path and #path > 0 then
        h.x = path[1].x
        h.y = path[1].y
        if on_event then on_event("move", h) end
    end
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
-- Count alive entities across both arrays; used by the tension hook to
-- detect "anyone died this tick" without needing per-event tracking.
local function alive_count(arr)
    local n = 0
    for _, e in ipairs(arr) do if e.alive then n = n + 1 end end
    return n
end

-- Drama beat: any death OR a hero closing on the treasure delays the
-- next auto-step. Skipped if the wave already ended (phase ≠ INVASION) —
-- no next step to slow.
local function update_tension(state, monsters_alive_before, heroes_alive_before)
    if state.phase ~= M.PHASE_INVASION then return end
    local pause = 0
    if alive_count(state.monsters) < monsters_alive_before
       or alive_count(state.heroes) < heroes_alive_before then
        pause = math.max(pause, M.DRAMA_DEATH_PAUSE)
    end
    local goal = state.dungeon.treasure
    for _, h in ipairs(state.heroes) do
        if h.alive
           and grid.manhattan(h.x, h.y, goal.x, goal.y) <= M.DRAMA_APPROACH_DIST then
            pause = math.max(pause, M.DRAMA_APPROACH_PAUSE)
            break
        end
    end
    state.tension_pause = pause
end

function M.step_invasion(state, on_event)
    if state.phase ~= M.PHASE_INVASION then return end

    -- Snapshot alive counts for the post-step tension hook.
    local monsters_alive_before = alive_count(state.monsters)
    local heroes_alive_before   = alive_count(state.heroes)

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

    -- Hero turns: each alive hero attacks via class-aware targeting (Archer
    -- focus-fires; Mage adds splash). Iterating a snapshot keeps the order
    -- deterministic even if state.heroes is mutated mid-loop.
    local snapshot = {}
    for i, h in ipairs(state.heroes) do snapshot[i] = h end
    for _, h in ipairs(snapshot) do
        if h.alive then
            local target = find_target_for_hero(state, h)
            if target then
                hero_attack(state, h, target, on_event)
                attempt_close_in(state, h, target, on_event)
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
    -- bonus the moment a neighbor falls. Warrior retaliate fires inline:
    -- if the struck hero is a Warrior that survived and the attacker is
    -- still alive, it takes target.retaliate dmg back — and that retaliate
    -- can itself kill the monster (triggering its death payoff).
    for _, m in ipairs(pre_monsters) do
        if m.alive then
            local target = find_hero_in_range(state, m)
            if target then
                local dmg = monster.effective_atk(m, state.monsters)
                apply_attack(state, m, target, dmg, on_event)
                if target.alive and m.alive
                   and target.retaliate and target.retaliate > 0 then
                    apply_attack(state, target, m, target.retaliate, on_event)
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

    -- Drama beat: any kill or hero-on-the-treasure-doorstep slows the
    -- next auto-step. Computed before the wave-end check so the carry
    -- is set even when the killing blow is the last hero falling
    -- (though it's then cleared by advance_to_next_wave anyway).
    update_tension(state, monsters_alive_before, heroes_alive_before)

    -- End of wave: queue empty AND no living hero left in the dungeon.
    -- The run continues — the player drops back into BUILD with a
    -- refund and the next wave pre-rolled. The run only ends when a
    -- hero touches the treasure (handled inline above).
    if #state.hero_queue == 0 and not any_hero_alive(state) then
        advance_to_next_wave(state)
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
    -- Effective interval folds in any drama-beat carry-over set at the
    -- end of the previous step (death this tick, hero closing on the
    -- treasure). Consumed once on the next step so the cadence returns
    -- to STEP_INTERVAL unless another dramatic event re-triggers it.
    local interval = M.STEP_INTERVAL + (state.tension_pause or 0)
    while state.step_timer >= interval do
        state.step_timer = state.step_timer - interval
        state.tension_pause = 0
        M.step_invasion(state, on_event)
        if state.phase ~= M.PHASE_INVASION then
            state.step_timer = 0
            break
        end
        interval = M.STEP_INTERVAL + (state.tension_pause or 0)
    end
end

return M
