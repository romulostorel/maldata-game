package.path = "./?.lua;./?/init.lua;" .. package.path

local state = require("src.state")
local dungeon = require("src.dungeon")
local monster = require("src.monster")
local grid = require("src.grid")
local ai = require("src.ai")
local hero = require("src.hero")

-- First n interior FLOOR tiles (2..W-1, 2..H-1) that aren't the treasure
-- for the given state. Filters by grid value so it skips internal walls
-- and pillars carved by the procgen layout. Stable per-seed.
local function free_tiles(s, n)
    local tiles = {}
    for y = 2, grid.HEIGHT - 1 do
        for x = 2, grid.WIDTH - 1 do
            if s.dungeon.grid[y][x] == dungeon.FLOOR
               and not (x == s.dungeon.treasure.x and y == s.dungeon.treasure.y)
               and not (x == s.dungeon.entrance.x and y == s.dungeon.entrance.y) then
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

-- Build a synthetic hero of a chosen class at (x, y) with full class HP/ATK.
-- Used to pin invasion tests to a specific class regardless of the seed's
-- roll (and bypass the lead-warrior swap when verifying default behaviors).
local function make_hero(class_key, x, y)
    local c = hero.CLASSES[class_key]
    return {
        class = class_key,
        x = x, y = y,
        hp = c.hp, max_hp = c.hp,
        atk = c.atk,
        range = c.range,
        retaliate = c.retaliate,
        alive = true,
    }
end

