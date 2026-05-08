package.path = "./?.lua;./?/init.lua;" .. package.path

local state = require("src.state")
local dungeon = require("src.dungeon")
local monster = require("src.monster")
local grid = require("src.grid")
local ai = require("src.ai")

-- First n interior tiles (2..W-1, 2..H-1) that aren't the treasure for the
-- given state. Stable per-seed so tests are deterministic.
local function free_tiles(s, n)
    local tiles = {}
    for y = 2, grid.HEIGHT - 1 do
        for x = 2, grid.WIDTH - 1 do
            if not (x == s.dungeon.treasure.x and y == s.dungeon.treasure.y) then
                table.insert(tiles, { x = x, y = y })
                if #tiles == n then return tiles end
            end
        end
    end
    return tiles
end

-- Find the first floor neighbor of (hx, hy). Combined with state.advance(),
-- this lets combat tests place a monster directly adjacent to the hero
-- regardless of where the seed put the entrance.
local function first_floor_neighbor(s, hx, hy)
    local dirs = { { 0, 1 }, { 1, 0 }, { 0, -1 }, { -1, 0 } }
    for _, d in ipairs(dirs) do
        local nx, ny = hx + d[1], hy + d[2]
        if s.dungeon.grid[ny] and s.dungeon.grid[ny][nx] == dungeon.FLOOR
           and not (nx == s.dungeon.entrance.x and ny == s.dungeon.entrance.y)
           and not (nx == s.dungeon.treasure.x and ny == s.dungeon.treasure.y) then
            return nx, ny
        end
    end
end

-- Direct injection bypasses placement rules — needed for combat tests that
-- want a specific monster on a specific tile.
local function inject_monster(s, type_key, x, y)
    local m = monster.new(type_key, x, y)
    table.insert(s.monsters, m)
    return m
end

