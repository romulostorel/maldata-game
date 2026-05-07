package.path = "./?.lua;./?/init.lua;" .. package.path

local state = require("src.state")
local dungeon = require("src.dungeon")
local monster = require("src.monster")
local grid = require("src.grid")

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
            assert.is_nil(s.hero)
            assert.is_nil(s.outcome)
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

        it("clears the hero and outcome", function()
            local s = state.new(7)
            state.advance(s) -- spawns hero
            s.outcome = state.OUTCOME_TREASURE_STOLEN
            state.reset(s, 42)
            assert.is_nil(s.hero)
            assert.is_nil(s.outcome)
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

        it("caps placement at MAX_MONSTERS", function()
            local s = state.new(7)
            local tiles = free_tiles(s, state.MAX_MONSTERS + 1)
            for i = 1, state.MAX_MONSTERS do
                assert.is_true(state.try_place_monster(s, tiles[i].x, tiles[i].y))
            end
            local extra = tiles[state.MAX_MONSTERS + 1]
            assert.is_false(state.try_place_monster(s, extra.x, extra.y))
            assert.are.equal(state.MAX_MONSTERS, #s.monsters)
        end)

        it("rejects placement outside the BUILD phase", function()
            local s = state.new(7)
            local t = free_tiles(s, 1)[1]
            state.advance(s) -- now invasion
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

    describe("invasion", function()
        it("spawns a hero at the entrance when entering invasion", function()
            local s = state.new(7)
            assert.is_nil(s.hero)
            state.advance(s)
            assert.is_not_nil(s.hero)
            assert.are.equal(s.dungeon.entrance.x, s.hero.x)
            assert.are.equal(s.dungeon.entrance.y, s.hero.y)
        end)

        it("seeds the run rng so hero gen is deterministic per seed", function()
            local a = state.new(7)
            state.advance(a)
            local b = state.new(7)
            state.advance(b)
            assert.are.equal(a.hero.class, b.hero.class)
            assert.are.equal(a.hero.hp, b.hero.hp)
            assert.are.equal(a.hero.atk, b.hero.atk)
        end)

        it("clears the hero on advance back to build", function()
            local s = state.new(7)
            state.advance(s)
            state.advance(s)
            assert.is_not_nil(s.hero)
            state.advance(s)
            assert.is_nil(s.hero)
        end)

        it("re-spawns a fresh hero on a second invasion", function()
            local s = state.new(7)
            state.advance(s)
            local first = s.hero
            state.advance(s); state.advance(s)
            state.advance(s)
            assert.is_not_nil(s.hero)
            assert.are.equal(s.dungeon.entrance.x, s.hero.x)
            assert.are.equal(s.dungeon.entrance.y, s.hero.y)
            assert.are.equal(s.hero.max_hp, s.hero.hp)
            assert.are_not.equal(first, s.hero)
        end)

        describe("step_invasion (movement)", function()
            it("moves the hero one tile closer to the treasure when no monster is in range", function()
                local s = state.new(7)
                state.advance(s)
                local d_before = grid.manhattan(
                    s.hero.x, s.hero.y,
                    s.dungeon.treasure.x, s.dungeon.treasure.y)
                state.step_invasion(s)
                local d_after = grid.manhattan(
                    s.hero.x, s.hero.y,
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
                assert.are.equal(s.dungeon.treasure.x, s.hero.x)
                assert.are.equal(s.dungeon.treasure.y, s.hero.y)
            end)

            it("no-ops outside the INVASION phase", function()
                local s = state.new(7)
                state.step_invasion(s)
                assert.is_nil(s.hero)
                assert.are.equal(state.PHASE_BUILD, s.phase)
            end)
        end)

        describe("step_invasion (combat)", function()
            it("hero attacks an adjacent monster instead of moving", function()
                local s = state.new(7)
                state.advance(s)
                local hx, hy = s.hero.x, s.hero.y
                local mx, my = first_floor_neighbor(s, hx, hy)
                local m = inject_monster(s, monster.GOBLIN, mx, my)
                local m_hp_before = m.hp

                state.step_invasion(s)

                assert.are.equal(hx, s.hero.x)
                assert.are.equal(hy, s.hero.y)
                assert.are.equal(m_hp_before - s.hero.atk, m.hp)
            end)

            it("monster in range attacks the hero on the same turn", function()
                local s = state.new(7)
                state.advance(s)
                local mx, my = first_floor_neighbor(s, s.hero.x, s.hero.y)
                inject_monster(s, monster.ORC, mx, my)
                local hp_before = s.hero.hp

                state.step_invasion(s)

                assert.is_true(s.hero.hp < hp_before)
            end)

            it("hero death transitions to RESULT with hero_dead", function()
                local s = state.new(7)
                state.advance(s)
                s.hero.hp = 1
                local mx, my = first_floor_neighbor(s, s.hero.x, s.hero.y)
                -- Orc atk=4 will down a 1-hp hero even after the hero hits back.
                inject_monster(s, monster.ORC, mx, my)

                state.step_invasion(s)

                assert.are.equal(state.PHASE_RESULT, s.phase)
                assert.are.equal(state.OUTCOME_HERO_DEAD, s.outcome)
                assert.is_false(s.hero.alive)
            end)

            it("once a monster dies, hero proceeds to move on the following turn", function()
                local s = state.new(7)
                state.advance(s)
                local hx, hy = s.hero.x, s.hero.y
                local mx, my = first_floor_neighbor(s, hx, hy)
                local m = inject_monster(s, monster.GOBLIN, mx, my)
                m.hp = 1 -- hero one-shots the goblin

                state.step_invasion(s) -- hero kills the goblin
                assert.is_false(m.alive)
                -- hero stayed put and survived (dead monster cannot strike back)
                assert.are.equal(hx, s.hero.x)
                assert.are.equal(hy, s.hero.y)
                assert.is_true(s.hero.alive)

                state.step_invasion(s) -- now hero should advance
                assert.is_true(s.hero.x ~= hx or s.hero.y ~= hy)
            end)

            it("ranged hero stays out of melee monster range", function()
                local s = state.new(7)
                state.advance(s)
                -- Force an archer (range 3) regardless of seed roll.
                s.hero.range = 3
                s.hero.atk = 1 -- avoid one-shotting and hide the test behind random rolls
                local hx, hy = s.hero.x, s.hero.y
                -- Place a goblin (range 1) two tiles away on a floor tile.
                local target_x, target_y
                if first_floor_neighbor(s, hx, hy) then
                    local nx, ny = first_floor_neighbor(s, hx, hy)
                    -- step one further in the same direction
                    local dx, dy = nx - hx, ny - hy
                    target_x, target_y = nx + dx, ny + dy
                end
                if target_x and s.dungeon.grid[target_y]
                   and s.dungeon.grid[target_y][target_x] == dungeon.FLOOR then
                    local m = inject_monster(s, monster.GOBLIN, target_x, target_y)
                    local hp_before = s.hero.hp
                    state.step_invasion(s)
                    -- hero attacked the goblin but goblin (range 1, 2 tiles away) cannot retaliate.
                    assert.is_true(m.hp < m.max_hp)
                    assert.are.equal(hp_before, s.hero.hp)
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
                    grid.manhattan(s.hero.x, s.hero.y,
                        s.dungeon.treasure.x, s.dungeon.treasure.y),
                    #path)
            end)
        end)
    end)
end)