-- Drop a synthetic hero on the first interior floor tile that has at least
-- `min_neighbors` cardinal-adjacent FLOOR tiles available (excluding
-- entrance/treasure). Returns the hero plus the list of those neighbor
-- positions. Lets class-behavior tests place 2+ monsters around the hero
-- regardless of where the seed put the entrance.
local function inject_hero_at_open_interior(s, class_key, min_neighbors)
    local CARDINAL = { { 0, 1 }, { 1, 0 }, { 0, -1 }, { -1, 0 } }
    for _, t in ipairs(free_tiles(s, 200)) do
        local nbrs = {}
        for _, d in ipairs(CARDINAL) do
            local nx, ny = t.x + d[1], t.y + d[2]
            if s.dungeon.grid[ny] and s.dungeon.grid[ny][nx] == dungeon.FLOOR
               and not (nx == s.dungeon.entrance.x and ny == s.dungeon.entrance.y)
               and not (nx == s.dungeon.treasure.x and ny == s.dungeon.treasure.y) then
                table.insert(nbrs, { x = nx, y = ny })
            end
        end
        if #nbrs >= min_neighbors then
            local h = make_hero(class_key, t.x, t.y)
            table.insert(s.heroes, h)
            return h, nbrs
        end
    end
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
        it("BUILD->INVASION promotes the wave; RESULT->BUILD retries", function()
            local s = state.new(1)
            assert.are.equal(state.PHASE_BUILD, s.phase)
            state.advance(s)
            assert.are.equal(state.PHASE_INVASION, s.phase)
            -- Force a treasure-stolen result, then retry.
            s.outcome = state.OUTCOME_TREASURE_STOLEN
            s.phase   = state.PHASE_RESULT
            state.advance(s)
            assert.are.equal(state.PHASE_BUILD, s.phase)
        end)

        it("is a no-op while INVASION is mid-wave", function()
            -- Wave transitions are automatic (next-wave on heroes-dead,
            -- run-over on treasure-stolen). state.advance during INVASION
            -- must NOT short-circuit either.
            local s = state.new(1)
            state.advance(s)
            assert.are.equal(state.PHASE_INVASION, s.phase)
            state.advance(s)
            assert.are.equal(state.PHASE_INVASION, s.phase)
        end)

        it("does not regenerate the dungeon on retry", function()
            local s = state.new(7)
            local original_grid = s.dungeon.grid
            state.advance(s)
            s.outcome = state.OUTCOME_TREASURE_STOLEN
            s.phase   = state.PHASE_RESULT
            state.advance(s)
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

    describe("retry (advance from result back to build)", function()
        -- Drive the run to RESULT (treasure stolen) without hand-rolling the
        -- combat: helper just slams the phase + outcome so we can exercise
        -- the retry transition in isolation.
        local function force_result(s)
            s.outcome = state.OUTCOME_TREASURE_STOLEN
            s.phase   = state.PHASE_RESULT
        end

        it("clears placed monsters", function()
            local s = state.new(7)
            local t = free_tiles(s, 1)[1]
            state.try_place_monster(s, t.x, t.y)
            state.advance(s)
            force_result(s)
            state.advance(s)
            assert.are.equal(state.PHASE_BUILD, s.phase)
            assert.are.equal(0, #s.monsters)
        end)

        it("clears placed walls and reverts the grid back to floor", function()
            local s = state.new(7)
            local t = free_tiles(s, 1)[1]
            assert.is_true(state.try_place_wall(s, t.x, t.y))
            state.advance(s)
            force_result(s)
            state.advance(s)
            assert.are.same({}, s.placed_walls)
            assert.are.equal(dungeon.FLOOR, s.dungeon.grid[t.y][t.x])
        end)

        it("restores full budget", function()
            local s = state.new(7)
            local tiles = free_tiles(s, 3)
            for _, t in ipairs(tiles) do
                state.try_place_monster(s, t.x, t.y)
            end
            state.try_place_wall(s, free_tiles(s, 4)[4].x, free_tiles(s, 4)[4].y)
            assert.is_true(state.spent_budget(s) > 0)
            state.advance(s)
            force_result(s)
            state.advance(s)
            assert.are.equal(0, state.spent_budget(s))
            assert.are.equal(state.BUDGET, state.remaining_budget(s))
        end)

        it("rewinds wave + budget_bonus to wave 1", function()
            local s = state.new(7)
            s.wave = 4
            s.budget_bonus = 15
            s.num_heroes = 6
            state.advance(s)
            force_result(s)
            state.advance(s)
            assert.are.equal(1, s.wave)
            assert.are.equal(0, s.budget_bonus)
            assert.are.equal(state.DEFAULT_NUM_HEROES, s.num_heroes)
        end)

        it("preserves the dungeon layout (same entrance + treasure + grid object)", function()
            local s = state.new(7)
            local original_grid = s.dungeon.grid
            local ex, ey = s.dungeon.entrance.x, s.dungeon.entrance.y
            local tx, ty = s.dungeon.treasure.x, s.dungeon.treasure.y
            state.advance(s)
            force_result(s)
            state.advance(s)
            assert.are.equal(original_grid, s.dungeon.grid)
            assert.are.equal(ex, s.dungeon.entrance.x)
            assert.are.equal(ey, s.dungeon.entrance.y)
            assert.are.equal(tx, s.dungeon.treasure.x)
            assert.are.equal(ty, s.dungeon.treasure.y)
        end)
    end)

    describe("lead-warrior swap", function()
        it("promotes a Warrior to slot 1 of the wave preview if rolled", function()
            -- Sample seeds and verify whenever the wave contains a Warrior,
            -- the warrior is in slot 1 of the preview.
            local found = false
            for seed = 1, 200 do
                local s = state.new(seed)
                local has_warrior = false
                for _, h in ipairs(s.wave_preview) do
                    if h.class == hero.WARRIOR then has_warrior = true; break end
                end
                if has_warrior then
                    assert.are.equal(hero.WARRIOR, s.wave_preview[1].class,
                        ("seed %d had a warrior but it was not at slot 1"):format(seed))
                    found = true
                end
            end
            assert.is_true(found, "no warrior rolled in 200 seeds — sample size issue")
        end)

        it("preserves preview order when no Warrior is present", function()
            -- Construct a non-warrior wave by directly setting wave_preview;
            -- if roll_wave is invoked again (advance), it will reroll. We
            -- instead just verify the swap is a no-op when no warrior exists.
            local s = state.new(1)
            s.wave_preview = {
                make_hero(hero.MAGE,   s.dungeon.entrance.x, s.dungeon.entrance.y),
                make_hero(hero.ARCHER, s.dungeon.entrance.x, s.dungeon.entrance.y),
                make_hero(hero.MAGE,   s.dungeon.entrance.x, s.dungeon.entrance.y),
            }
            local before = { s.wave_preview[1], s.wave_preview[2], s.wave_preview[3] }
            state.advance(s)
            assert.are.equal(before[1], s.heroes[1])
            assert.are.equal(before[2], s.hero_queue[1])
            assert.are.equal(before[3], s.hero_queue[2])
        end)
    end)

    describe("warrior retaliate", function()
        it("deals retaliate dmg to the adjacent attacker after being hit", function()
            local s = state.new(7)
            state.advance(s)
            s.heroes = {}
            s.hero_queue = {}
            local h = make_hero(hero.WARRIOR,
                s.dungeon.entrance.x, s.dungeon.entrance.y)
            table.insert(s.heroes, h)
            local nx, ny = first_floor_neighbor(s, h.x, h.y)
            local g = inject_monster(s, monster.GOBLIN, nx, ny)
            local g_hp_before = g.hp
            state.step_invasion(s)
            -- Hero attacks goblin (-h.atk), goblin (alive) attacks warrior
            -- (-g.atk), warrior retaliates (-h.retaliate).
            assert.are.equal(g_hp_before - h.atk - h.retaliate, g.hp)
        end)

        it("does NOT retaliate if the attack killed the warrior", function()
            local s = state.new(7)
            state.advance(s)
            s.heroes = {}
            -- Keep one hero in the queue so the wave doesn't auto-end on
            -- the warrior's death (which would reset the orc's HP via the
            -- between-wave heal — masking the assertion under test).
            s.hero_queue = { make_hero(hero.MAGE, 0, 0) }
            local h = make_hero(hero.WARRIOR,
                s.dungeon.entrance.x, s.dungeon.entrance.y)
            h.hp = 1
            table.insert(s.heroes, h)
            local nx, ny = first_floor_neighbor(s, h.x, h.y)
            local orc = inject_monster(s, monster.ORC, nx, ny)
            local orc_hp_before = orc.hp
            state.step_invasion(s)
            assert.is_false(h.alive)
            -- Orc took only h.atk dmg from the swing, no retaliate.
            assert.are.equal(orc_hp_before - h.atk, orc.hp)
        end)

        it("retaliate kill on an Orc still triggers the corpse death payoff", function()
            local s = state.new(7)
            state.advance(s)
            s.heroes = {}
            s.hero_queue = {}
            local h = make_hero(hero.WARRIOR,
                s.dungeon.entrance.x, s.dungeon.entrance.y)
            table.insert(s.heroes, h)
            local nx, ny = first_floor_neighbor(s, h.x, h.y)
            local orc = inject_monster(s, monster.ORC, nx, ny)
            -- Set orc HP so the warrior swing alone leaves it alive but
            -- the +1 retaliate kills it on the way out.
            orc.hp = h.atk + h.retaliate
            state.step_invasion(s)
            assert.is_false(orc.alive)
            assert.is_true(#s.corpses >= 1)
            local found = false
            for _, c in ipairs(s.corpses) do
                if c.x == nx and c.y == ny then found = true end
            end
            assert.is_true(found, "expected a corpse at the orc's tile")
        end)

        it("non-warrior heroes do not retaliate", function()
            local s = state.new(7)
            state.advance(s)
            s.heroes = {}
            s.hero_queue = {}
            local h = make_hero(hero.ARCHER,
                s.dungeon.entrance.x, s.dungeon.entrance.y)
            table.insert(s.heroes, h)
            local nx, ny = first_floor_neighbor(s, h.x, h.y)
            local g = inject_monster(s, monster.GOBLIN, nx, ny)
            local g_hp_before = g.hp
            state.step_invasion(s)
            -- Only the archer's swing damage; no retaliate.
            assert.are.equal(g_hp_before - h.atk, g.hp)
        end)
    end)

    describe("archer focus-fire", function()
        it("targets the lowest-HP monster among those in range", function()
            local s = state.new(7)
            state.advance(s)
            s.heroes = {}
            s.hero_queue = {}
            local h, nbrs = inject_hero_at_open_interior(s, hero.ARCHER, 2)
            assert.is_not_nil(h)

            local high = inject_monster(s, monster.GOBLIN, nbrs[1].x, nbrs[1].y)
            local low  = inject_monster(s, monster.GOBLIN, nbrs[2].x, nbrs[2].y)
            high.hp = 5
            low.hp  = 1

            state.step_invasion(s)
            assert.is_false(low.alive,  "archer should have killed the low-HP goblin")
            assert.are.equal(5, high.hp, "high-HP goblin should be untouched by hero swing")
        end)
    end)

    describe("mage AoE splash", function()
        it("splashes floor(atk / divisor) to each cardinal-adjacent monster", function()
            local s = state.new(7)
            state.advance(s)
            s.heroes = {}
            s.hero_queue = {}
            local h = make_hero(hero.MAGE,
                s.dungeon.entrance.x, s.dungeon.entrance.y)
            -- Pin atk so the splash math is deterministic.
            h.atk = 6
            table.insert(s.heroes, h)
            -- Main target adjacent to mage; splash victims adjacent to main.
            local mx, my = first_floor_neighbor(s, h.x, h.y)
            local main = inject_monster(s, monster.SLIME, mx, my)
            -- Place two splash candidates around the main target. Skip the
            -- mage's own tile (back-direction).
            local dirs = { { 0, 1 }, { 1, 0 }, { 0, -1 }, { -1, 0 } }
            local splash_targets = {}
            for _, d in ipairs(dirs) do
                local nx, ny = mx + d[1], my + d[2]
                if not (nx == h.x and ny == h.y)
                   and s.dungeon.grid[ny] and s.dungeon.grid[ny][nx] == dungeon.FLOOR
                   and not (nx == s.dungeon.entrance.x and ny == s.dungeon.entrance.y)
                   and not (nx == s.dungeon.treasure.x and ny == s.dungeon.treasure.y) then
                    table.insert(splash_targets,
                        inject_monster(s, monster.GOBLIN, nx, ny))
                    if #splash_targets == 2 then break end
                end
            end
            assert.is_true(#splash_targets > 0, "no splash tiles available for this seed")

            local main_hp_before   = main.hp
            local splash_hp_before = splash_targets[1].hp
            state.step_invasion(s)

            local expected_splash = math.floor(h.atk / hero.MAGE_SPLASH_DIVISOR)
            -- Main took full damage. (Slime might split if killed; if main
            -- survived, splash victims took expected_splash dmg.)
            if main.alive then
                assert.are.equal(main_hp_before - h.atk, main.hp)
            end
            for _, t in ipairs(splash_targets) do
                if t.alive then
                    assert.are.equal(splash_hp_before - expected_splash, t.hp)
                end
            end
        end)

        it("does not splash when atk is below 2 * divisor (splash floor = 0)", function()
            local s = state.new(7)
            state.advance(s)
            s.heroes = {}
            s.hero_queue = {}
            local h = make_hero(hero.MAGE,
                s.dungeon.entrance.x, s.dungeon.entrance.y)
            h.atk = 1
            table.insert(s.heroes, h)
            local mx, my = first_floor_neighbor(s, h.x, h.y)
            local main = inject_monster(s, monster.GOBLIN, mx, my)
            -- Find any cardinal neighbor of main (other than mage's tile).
            local nx, ny
            for _, d in ipairs({ { 0, 1 }, { 1, 0 }, { 0, -1 }, { -1, 0 } }) do
                local cx, cy = mx + d[1], my + d[2]
                if not (cx == h.x and cy == h.y)
                   and s.dungeon.grid[cy] and s.dungeon.grid[cy][cx] == dungeon.FLOOR
                   and not (cx == s.dungeon.entrance.x and cy == s.dungeon.entrance.y)
                   and not (cx == s.dungeon.treasure.x and cy == s.dungeon.treasure.y) then
                    nx, ny = cx, cy
                    break
                end
            end
            assert.is_not_nil(nx, "no neighbor tile available for this seed")
            local witness = inject_monster(s, monster.GOBLIN, nx, ny)
            local witness_hp = witness.hp
            state.step_invasion(s)
            assert.are.equal(witness_hp, witness.hp)
        end)

        it("snapshots splash candidates before applying — mini-slime spawned mid-attack is not splashed", function()
            local s = state.new(7)
            state.advance(s)
            s.heroes = {}
            s.hero_queue = {}
            -- Mage on an interior tile so the slime placed at a neighbor
            -- has 3 free cardinals for split spawn (not just 1 from the
            -- entrance corridor).
            local h = inject_hero_at_open_interior(s, hero.MAGE, 1)
            assert.is_not_nil(h)
            h.atk = 50
            local mx, my = first_floor_neighbor(s, h.x, h.y)
            local slime = inject_monster(s, monster.SLIME, mx, my)
            state.step_invasion(s)
            assert.is_false(slime.alive)
            local found_mini = false
            for _, m in ipairs(s.monsters) do
                if m.is_mini and m.alive then
                    found_mini = true
                    assert.are.equal(monster.MINI_SLIME.hp, m.hp,
                        "mini-slime took splash damage on its spawn tick")
                end
            end
            assert.is_true(found_mini, "expected at least one mini-slime to spawn")
        end)
    end)

    describe("orc corpse passive", function()
        it("spawns a corpse on the tile when an orc dies", function()
            local s = state.new(7)
            state.advance(s)
            local mx, my = first_floor_neighbor(s, s.heroes[1].x, s.heroes[1].y)
            local orc = inject_monster(s, monster.ORC, mx, my)
            orc.hp = 1
            state.step_invasion(s)
            assert.is_false(orc.alive)
            assert.are.equal(1, #s.corpses)
            assert.are.equal(mx, s.corpses[1].x)
            assert.are.equal(my, s.corpses[1].y)
        end)

        it("does not spawn a corpse for non-orc kills", function()
            local s = state.new(7)
            state.advance(s)
            local mx, my = first_floor_neighbor(s, s.heroes[1].x, s.heroes[1].y)
            local g = inject_monster(s, monster.GOBLIN, mx, my); g.hp = 1
            state.step_invasion(s)
            assert.is_false(g.alive)
            assert.are.equal(0, #s.corpses)
        end)

        it("expires after ORC_CORPSE_TURNS future ticks", function()
            -- Corpse blocks the tick it spawned in plus ORC_CORPSE_TURNS - 1
            -- following ticks under the snapshot rule (decrement skips the
            -- spawn tick), then is removed at the end of tick N+ORC_CORPSE_TURNS.
            local s = state.new(7)
            state.advance(s)
            s.hero_queue = {}  -- isolate this hero from queue spawns blocking it
            local mx, my = first_floor_neighbor(s, s.heroes[1].x, s.heroes[1].y)
            local orc = inject_monster(s, monster.ORC, mx, my); orc.hp = 1
            state.step_invasion(s)
            assert.are.equal(1, #s.corpses)
            for _ = 1, state.ORC_CORPSE_TURNS - 1 do
                if s.phase == state.PHASE_RESULT then break end
                state.step_invasion(s)
                assert.are.equal(1, #s.corpses)
            end
            if s.phase == state.PHASE_INVASION then
                state.step_invasion(s)
                assert.are.equal(0, #s.corpses)
            end
        end)

        it("blocks hero pathing while it persists", function()
            -- Place an orc on the natural path midpoint, kill it, and verify
            -- the next tick's hero_path detours around the corpse tile.
            local s = state.new(7)
            local original = ai.find_path(s.dungeon,
                s.dungeon.entrance.x, s.dungeon.entrance.y,
                s.dungeon.treasure.x, s.dungeon.treasure.y)
            assert.is_not_nil(original)
            state.advance(s)
            local h = s.heroes[1]
            local nx, ny = first_floor_neighbor(s, h.x, h.y)
            local orc = inject_monster(s, monster.ORC, nx, ny); orc.hp = 1
            state.step_invasion(s)
            assert.is_false(orc.alive)
            assert.are.equal(1, #s.corpses)
            local cx, cy = s.corpses[1].x, s.corpses[1].y
            local path = state.hero_path(s, h)
            if path then
                for _, p in ipairs(path) do
                    assert.is_false(p.x == cx and p.y == cy)
                end
            end
        end)

        it("clears corpses on advance back to build (retry)", function()
            local s = state.new(7)
            state.advance(s)
            local mx, my = first_floor_neighbor(s, s.heroes[1].x, s.heroes[1].y)
            local orc = inject_monster(s, monster.ORC, mx, my); orc.hp = 1
            state.step_invasion(s)
            assert.is_true(#s.corpses > 0)
            -- Force result, then back to build.
            s.outcome = state.OUTCOME_TREASURE_STOLEN
            s.phase   = state.PHASE_RESULT
            state.advance(s)
            assert.are.equal(state.PHASE_BUILD, s.phase)
            assert.are.equal(0, #s.corpses)
        end)

        it("clears corpses on reset", function()
            local s = state.new(7)
            state.advance(s)
            local mx, my = first_floor_neighbor(s, s.heroes[1].x, s.heroes[1].y)
            local orc = inject_monster(s, monster.ORC, mx, my); orc.hp = 1
            state.step_invasion(s)
            assert.is_true(#s.corpses > 0)
            state.reset(s, 99)
            assert.are.equal(0, #s.corpses)
        end)

        it("clears corpses when entering a fresh invasion", function()
            local s = state.new(7)
            -- Inject a stray corpse manually as if from a prior wave.
            s.corpses = { { x = 3, y = 3, ttl = 5 } }
            state.advance(s)
            assert.are.equal(0, #s.corpses)
        end)
    end)

    describe("slime split passive", function()
        it("spawns SLIME_SPLIT_COUNT minis at cardinal-adjacent free tiles", function()
            local s = state.new(7)
            state.advance(s)
            local h = s.heroes[1]
            local mx, my = first_floor_neighbor(s, h.x, h.y)
            local slime = inject_monster(s, monster.SLIME, mx, my); slime.hp = 1
            local before = #s.monsters
            state.step_invasion(s)
            assert.is_false(slime.alive)
            -- New minis added to monsters list.
            assert.is_true(#s.monsters > before)
            -- Up to SLIME_SPLIT_COUNT minis adjacent to the dead slime tile.
            local minis = 0
            for _, m in ipairs(s.monsters) do
                if m.is_mini and m.alive then
                    minis = minis + 1
                    assert.are.equal(1, math.abs(m.x - mx) + math.abs(m.y - my))
                end
            end
            assert.is_true(minis > 0)
            assert.is_true(minis <= state.SLIME_SPLIT_COUNT)
        end)

        it("does NOT split when a mini-slime dies (no recursive chain)", function()
            local s = state.new(7)
            state.advance(s)
            local h = s.heroes[1]
            local mx, my = first_floor_neighbor(s, h.x, h.y)
            -- Inject a mini-slime directly so the kill bypasses the parent split.
            local mini = monster.new_mini_slime(mx, my); mini.hp = 1
            table.insert(s.monsters, mini)
            local count_before = #s.monsters
            state.step_invasion(s)
            assert.is_false(mini.alive)
            -- No new monsters added past the dead mini.
            assert.are.equal(count_before, #s.monsters)
        end)

        it("does not spawn minis on entrance, treasure, or walls", function()
            -- Surround the slime with all-blocked neighbors. Easiest: place
            -- the slime adjacent to the perimeter wall AND the entrance, so
            -- two of four neighbors are wall/entrance. The other two (if
            -- floor) would still spawn — so we only assert "spawns no more
            -- than the legal directions". This test mostly guards the
            -- predicate by checking no mini lands on illegal tiles.
            local s = state.new(7)
            state.advance(s)
            local h = s.heroes[1]
            local mx, my = first_floor_neighbor(s, h.x, h.y)
            local slime = inject_monster(s, monster.SLIME, mx, my); slime.hp = 1
            state.step_invasion(s)
            for _, m in ipairs(s.monsters) do
                if m.is_mini and m.alive then
                    -- Not entrance, not treasure.
                    assert.is_false(m.x == s.dungeon.entrance.x and m.y == s.dungeon.entrance.y)
                    assert.is_false(m.x == s.dungeon.treasure.x and m.y == s.dungeon.treasure.y)
                    -- Not on a wall tile.
                    assert.are.equal(dungeon.FLOOR, s.dungeon.grid[m.y][m.x])
                end
            end
        end)

        it("does not let a freshly spawned mini-slime swing on its spawn tick", function()
            -- The hero kills the slime in tick T. Minis spawn this tick.
            -- They must not appear in the monster turn snapshot, so the
            -- hero's HP after the tick should reflect at most the parent
            -- slime's pre-death swing (already dead → 0 swings) plus any
            -- pre-existing monsters' swings (none here). With only the
            -- slime adjacent and pre-killed, hero HP must be unchanged.
            local s = state.new(7)
            state.advance(s)
            s.hero_queue = {}
            local h = s.heroes[1]
            local mx, my = first_floor_neighbor(s, h.x, h.y)
            local slime = inject_monster(s, monster.SLIME, mx, my); slime.hp = 1
            local hp_before = h.hp
            state.step_invasion(s)
            assert.are.equal(hp_before, h.hp)
        end)
    end)

    describe("goblin cluster passive", function()
        it("a clustered goblin swings for atk + 1 per adjacent goblin", function()
            local s = state.new(7)
            state.advance(s)
            s.hero_queue = {}
            local h = s.heroes[1]
            local nx, ny = first_floor_neighbor(s, h.x, h.y)
            local lead = inject_monster(s, monster.GOBLIN, nx, ny)
            -- Try to add a cluster mate at a different cardinal neighbor of the lead.
            local dirs = { { 0, 1 }, { 1, 0 }, { 0, -1 }, { -1, 0 } }
            local mate
            for _, d in ipairs(dirs) do
                local cx, cy = nx + d[1], ny + d[2]
                if not (cx == h.x and cy == h.y)
                   and not (cx == s.dungeon.entrance.x and cy == s.dungeon.entrance.y)
                   and not (cx == s.dungeon.treasure.x and cy == s.dungeon.treasure.y)
                   and s.dungeon.grid[cy] and s.dungeon.grid[cy][cx] == dungeon.FLOOR then
                    mate = inject_monster(s, monster.GOBLIN, cx, cy)
                    break
                end
            end
            assert.is_not_nil(mate, "could not place a cluster mate for this seed")

            local hp_before = h.hp
            state.step_invasion(s)
            -- One step:
            --   hero attacks lead (still alive after, hero.atk < goblin.hp)
            --   lead swings for atk + 1 (mate adjacent)
            --   mate swings (only adjacent to lead; no hero in mate's range)
            -- So hero loses lead.atk + GOBLIN_CLUSTER_BONUS HP.
            local expected_loss = monster.TYPES[monster.GOBLIN].atk + monster.GOBLIN_CLUSTER_BONUS
            assert.are.equal(hp_before - expected_loss, h.hp)
        end)
    end)

    describe("session counters", function()
        it("starts at zero best_wave/last_wave/runs", function()
            local s = state.new(1)
            assert.are.equal(0, s.session.best_wave)
            assert.are.equal(0, s.session.last_wave)
            assert.are.equal(0, s.session.runs)
        end)

        it("clearing a wave bumps state.wave but does not end the run", function()
            local s = state.new(7)
            state.advance(s)  -- BUILD -> INVASION (wave 1)
            -- Force the wave to end by killing all heroes.
            s.heroes = {}
            s.hero_queue = {}
            -- Run one tick: the end-of-wave check runs at the end of the
            -- step and triggers the between-wave transition.
            state.step_invasion(s)
            assert.are.equal(state.PHASE_BUILD, s.phase)
            assert.are.equal(2, s.wave)
            assert.are.equal(state.WAVE_BUDGET_BONUS, s.budget_bonus)
            assert.is_nil(s.outcome)
            assert.are.equal(0, s.session.runs)
        end)

        it("invasion start updates best_wave (highest wave attempted)", function()
            local s = state.new(7)
            assert.are.equal(0, s.session.best_wave)
            state.advance(s)  -- start wave 1
            assert.are.equal(1, s.session.best_wave)
            -- Simulate clearing wave 1.
            s.heroes = {}
            s.hero_queue = {}
            state.step_invasion(s)
            assert.are.equal(2, s.wave)
            assert.are.equal(1, s.session.best_wave)
            state.advance(s)  -- start wave 2
            assert.are.equal(2, s.session.best_wave)
        end)

        it("increments runs + remembers last_wave on treasure_stolen", function()
            local s = state.new(7)
            s.wave = 3
            state.advance(s)
            for _ = 1, 400 do
                if s.phase == state.PHASE_RESULT then break end
                state.step_invasion(s)
            end
            assert.are.equal(state.OUTCOME_TREASURE_STOLEN, s.outcome)
            assert.are.equal(1, s.session.runs)
            assert.are.equal(3, s.session.last_wave)
        end)

        it("preserves session counters across reset", function()
            local s = state.new(7)
            s.session.best_wave = 5
            s.session.last_wave = 3
            s.session.runs = 2
            state.reset(s, 42)
            assert.are.equal(5, s.session.best_wave)
            assert.are.equal(3, s.session.last_wave)
            assert.are.equal(2, s.session.runs)
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

        it("re-rolls a fresh preview on retry from RESULT", function()
            local s = state.new(7)
            state.advance(s)  -- build -> inv
            assert.are.equal(0, #s.wave_preview)
            s.outcome = state.OUTCOME_TREASURE_STOLEN
            s.phase   = state.PHASE_RESULT
            state.advance(s)  -- result -> build (retry)
            assert.are.equal(s.num_heroes, #s.wave_preview)
        end)

        it("re-rolls a fresh preview between waves", function()
            local s = state.new(7)
            state.advance(s)  -- enter wave 1 invasion
            assert.are.equal(0, #s.wave_preview)
            -- Force the wave to end (no heroes alive, queue empty).
            s.heroes = {}
            s.hero_queue = {}
            state.step_invasion(s)
            assert.are.equal(state.PHASE_BUILD, s.phase)
            assert.are.equal(2, s.wave)
            -- Wave 2 has +1 hero on top of DEFAULT_NUM_HEROES.
            assert.are.equal(state.DEFAULT_NUM_HEROES + 1, s.num_heroes)
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

        it("clears the hero on retry from RESULT", function()
            local s = state.new(7)
            state.advance(s)
            assert.is_not_nil(s.heroes[1])
            s.outcome = state.OUTCOME_TREASURE_STOLEN
            s.phase   = state.PHASE_RESULT
            state.advance(s)
            assert.is_nil(s.heroes[1])
        end)

        it("re-spawns a fresh hero on a second invasion", function()
            local s = state.new(7)
            state.advance(s)
            local first = s.heroes[1]
            s.outcome = state.OUTCOME_TREASURE_STOLEN
            s.phase   = state.PHASE_RESULT
            state.advance(s)
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
                -- Pin retaliate to 0 so this test stays about the hero's
                -- main swing, regardless of which class the seed promotes
                -- to lead. (Warrior retaliate would land the goblin at 0 HP.)
                s.heroes[1].retaliate = 0
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

            it("the wave advances back to BUILD when the last hero falls", function()
                -- Empty the queue to simulate a one-hero wave: only the
                -- leader is in play, so its death must end the wave (NOT
                -- the run — multi-wave: the player drops back into BUILD
                -- with a budget bonus and the next wave pre-rolled).
                local s = state.new(7)
                state.advance(s)
                local wave_before = s.wave
                local bonus_before = s.budget_bonus
                s.hero_queue = {}
                s.heroes[1].hp = 1
                local mx, my = first_floor_neighbor(s, s.heroes[1].x, s.heroes[1].y)
                inject_monster(s, monster.ORC, mx, my)

                state.step_invasion(s)

                assert.are.equal(state.PHASE_BUILD, s.phase)
                assert.are.equal(wave_before + 1, s.wave)
                assert.are.equal(bonus_before + state.WAVE_BUDGET_BONUS,
                    s.budget_bonus)
                assert.is_nil(s.outcome)
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

        describe("ranged counterplay (damage falloff + close-in)", function()
            -- Set up an archer at an interior floor tile that has a
            -- cardinal 2-tile floor sight-line. Returns the hero plus
            -- the (mid, far) tile pair so the caller can inject the
            -- target monster at `far`.
            local function archer_with_2tile_lane(s)
                local CARDINAL = { { 0, 1 }, { 1, 0 }, { 0, -1 }, { -1, 0 } }
                for _, t in ipairs(free_tiles(s, 300)) do
                    for _, d in ipairs(CARDINAL) do
                        local mid_x, mid_y = t.x + d[1], t.y + d[2]
                        local far_x, far_y = t.x + d[1] * 2, t.y + d[2] * 2
                        if s.dungeon.grid[mid_y] and s.dungeon.grid[mid_y][mid_x] == dungeon.FLOOR
                           and s.dungeon.grid[far_y] and s.dungeon.grid[far_y][far_x] == dungeon.FLOOR
                           and not (mid_x == s.dungeon.entrance.x and mid_y == s.dungeon.entrance.y)
                           and not (far_x == s.dungeon.entrance.x and far_y == s.dungeon.entrance.y)
                           and not (mid_x == s.dungeon.treasure.x and mid_y == s.dungeon.treasure.y)
                           and not (far_x == s.dungeon.treasure.x and far_y == s.dungeon.treasure.y) then
                            local h = make_hero(hero.ARCHER, t.x, t.y)
                            h.range = 2
                            table.insert(s.heroes, h)
                            return h, { x = far_x, y = far_y }
                        end
                    end
                end
            end

            it("a ranged hit from d>1 deals floor(atk/2)", function()
                local s = state.new(7)
                state.advance(s)
                s.heroes = {}
                s.hero_queue = { make_hero(hero.WARRIOR, 0, 0) }
                local h, far = archer_with_2tile_lane(s)
                assert.is_not_nil(h, "no 2-tile lane in seed 7")
                h.atk = 5
                local m = inject_monster(s, monster.GOBLIN, far.x, far.y)
                m.hp = 99
                local hp_before = m.hp
                state.step_invasion(s)
                -- Damage should be floor(5/2) = 2 at d=2, not 5 at d=1.
                assert.are.equal(hp_before - 2, m.hp)
            end)

            it("an adjacent ranged hit deals full atk", function()
                local s = state.new(7)
                state.advance(s)
                s.heroes = {}
                s.hero_queue = { make_hero(hero.WARRIOR, 0, 0) }
                local h, _ = inject_hero_at_open_interior(s, hero.ARCHER, 1)
                h.range = 2
                h.atk = 5
                local mx, my = first_floor_neighbor(s, h.x, h.y)
                local m = inject_monster(s, monster.GOBLIN, mx, my)
                m.hp = 99
                local hp_before = m.hp
                state.step_invasion(s)
                assert.are.equal(hp_before - h.atk, m.hp)
            end)

            it("a ranged attacker steps closer after firing from d>1", function()
                local s = state.new(7)
                state.advance(s)
                s.heroes = {}
                s.hero_queue = { make_hero(hero.WARRIOR, 0, 0) }
                local h, far = archer_with_2tile_lane(s)
                assert.is_not_nil(h)
                -- atk=4 → falloff 2 dmg at d=2; goblin at 50 hp survives,
                -- so close-in must trigger.
                h.atk = 4
                local hx0, hy0 = h.x, h.y
                local m = inject_monster(s, monster.GOBLIN, far.x, far.y)
                m.hp = 50
                state.step_invasion(s)
                assert.is_true(m.hp < 50, "attack did not land")
                assert.is_true(h.x ~= hx0 or h.y ~= hy0,
                    "ranged attacker should close in after firing from d>1")
                assert.are.equal(1,
                    grid.manhattan(h.x, h.y, m.x, m.y),
                    "expected the close-in to land at d=1")
            end)

            it("close-in does not fire when the swing killed the target", function()
                local s = state.new(7)
                state.advance(s)
                s.heroes = {}
                s.hero_queue = { make_hero(hero.WARRIOR, 0, 0) }
                local h, far = archer_with_2tile_lane(s)
                assert.is_not_nil(h)
                h.atk = 50
                local hx0, hy0 = h.x, h.y
                local m = inject_monster(s, monster.GOBLIN, far.x, far.y)
                m.hp = 1
                state.step_invasion(s)
                assert.is_false(m.alive, "test expects the goblin to die")
                assert.are.equal(hx0, h.x)
                assert.are.equal(hy0, h.y)
            end)
        end)

        describe("hero_path fallback when the strict route is blocked", function()
            it("returns a path even when monsters block every alternative", function()
                -- Plant monsters on every tile of the would-be route except
                -- the entrance and the treasure: the strict A* (which treats
                -- monsters as blockers) returns nil, so we exercise the
                -- approach fallback that ignores monsters.
                local s = state.new(7)
                state.advance(s)
                local h = s.heroes[1]
                local preview = state.preview_path(s)
                for _, p in ipairs(preview) do
                    if not (p.x == s.dungeon.treasure.x and p.y == s.dungeon.treasure.y)
                       and not (p.x == h.x and p.y == h.y) then
                        inject_monster(s, monster.GOBLIN, p.x, p.y)
                    end
                end
                local path = state.hero_path(s, h)
                assert.is_truthy(path,
                    "hero_path must fall back to a monster-ignoring route")
                assert.is_true(#path > 0)
            end)

            it("a hero does not stall when a monster sits 2 tiles ahead", function()
                -- Reproduces the corridor-blocker bug: with the fallback
                -- absent, a single monster blocking the only path made the
                -- hero stand still forever. With the fallback, the hero
                -- closes on the blockage, attacks adjacent the next tick,
                -- and the wave keeps moving.
                local s = state.new(7)
                state.advance(s)
                local h = s.heroes[1]
                local hx0, hy0 = h.x, h.y
                local preview = state.preview_path(s)
                -- First non-hero tile in the preview = manhattan 1 from
                -- the hero. The tile after that is manhattan 2 — out of
                -- attack range, so the hero MUST move (not attack) to
                -- close the gap.
                local plant
                for _, p in ipairs(preview) do
                    if not (p.x == hx0 and p.y == hy0)
                       and not (p.x == s.dungeon.treasure.x and p.y == s.dungeon.treasure.y) then
                        plant = p
                        break
                    end
                end
                assert.is_not_nil(plant)
                inject_monster(s, monster.GOBLIN, plant.x, plant.y)

                local hp_before = (s.monsters[#s.monsters].hp)
                state.step_invasion(s)
                -- Either the hero stepped (was 2+ away from the planted
                -- monster) OR it attacked it (was already adjacent). Both
                -- count as "didn't stall". Stalling = same position AND
                -- the planted monster untouched.
                local moved = (h.x ~= hx0 or h.y ~= hy0)
                local attacked = (s.monsters[#s.monsters].hp < hp_before)
                assert.is_true(moved or attacked,
                    "hero must move toward or attack the blockage, not stall")
            end)
        end)

        describe("drama beats (tension_pause)", function()
            it("a kill this tick sets tension_pause for the next step", function()
                local s = state.new(7)
                state.advance(s)
                -- Pin a fragile goblin adjacent to the lead so the swing
                -- this tick definitely kills something.
                local hx, hy = s.heroes[1].x, s.heroes[1].y
                local mx, my = first_floor_neighbor(s, hx, hy)
                local g = inject_monster(s, monster.GOBLIN, mx, my); g.hp = 1
                state.step_invasion(s)
                assert.is_false(g.alive)
                assert.is_true(s.tension_pause >= state.DRAMA_DEATH_PAUSE)
            end)

            it("a hero on the treasure doorstep sets tension_pause", function()
                -- Move the lead hero to a tile within DRAMA_APPROACH_DIST
                -- of the treasure manually, then run a step. No combat:
                -- we want the approach trigger isolated.
                local s = state.new(7)
                state.advance(s)
                local t = s.dungeon.treasure
                -- Find any FLOOR tile within range of the treasure.
                local target_x, target_y
                for dy = -state.DRAMA_APPROACH_DIST, state.DRAMA_APPROACH_DIST do
                    for dx = -state.DRAMA_APPROACH_DIST, state.DRAMA_APPROACH_DIST do
                        local nx, ny = t.x + dx, t.y + dy
                        if (math.abs(dx) + math.abs(dy)) > 0
                           and (math.abs(dx) + math.abs(dy)) <= state.DRAMA_APPROACH_DIST
                           and s.dungeon.grid[ny] and s.dungeon.grid[ny][nx] == dungeon.FLOOR
                           and not (nx == t.x and ny == t.y)
                           and not (nx == s.dungeon.entrance.x and ny == s.dungeon.entrance.y) then
                            target_x, target_y = nx, ny
                            break
                        end
                    end
                    if target_x then break end
                end
                assert.is_not_nil(target_x, "no eligible approach tile for seed 7")
                s.heroes[1].x = target_x
                s.heroes[1].y = target_y
                state.step_invasion(s)
                if s.phase == state.PHASE_INVASION then
                    assert.is_true(s.tension_pause >= state.DRAMA_APPROACH_PAUSE)
                end
            end)

            it("tension_pause is consumed by the next auto-step", function()
                local s = state.new(7)
                state.advance(s)
                s.tension_pause = 0.5
                -- Effective interval = STEP_INTERVAL + 0.5. dt enough only
                -- for the slow tick.
                state.update(s, state.STEP_INTERVAL + 0.5 + 0.001)
                assert.are.equal(0, s.tension_pause)
            end)
        end)
    end)

    describe("preview_path", function()
        it("returns a path from entrance to treasure during build", function()
            local s = state.new(11)
            local path = state.preview_path(s)
            assert.is_truthy(path)
            assert.is_true(#path > 0)
            local last = path[#path]
            assert.are.equal(s.dungeon.treasure.x, last.x)
            assert.are.equal(s.dungeon.treasure.y, last.y)
        end)

        it("ignores monsters (heroes fight through them at runtime)", function()
            local s = state.new(11)
            -- Plant a monster on every tile of the unobstructed path; the
            -- preview must still return a path because monsters aren't
            -- treated as blockers in the build forecast.
            for _, p in ipairs(state.preview_path(s)) do
                if not (p.x == s.dungeon.treasure.x and p.y == s.dungeon.treasure.y) then
                    table.insert(s.monsters, monster.new(monster.GOBLIN, p.x, p.y))
                end
            end
            local path = state.preview_path(s)
            assert.is_truthy(path)
        end)

        it("reroutes when a wall is placed on the current route", function()
            local s = state.new(11)
            local before = state.preview_path(s)
            assert.is_truthy(before)
            -- Place a wall on the second step of the previewed path. It
            -- should be a legal placement (path_survives_wall keeps
            -- connectivity) and the new path should differ.
            local cut = before[2]
            assert.is_true(state.try_place_wall(s, cut.x, cut.y))
            local after = state.preview_path(s)
            assert.is_truthy(after)
            local same = (#after == #before)
            if same then
                for i, p in ipairs(after) do
                    if p.x ~= before[i].x or p.y ~= before[i].y then
                        same = false
                        break
                    end
                end
            end
            assert.is_false(same)
        end)
    end)
end)