describe("state", function()
    describe("new", function()
        it("starts in the build phase", function()
            assert.are.equal(state.PHASE_BUILD, state.new(1).phase)
        end)

        it("stores the seed it was given", function()
            assert.are.equal(99, state.new(99).seed)
        end)

        it("generates the dungeon for that seed", function()
            local s = state.new(42)
            local expected = dungeon.generate(42)
            assert.are.same(expected.grid, s.dungeon.grid)
            assert.are.same(expected.entrance, s.dungeon.entrance)
            assert.are.same(expected.treasure, s.dungeon.treasure)
        end)

        it("starts with no monsters and goblin selected", function()
            local s = state.new(1)
            assert.are.equal(0, #s.monsters)
            assert.are.equal(monster.GOBLIN, s.selected_monster_type)
        end)

        it("starts with no hero and no outcome", function()
            local s = state.new(1)
            assert.is_nil(s.heroes[1])
            assert.is_nil(s.outcome)
        end)

        it("starts with auto-step enabled and timer at zero", function()
            local s = state.new(1)
            assert.is_true(s.auto_step)
            assert.are.equal(0, s.step_timer)
        end)
    end)

    describe("advance", function()
        it("cycles build -> invasion -> result -> build", function()
            local s = state.new(1)
            assert.are.equal(state.PHASE_BUILD, s.phase)
            state.advance(s)
            assert.are.equal(state.PHASE_INVASION, s.phase)
            state.advance(s)
            assert.are.equal(state.PHASE_RESULT, s.phase)
            state.advance(s)
            assert.are.equal(state.PHASE_BUILD, s.phase)
        end)

        it("does not regenerate the dungeon when wrapping back to build", function()
            local s = state.new(7)
            local original_grid = s.dungeon.grid
            for _ = 1, 3 do state.advance(s) end
            assert.are.equal(state.PHASE_BUILD, s.phase)
            assert.are.equal(original_grid, s.dungeon.grid)
        end)

        it("re-arms auto-step on entering invasion", function()
            local s = state.new(7)
            s.auto_step = false
            s.step_timer = 99
            state.advance(s)
            assert.is_true(s.auto_step)
            assert.are.equal(0, s.step_timer)
        end)
    end)

    describe("reset", function()
        it("returns to build with a fresh dungeon for the new seed", function()
            local s = state.new(1)
            state.advance(s)
            state.advance(s)
            state.reset(s, 42)
            assert.are.equal(state.PHASE_BUILD, s.phase)
            assert.are.equal(42, s.seed)
            assert.are.same(dungeon.generate(42).grid, s.dungeon.grid)
        end)

        it("clears placed monsters and resets the selection", function()
            local s = state.new(7)
            local t = free_tiles(s, 1)[1]
            state.try_place_monster(s, t.x, t.y)
            state.select_monster_type(s, monster.ORC)
            state.reset(s, 42)
            assert.are.equal(0, #s.monsters)
            assert.are.equal(monster.GOBLIN, s.selected_monster_type)
        end)

        it("clears placed walls and resets the tool to monster", function()
            local s = state.new(7)
            local t = free_tiles(s, 1)[1]
            state.try_place_wall(s, t.x, t.y)
            state.select_tool(s, state.TOOL_WALL)
            state.reset(s, 42)
            assert.are.equal(state.TOOL_MONSTER, s.selected_tool)
            assert.are.same({}, s.placed_walls)
        end)

        it("clears the hero and outcome", function()
            local s = state.new(7)
            state.advance(s)
            s.outcome = state.OUTCOME_TREASURE_STOLEN
            state.reset(s, 42)
            assert.is_nil(s.heroes[1])
            assert.is_nil(s.outcome)
        end)

        it("re-arms auto-step", function()
            local s = state.new(7)
            s.auto_step = false
            s.step_timer = 99
            state.reset(s, 42)
            assert.is_true(s.auto_step)
            assert.are.equal(0, s.step_timer)
        end)
    end)

    describe("monster placement", function()
        it("places a monster on a valid floor tile", function()
            local s = state.new(7)
            local t = free_tiles(s, 1)[1]
            assert.is_true(state.try_place_monster(s, t.x, t.y))
            assert.are.equal(1, #s.monsters)
            assert.are.equal(monster.GOBLIN, s.monsters[1].type)
            assert.are.equal(t.x, s.monsters[1].x)
            assert.are.equal(t.y, s.monsters[1].y)
        end)

        it("rejects placement on a wall (corner)", function()
            local s = state.new(7)
            assert.is_false(state.try_place_monster(s, 1, 1))
            assert.are.equal(0, #s.monsters)
        end)

        it("rejects placement on the entrance", function()
            local s = state.new(7)
            assert.is_false(state.try_place_monster(s,
                s.dungeon.entrance.x, s.dungeon.entrance.y))
        end)

        it("rejects placement on the treasure", function()
            local s = state.new(7)
            assert.is_false(state.try_place_monster(s,
                s.dungeon.treasure.x, s.dungeon.treasure.y))
        end)

        it("rejects placement on a tile already occupied by a monster", function()
            local s = state.new(7)
            local t = free_tiles(s, 1)[1]
            assert.is_true(state.try_place_monster(s, t.x, t.y))
            assert.is_false(state.try_place_monster(s, t.x, t.y))
            assert.are.equal(1, #s.monsters)
        end)

        it("caps placement at the budget", function()
            -- Goblin costs 2, BUDGET 10 — exactly 5 fit, the 6th must fail.
            local s = state.new(7)
            local goblin_cost = monster.TYPES[monster.GOBLIN].cost
            local max_goblins = math.floor(state.BUDGET / goblin_cost)
            local tiles = free_tiles(s, max_goblins + 1)
            for i = 1, max_goblins do
                assert.is_true(state.try_place_monster(s, tiles[i].x, tiles[i].y))
            end
            local extra = tiles[max_goblins + 1]
            assert.is_false(state.try_place_monster(s, extra.x, extra.y))
            assert.are.equal(max_goblins, #s.monsters)
        end)

        it("rejects placement when the selected type would exceed remaining budget", function()
            -- Spend until exactly 2 remains, then verify Orc/Slime fail
            -- and a Goblin (cost 2) just fits.
            local s = state.new(7)
            local goblin_cost = monster.TYPES[monster.GOBLIN].cost
            local n_goblins = math.floor((state.BUDGET - 2) / goblin_cost)
            local tiles = free_tiles(s, n_goblins + 1)
            for i = 1, n_goblins do
                assert.is_true(state.try_place_monster(s, tiles[i].x, tiles[i].y))
            end
            assert.are.equal(2, state.remaining_budget(s))
            state.select_monster_type(s, monster.ORC)
            assert.is_false(state.try_place_monster(s,
                tiles[n_goblins + 1].x, tiles[n_goblins + 1].y))
            state.select_monster_type(s, monster.SLIME)
            assert.is_false(state.try_place_monster(s,
                tiles[n_goblins + 1].x, tiles[n_goblins + 1].y))
            state.select_monster_type(s, monster.GOBLIN)
            assert.is_true(state.try_place_monster(s,
                tiles[n_goblins + 1].x, tiles[n_goblins + 1].y))
            assert.are.equal(0, state.remaining_budget(s))
        end)

        it("frees budget when a monster is removed", function()
            local s = state.new(7)
            local t = free_tiles(s, 1)[1]
            state.select_monster_type(s, monster.ORC)
            state.try_place_monster(s, t.x, t.y)
            assert.are.equal(state.BUDGET - 4, state.remaining_budget(s))
            state.try_remove_monster(s, t.x, t.y)
            assert.are.equal(state.BUDGET, state.remaining_budget(s))
        end)

        it("rejects placement outside the BUILD phase", function()
            local s = state.new(7)
            local t = free_tiles(s, 1)[1]
            state.advance(s)
            assert.is_false(state.try_place_monster(s, t.x, t.y))
        end)

        it("uses the selected type when placing", function()
            local s = state.new(7)
            state.select_monster_type(s, monster.ORC)
            local t = free_tiles(s, 1)[1]
            assert.is_true(state.try_place_monster(s, t.x, t.y))
            assert.are.equal(monster.ORC, s.monsters[1].type)
        end)
    end)

    describe("tool selection", function()
        it("starts with the monster tool selected", function()
            local s = state.new(1)
            assert.are.equal(state.TOOL_MONSTER, s.selected_tool)
        end)

        it("switches to the wall tool", function()
            local s = state.new(1)
            assert.is_true(state.select_tool(s, state.TOOL_WALL))
            assert.are.equal(state.TOOL_WALL, s.selected_tool)
        end)

        it("rejects unknown tools and leaves the selection unchanged", function()
            local s = state.new(1)
            assert.is_false(state.select_tool(s, "trap"))
            assert.are.equal(state.TOOL_MONSTER, s.selected_tool)
        end)
    end)

    describe("wall placement", function()
        it("places a wall on a valid floor tile", function()
            local s = state.new(7)
            local t = free_tiles(s, 1)[1]
            assert.is_true(state.try_place_wall(s, t.x, t.y))
            assert.are.equal(dungeon.WALL, s.dungeon.grid[t.y][t.x])
        end)

        it("rejects placement on the perimeter", function()
            local s = state.new(7)
            assert.is_false(state.try_place_wall(s, 1, 1))
        end)

        it("rejects placement on the entrance", function()
            local s = state.new(7)
            assert.is_false(state.try_place_wall(s,
                s.dungeon.entrance.x, s.dungeon.entrance.y))
        end)

        it("rejects placement on the treasure", function()
            local s = state.new(7)
            assert.is_false(state.try_place_wall(s,
                s.dungeon.treasure.x, s.dungeon.treasure.y))
        end)

        it("rejects placement on a tile already occupied by a monster", function()
            local s = state.new(7)
            local t = free_tiles(s, 1)[1]
            state.try_place_monster(s, t.x, t.y)
            assert.is_false(state.try_place_wall(s, t.x, t.y))
        end)

        it("rejects placement outside BUILD phase", function()
            local s = state.new(7)
            local t = free_tiles(s, 1)[1]
            state.advance(s)
            assert.is_false(state.try_place_wall(s, t.x, t.y))
        end)

        it("rejects a wall that would disconnect entrance from treasure", function()
            -- Build a 1-tile-wide neck around the entrance: walling every
            -- floor neighbor of the door is illegal because entrance is
            -- then sealed off.
            local s = state.new(7)
            local e = s.dungeon.entrance
            local neighbors = {
                { e.x + 1, e.y }, { e.x - 1, e.y },
                { e.x, e.y + 1 }, { e.x, e.y - 1 },
            }
            local floor_neighbors = {}
            for _, n in ipairs(neighbors) do
                if s.dungeon.grid[n[2]] and s.dungeon.grid[n[2]][n[1]] == dungeon.FLOOR then
                    table.insert(floor_neighbors, n)
                end
            end
            -- Wall every floor neighbor except the last; the last one would
            -- complete the seal and must be rejected.
            for i = 1, #floor_neighbors - 1 do
                local n = floor_neighbors[i]
                assert.is_true(state.try_place_wall(s, n[1], n[2]))
            end
            local last = floor_neighbors[#floor_neighbors]
            assert.is_false(state.try_place_wall(s, last[1], last[2]))
        end)

        it("rejects placement on an existing wall", function()
            local s = state.new(7)
            local t = free_tiles(s, 1)[1]
            assert.is_true(state.try_place_wall(s, t.x, t.y))
            assert.is_false(state.try_place_wall(s, t.x, t.y))
        end)

        it("each placed wall spends WALL_COST from the budget", function()
            local s = state.new(7)
            local t = free_tiles(s, 1)[1]
            local before = state.remaining_budget(s)
            assert.is_true(state.try_place_wall(s, t.x, t.y))
            assert.are.equal(before - state.WALL_COST, state.remaining_budget(s))
        end)

        it("rejects wall placement when remaining budget is zero", function()
            -- Spend the full budget on goblins, then try to wall a free tile.
            local s = state.new(7)
            local goblin_cost = monster.TYPES[monster.GOBLIN].cost
            local n_goblins = math.floor(state.BUDGET / goblin_cost)
            local tiles = free_tiles(s, n_goblins + 1)
            for i = 1, n_goblins do
                assert.is_true(state.try_place_monster(s, tiles[i].x, tiles[i].y))
            end
            assert.are.equal(0, state.remaining_budget(s))
            local extra = tiles[n_goblins + 1]
            assert.is_false(state.try_place_wall(s, extra.x, extra.y))
        end)

        it("frees budget when a wall is removed", function()
            local s = state.new(7)
            local t = free_tiles(s, 1)[1]
            local before = state.remaining_budget(s)
            state.try_place_wall(s, t.x, t.y)
            state.try_remove_wall(s, t.x, t.y)
            assert.are.equal(before, state.remaining_budget(s))
        end)
    end)

    describe("wall removal", function()
        it("reverts a player-placed wall back to floor", function()
            local s = state.new(7)
            local t = free_tiles(s, 1)[1]
            state.try_place_wall(s, t.x, t.y)
            assert.is_true(state.try_remove_wall(s, t.x, t.y))
            assert.are.equal(dungeon.FLOOR, s.dungeon.grid[t.y][t.x])
        end)

        it("does not remove the perimeter wall", function()
            local s = state.new(7)
            assert.is_false(state.try_remove_wall(s, 1, 1))
            assert.are.equal(dungeon.WALL, s.dungeon.grid[1][1])
        end)

        it("does not remove an empty floor tile", function()
            local s = state.new(7)
            local t = free_tiles(s, 1)[1]
            assert.is_false(state.try_remove_wall(s, t.x, t.y))
        end)

        it("rejects removal outside BUILD phase", function()
            local s = state.new(7)
            local t = free_tiles(s, 1)[1]
            state.try_place_wall(s, t.x, t.y)
            state.advance(s)
            assert.is_false(state.try_remove_wall(s, t.x, t.y))
            assert.are.equal(dungeon.WALL, s.dungeon.grid[t.y][t.x])
        end)
    end)

    describe("hero pathing around walls", function()
        it("routes the hero around a player-placed wall", function()
            -- Pick the midpoint of the natural A* path so the wall lands
            -- well inside the room (not at the entrance neck) and a detour
            -- definitely exists.
            local s = state.new(7)
            local original = ai.find_path(s.dungeon,
                s.dungeon.entrance.x, s.dungeon.entrance.y,
                s.dungeon.treasure.x, s.dungeon.treasure.y)
            assert.is_not_nil(original)
            local mid = original[math.floor(#original / 2)]
            local wx, wy = mid.x, mid.y

            assert.is_true(state.try_place_wall(s, wx, wy))
            state.advance(s)
            local path = state.hero_path(s)
            assert.is_not_nil(path)
            for _, p in ipairs(path) do
                assert.is_false(p.x == wx and p.y == wy)
            end
        end)
    end)

    describe("monster removal", function()
        it("removes a monster from a tile that has one", function()
            local s = state.new(7)
            local t = free_tiles(s, 1)[1]
            state.try_place_monster(s, t.x, t.y)
            assert.is_true(state.try_remove_monster(s, t.x, t.y))
            assert.are.equal(0, #s.monsters)
        end)

        it("returns false when no monster is on the tile", function()
            local s = state.new(7)
            local t = free_tiles(s, 1)[1]
            assert.is_false(state.try_remove_monster(s, t.x, t.y))
        end)

        it("only affects the targeted tile when several monsters are placed", function()
            local s = state.new(7)
            local tiles = free_tiles(s, 2)
            state.try_place_monster(s, tiles[1].x, tiles[1].y)
            state.try_place_monster(s, tiles[2].x, tiles[2].y)
            assert.is_true(state.try_remove_monster(s, tiles[1].x, tiles[1].y))
            assert.are.equal(1, #s.monsters)
            assert.are.equal(tiles[2].x, s.monsters[1].x)
            assert.are.equal(tiles[2].y, s.monsters[1].y)
        end)

        it("rejects removal outside the BUILD phase", function()
            local s = state.new(7)
            local t = free_tiles(s, 1)[1]
            state.try_place_monster(s, t.x, t.y)
            state.advance(s)
            assert.is_false(state.try_remove_monster(s, t.x, t.y))
            assert.are.equal(1, #s.monsters)
        end)
    end)

    describe("select_monster_type", function()
        it("changes the active selection for known types", function()
            local s = state.new(1)
            assert.is_true(state.select_monster_type(s, monster.SLIME))
            assert.are.equal(monster.SLIME, s.selected_monster_type)
        end)

        it("rejects unknown types and leaves the selection unchanged", function()
            local s = state.new(1)
            assert.is_false(state.select_monster_type(s, "dragon"))
            assert.are.equal(monster.GOBLIN, s.selected_monster_type)
        end)
    end)

    describe("session counters", function()
        it("starts at zero wins/losses", function()
            local s = state.new(1)
            assert.are.equal(0, s.session.wins)
            assert.are.equal(0, s.session.losses)
        end)

        it("increments wins on hero_dead transition", function()
            local s = state.new(7)
            state.advance(s)
            s.hero_queue = {}
            s.heroes[1].hp = 1
            local mx, my = first_floor_neighbor(s, s.heroes[1].x, s.heroes[1].y)
            inject_monster(s, monster.ORC, mx, my)
            state.step_invasion(s)
            assert.are.equal(state.OUTCOME_HERO_DEAD, s.outcome)
            assert.are.equal(1, s.session.wins)
            assert.are.equal(0, s.session.losses)
        end)

        it("increments losses on treasure_stolen transition", function()
            local s = state.new(7)
            state.advance(s)
            for _ = 1, 200 do
                if s.phase == state.PHASE_RESULT then break end
                state.step_invasion(s)
            end
            assert.are.equal(state.OUTCOME_TREASURE_STOLEN, s.outcome)
            assert.are.equal(0, s.session.wins)
            assert.are.equal(1, s.session.losses)
        end)

        it("preserves session counters across reset", function()
            local s = state.new(7)
            s.session.wins = 3
            s.session.losses = 2
            state.reset(s, 42)
            assert.are.equal(3, s.session.wins)
            assert.are.equal(2, s.session.losses)
        end)
    end)

    describe("wave_preview", function()
        it("pre-rolls num_heroes heroes at state.new", function()
            local s = state.new(7)
            assert.are.equal(s.num_heroes, #s.wave_preview)
            for _, h in ipairs(s.wave_preview) do
                assert.is_not_nil(h.class)
                assert.is_true(h.hp > 0)
                assert.is_true(h.atk > 0)
            end
        end)

        it("invasion promotes preview heroes by reference (no re-roll)", function()
            local s = state.new(7)
            local previewed = { s.wave_preview[1], s.wave_preview[2], s.wave_preview[3] }
            state.advance(s)
            -- heroes[1] is the same table as wave_preview[1] before advance.
            assert.are.equal(previewed[1], s.heroes[1])
            assert.are.equal(previewed[2], s.hero_queue[1])
            assert.are.equal(previewed[3], s.hero_queue[2])
            assert.are.equal(0, #s.wave_preview)
        end)

        it("re-rolls a fresh preview on return to build", function()
            local s = state.new(7)
            state.advance(s)  -- build -> inv
            assert.are.equal(0, #s.wave_preview)
            state.advance(s)  -- inv -> result
            state.advance(s)  -- result -> build
            assert.are.equal(s.num_heroes, #s.wave_preview)
        end)

        it("reset re-rolls a fresh preview", function()
            local s = state.new(7)
            state.advance(s)
            assert.are.equal(0, #s.wave_preview)
            state.reset(s, 42)
            assert.are.equal(s.num_heroes, #s.wave_preview)
        end)

        it("preview is deterministic per seed", function()
            local a = state.new(7)
            local b = state.new(7)
            for i = 1, a.num_heroes do
                assert.are.equal(a.wave_preview[i].class, b.wave_preview[i].class)
                assert.are.equal(a.wave_preview[i].hp,    b.wave_preview[i].hp)
                assert.are.equal(a.wave_preview[i].atk,   b.wave_preview[i].atk)
            end
        end)
    end)

    describe("invasion", function()
        it("spawns a hero at the entrance when entering invasion", function()
            local s = state.new(7)
            assert.is_nil(s.heroes[1])
            state.advance(s)
            assert.is_not_nil(s.heroes[1])
            assert.are.equal(s.dungeon.entrance.x, s.heroes[1].x)
            assert.are.equal(s.dungeon.entrance.y, s.heroes[1].y)
        end)

        it("seeds the run rng so hero gen is deterministic per seed", function()
            local a = state.new(7)
            state.advance(a)
            local b = state.new(7)
            state.advance(b)
            assert.are.equal(a.heroes[1].class, b.heroes[1].class)
            assert.are.equal(a.heroes[1].hp, b.heroes[1].hp)
            assert.are.equal(a.heroes[1].atk, b.heroes[1].atk)
        end)

        it("clears the hero on advance back to build", function()
            local s = state.new(7)
            state.advance(s)
            state.advance(s)
            assert.is_not_nil(s.heroes[1])
            state.advance(s)
            assert.is_nil(s.heroes[1])
        end)

        it("re-spawns a fresh hero on a second invasion", function()
            local s = state.new(7)
            state.advance(s)
            local first = s.heroes[1]
            state.advance(s); state.advance(s)
            state.advance(s)
            assert.is_not_nil(s.heroes[1])
            assert.are.equal(s.dungeon.entrance.x, s.heroes[1].x)
            assert.are.equal(s.dungeon.entrance.y, s.heroes[1].y)
            assert.are.equal(s.heroes[1].max_hp, s.heroes[1].hp)
            assert.are_not.equal(first, s.heroes[1])
        end)

        describe("step_invasion (movement)", function()
            it("moves the hero one tile closer to the treasure when no monster is in range", function()
                local s = state.new(7)
                state.advance(s)
                local d_before = grid.manhattan(
                    s.heroes[1].x, s.heroes[1].y,
                    s.dungeon.treasure.x, s.dungeon.treasure.y)
                state.step_invasion(s)
                local d_after = grid.manhattan(
                    s.heroes[1].x, s.heroes[1].y,
                    s.dungeon.treasure.x, s.dungeon.treasure.y)
                assert.are.equal(d_before - 1, d_after)
            end)

            it("transitions to RESULT with treasure_stolen when hero arrives", function()
                local s = state.new(7)
                state.advance(s)
                for _ = 1, 200 do
                    if s.phase == state.PHASE_RESULT then break end
                    state.step_invasion(s)
                end
                assert.are.equal(state.PHASE_RESULT, s.phase)
                assert.are.equal(state.OUTCOME_TREASURE_STOLEN, s.outcome)
                assert.are.equal(s.dungeon.treasure.x, s.heroes[1].x)
                assert.are.equal(s.dungeon.treasure.y, s.heroes[1].y)
            end)

            it("no-ops outside the INVASION phase", function()
                local s = state.new(7)
                state.step_invasion(s)
                assert.is_nil(s.heroes[1])
                assert.are.equal(state.PHASE_BUILD, s.phase)
            end)
        end)

        describe("step_invasion (combat)", function()
            it("hero attacks an adjacent monster instead of moving", function()
                local s = state.new(7)
                state.advance(s)
                local hx, hy = s.heroes[1].x, s.heroes[1].y
                local mx, my = first_floor_neighbor(s, hx, hy)
                local m = inject_monster(s, monster.GOBLIN, mx, my)
                local m_hp_before = m.hp

                state.step_invasion(s)

                assert.are.equal(hx, s.heroes[1].x)
                assert.are.equal(hy, s.heroes[1].y)
                assert.are.equal(m_hp_before - s.heroes[1].atk, m.hp)
            end)

            it("monster in range attacks the hero on the same turn", function()
                local s = state.new(7)
                state.advance(s)
                local mx, my = first_floor_neighbor(s, s.heroes[1].x, s.heroes[1].y)
                inject_monster(s, monster.ORC, mx, my)
                local hp_before = s.heroes[1].hp

                state.step_invasion(s)

                assert.is_true(s.heroes[1].hp < hp_before)
            end)

            it("the wave ends with hero_dead when the last hero falls", function()
                -- Empty the queue to simulate a one-hero wave: only the
                -- leader is in play, so its death must end the run.
                local s = state.new(7)
                state.advance(s)
                s.hero_queue = {}
                s.heroes[1].hp = 1
                local mx, my = first_floor_neighbor(s, s.heroes[1].x, s.heroes[1].y)
                inject_monster(s, monster.ORC, mx, my)

                state.step_invasion(s)

                assert.are.equal(state.PHASE_RESULT, s.phase)
                assert.are.equal(state.OUTCOME_HERO_DEAD, s.outcome)
                assert.is_false(s.heroes[1].alive)
            end)

            it("a single hero dying does not end the wave when peers remain", function()
                local s = state.new(7)
                state.advance(s)
                assert.is_true(s.num_heroes > 1)
                s.heroes[1].hp = 1
                local mx, my = first_floor_neighbor(s, s.heroes[1].x, s.heroes[1].y)
                inject_monster(s, monster.ORC, mx, my)

                state.step_invasion(s)

                assert.is_false(s.heroes[1].alive)
                assert.are.equal(state.PHASE_INVASION, s.phase)
            end)

            it("once a monster dies, hero proceeds to move on the following turn", function()
                local s = state.new(7)
                state.advance(s)
                local hx, hy = s.heroes[1].x, s.heroes[1].y
                local mx, my = first_floor_neighbor(s, hx, hy)
                local m = inject_monster(s, monster.GOBLIN, mx, my)
                m.hp = 1

                state.step_invasion(s)
                assert.is_false(m.alive)
                assert.are.equal(hx, s.heroes[1].x)
                assert.are.equal(hy, s.heroes[1].y)
                assert.is_true(s.heroes[1].alive)

                state.step_invasion(s)
                assert.is_true(s.heroes[1].x ~= hx or s.heroes[1].y ~= hy)
            end)
        end)

        describe("multi-hero waves", function()
            it("queues additional heroes on advance to invasion", function()
                local s = state.new(7)
                state.advance(s)
                assert.are.equal(1, #s.heroes)
                assert.are.equal(s.num_heroes - 1, #s.hero_queue)
            end)

            it("dequeues a hero onto the entrance the tick after it clears", function()
                local s = state.new(7)
                state.advance(s)
                -- One step: heroes[1] moves off the entrance and (at end of
                -- tick) heroes[2] is pulled onto it. heroes[2] does not act
                -- this tick, so it remains on the entrance tile.
                state.step_invasion(s)
                assert.is_true(s.heroes[1].x ~= s.dungeon.entrance.x
                    or s.heroes[1].y ~= s.dungeon.entrance.y)
                assert.are.equal(2, #s.heroes)
                assert.are.equal(s.dungeon.entrance.x, s.heroes[2].x)
                assert.are.equal(s.dungeon.entrance.y, s.heroes[2].y)
            end)

            it("only the leader can occupy the entrance at a time", function()
                local s = state.new(7)
                state.advance(s)
                -- Before stepping, the queue still holds num_heroes - 1.
                -- A step shouldn't pull anyone new while heroes[1] sits on
                -- the entrance.
                local pre_queue = #s.hero_queue
                -- Pin heroes[1] in place by injecting a monster adjacent so
                -- it attacks rather than moves.
                local mx, my = first_floor_neighbor(s,
                    s.heroes[1].x, s.heroes[1].y)
                inject_monster(s, monster.GOBLIN, mx, my)
                state.step_invasion(s)
                assert.are.equal(s.dungeon.entrance.x, s.heroes[1].x)
                assert.are.equal(s.dungeon.entrance.y, s.heroes[1].y)
                assert.are.equal(pre_queue, #s.hero_queue)
                assert.are.equal(1, #s.heroes)
            end)

            it("treasure is stolen the moment any hero reaches it", function()
                local s = state.new(7)
                state.advance(s)
                for _ = 1, 200 do
                    if s.phase == state.PHASE_RESULT then break end
                    state.step_invasion(s)
                end
                assert.are.equal(state.PHASE_RESULT, s.phase)
                assert.are.equal(state.OUTCOME_TREASURE_STOLEN, s.outcome)
            end)

            it("paths around peer heroes that occupy the lead tile", function()
                -- Force heroes[1] to stand still (engaged with a monster)
                -- and observe heroes[2]'s computed path: it must NOT step
                -- onto heroes[1]'s tile.
                local s = state.new(7)
                state.advance(s)
                local mx, my = first_floor_neighbor(s,
                    s.heroes[1].x, s.heroes[1].y)
                inject_monster(s, monster.GOBLIN, mx, my)
                -- Step until heroes[2] spawns.
                for _ = 1, 5 do
                    if #s.heroes >= 2 then break end
                    state.step_invasion(s)
                end
                -- Forcibly move heroes[1] back to entrance and clear the
                -- queue so we can isolate heroes[2]'s pathing decision.
                if #s.heroes >= 2 then
                    local h1, h2 = s.heroes[1], s.heroes[2]
                    local path = state.hero_path(s, h2)
                    if path and #path > 0 then
                        for _, p in ipairs(path) do
                            assert.is_false(p.x == h1.x and p.y == h1.y)
                        end
                    end
                end
            end)
        end)

        describe("hero_path", function()
            it("returns nil when there is no hero", function()
                local s = state.new(7)
                assert.is_nil(state.hero_path(s))
            end)

            it("returns a path of Manhattan length on an empty room", function()
                local s = state.new(7)
                state.advance(s)
                local path = state.hero_path(s)
                assert.is_not_nil(path)
                assert.are.equal(
                    grid.manhattan(s.heroes[1].x, s.heroes[1].y,
                        s.dungeon.treasure.x, s.dungeon.treasure.y),
                    #path)
            end)
        end)

        describe("toggle_auto_step", function()
            it("flips auto_step and resets the step timer", function()
                local s = state.new(7)
                state.advance(s)
                s.step_timer = 0.1
                assert.is_true(s.auto_step)

                state.toggle_auto_step(s)
                assert.is_false(s.auto_step)
                assert.are.equal(0, s.step_timer)

                state.toggle_auto_step(s)
                assert.is_true(s.auto_step)
                assert.are.equal(0, s.step_timer)
            end)
        end)

        describe("update (auto-step)", function()
            it("does nothing outside the INVASION phase", function()
                local s = state.new(7)
                state.update(s, 999)
                assert.are.equal(state.PHASE_BUILD, s.phase)
            end)

            it("does nothing while paused", function()
                local s = state.new(7)
                state.advance(s)
                s.auto_step = false
                local hx, hy = s.heroes[1].x, s.heroes[1].y
                state.update(s, 999)
                assert.are.equal(hx, s.heroes[1].x)
                assert.are.equal(hy, s.heroes[1].y)
            end)

            it("does not step before STEP_INTERVAL elapses", function()
                local s = state.new(7)
                state.advance(s)
                local hx, hy = s.heroes[1].x, s.heroes[1].y
                state.update(s, state.STEP_INTERVAL - 0.001)
                assert.are.equal(hx, s.heroes[1].x)
                assert.are.equal(hy, s.heroes[1].y)
            end)

            it("steps once after STEP_INTERVAL elapses", function()
                local s = state.new(7)
                state.advance(s)
                local hx, hy = s.heroes[1].x, s.heroes[1].y
                state.update(s, state.STEP_INTERVAL + 0.001)
                assert.is_true(s.heroes[1].x ~= hx or s.heroes[1].y ~= hy)
            end)

            it("accumulates dt across multiple calls", function()
                local s = state.new(7)
                state.advance(s)
                local hx, hy = s.heroes[1].x, s.heroes[1].y
                for _ = 1, 5 do
                    state.update(s, state.STEP_INTERVAL / 5 + 0.001)
                end
                assert.is_true(s.heroes[1].x ~= hx or s.heroes[1].y ~= hy)
            end)

            it("fast-forwards multiple steps when given a large dt", function()
                local s = state.new(7)
                state.advance(s)
                local d_initial = grid.manhattan(
                    s.heroes[1].x, s.heroes[1].y,
                    s.dungeon.treasure.x, s.dungeon.treasure.y)
                state.update(s, state.STEP_INTERVAL * 3 + 0.001)
                if s.phase == state.PHASE_INVASION then
                    local d_after = grid.manhattan(
                        s.heroes[1].x, s.heroes[1].y,
                        s.dungeon.treasure.x, s.dungeon.treasure.y)
                    assert.is_true(d_initial - d_after >= 3)
                else
                    -- Hero reached the treasure; that is the only legal way
                    -- the phase could have shifted under just movement.
                    assert.are.equal(state.PHASE_RESULT, s.phase)
                end
            end)

            it("stops stepping the moment phase leaves INVASION", function()
                local s = state.new(7)
                state.advance(s)
                -- Run forward until the hero arrives at the treasure.
                state.update(s, 999)
                assert.are.equal(state.PHASE_RESULT, s.phase)
                local frozen_x, frozen_y = s.heroes[1].x, s.heroes[1].y
                state.update(s, 999)
                assert.are.equal(frozen_x, s.heroes[1].x)
                assert.are.equal(frozen_y, s.heroes[1].y)
            end)
        end)
    end)
end)
