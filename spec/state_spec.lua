package.path = "./?.lua;./?/init.lua;" .. package.path

local state = require("src.state")
local dungeon = require("src.dungeon")

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
            -- Same table reference: advance() must never touch the dungeon.
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
    end)
end)
