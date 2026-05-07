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
end)
