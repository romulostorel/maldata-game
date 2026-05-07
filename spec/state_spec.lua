package.path = "./?.lua;./?/init.lua;" .. package.path

local state = require("src.state")
local dungeon = require("src.dungeon")
local monster = require("src.monster")
local grid = require("src.grid")

-- Returns the first n interior tiles (2..W-1, 2..H-1) that aren't the
-- treasure for the given state. Stable per-seed so tests are deterministic.
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
            state.advance(s) -- INVASION
            state.advance(s) -- RESULT (hero retained for the result screen)
            assert.is_not_nil(s.hero)
            state.advance(s) -- BUILD
            assert.is_nil(s.hero)
        end)

        it("re-spawns a fresh hero on a second invasion", function()
            local s = state.new(7)
            state.advance(s) -- spawn 1
            local first = s.hero
            state.advance(s); state.advance(s) -- result -> build (clears hero)
            state.advance(s) -- spawn 2
            assert.is_not_nil(s.hero)
            -- Same seed and the rng has advanced, so stats may differ; but the
            -- hero must be back at the entrance with full HP.
            assert.are.equal(s.dungeon.entrance.x, s.hero.x)
            assert.are.equal(s.dungeon.entrance.y, s.hero.y)
            assert.are.equal(s.hero.max_hp, s.hero.hp)
            -- Same table identity must NOT be reused (fresh entity).
            assert.are_not.equal(first, s.hero)
        end)

        describe("step_invasion", function()
            it("moves the hero one tile closer to the treasure", function()
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
                state.step_invasion(s) -- in BUILD
                assert.is_nil(s.hero)
                assert.are.equal(state.PHASE_BUILD, s.phase)
            end)
        end)

        describe("hero_path", function()
            it("returns nil when there is no hero", function()
                local s = state.new(7)
                assert.is_nil(state.hero_path(s))
            end)

            it("returns a path of Manhattan length on an empty room", function()
                local s = state.new(7)
                state.advance(s) -- spawn at entrance
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
