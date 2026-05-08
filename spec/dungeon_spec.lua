package.path = "./?.lua;./?/init.lua;" .. package.path

local grid = require("src.grid")
local dungeon = require("src.dungeon")

describe("dungeon", function()
    describe("determinism", function()
        it("same seed -> same dungeon", function()
            local a = dungeon.generate(42)
            local b = dungeon.generate(42)
            assert.are.same(a.grid, b.grid)
            assert.are.same(a.entrance, b.entrance)
            assert.are.same(a.treasure, b.treasure)
        end)

        it("returns the seed it was called with", function()
            assert.are.equal(123, dungeon.generate(123).seed)
        end)

        it("different seeds produce variation across a sample", function()
            local seen = {}
            for s = 1, 30 do
                local d = dungeon.generate(s)
                local key = ("%d,%d:%d,%d"):format(
                    d.entrance.x, d.entrance.y,
                    d.treasure.x, d.treasure.y)
                seen[key] = true
            end
            local unique = 0
            for _ in pairs(seen) do unique = unique + 1 end
            assert.is_true(unique > 1, "expected >1 distinct layout across 30 seeds")
        end)

        it("handles edge seeds (0 and negatives) without erroring", function()
            assert.has_no.errors(function() dungeon.generate(0) end)
            assert.has_no.errors(function() dungeon.generate(-1) end)
            assert.has_no.errors(function() dungeon.generate(-999999) end)
        end)
    end)

    describe("layout (seed=7)", function()
        local d = dungeon.generate(7)

        it("matches the configured grid dimensions", function()
            assert.are.equal(grid.HEIGHT, #d.grid)
            assert.are.equal(grid.WIDTH, #d.grid[1])
        end)

        it("walls every perimeter tile except the door", function()
            for y = 1, grid.HEIGHT do
                for x = 1, grid.WIDTH do
                    local on_perim = (x == 1 or x == grid.WIDTH
                        or y == 1 or y == grid.HEIGHT)
                    if on_perim and not (x == d.entrance.x and y == d.entrance.y) then
                        assert.are.equal(dungeon.WALL, d.grid[y][x],
                            ("expected WALL at (%d,%d)"):format(x, y))
                    end
                end
            end
        end)

        it("subdivides the interior with walls + pillars (still mostly floor)", function()
            local floor_tiles, wall_tiles = 0, 0
            for y = 2, grid.HEIGHT - 1 do
                for x = 2, grid.WIDTH - 1 do
                    if d.grid[y][x] == dungeon.FLOOR then
                        floor_tiles = floor_tiles + 1
                    else
                        wall_tiles = wall_tiles + 1
                    end
                end
            end
            -- The procgen always carves at least one internal wall, so
            -- some interior tiles must be walls; but the floor must stay
            -- the dominant terrain (otherwise there's no room for the
            -- player to plant monsters).
            assert.is_true(wall_tiles > 0,
                "expected at least one interior wall tile")
            assert.is_true(floor_tiles > wall_tiles,
                "expected floor tiles to outnumber interior walls")
        end)

        it("places the entrance on a non-corner perimeter tile", function()
            local on_perim = (d.entrance.x == 1 or d.entrance.x == grid.WIDTH
                or d.entrance.y == 1 or d.entrance.y == grid.HEIGHT)
            local at_corner = ((d.entrance.x == 1 or d.entrance.x == grid.WIDTH)
                and (d.entrance.y == 1 or d.entrance.y == grid.HEIGHT))
            assert.is_true(on_perim)
            assert.is_false(at_corner)
            assert.are.equal(dungeon.FLOOR,
                d.grid[d.entrance.y][d.entrance.x])
        end)

        it("places the treasure on an interior floor tile", function()
            assert.is_true(d.treasure.x >= 2 and d.treasure.x <= grid.WIDTH - 1)
            assert.is_true(d.treasure.y >= 2 and d.treasure.y <= grid.HEIGHT - 1)
            assert.are.equal(dungeon.FLOOR,
                d.grid[d.treasure.y][d.treasure.x])
        end)

        it("keeps the treasure at least MIN_DOOR_TREASURE_DIST from the door", function()
            local dist = grid.manhattan(
                d.entrance.x, d.entrance.y,
                d.treasure.x, d.treasure.y)
            assert.is_true(dist >= dungeon.MIN_DOOR_TREASURE_DIST,
                ("expected dist >= %d, got %d")
                    :format(dungeon.MIN_DOOR_TREASURE_DIST, dist))
        end)
    end)

    describe("invariants across many seeds", function()
        local ai = require("src.ai")
        for _, seed in ipairs({ 1, 7, 42, 100, 999, 12345, 2147483646 }) do
            it("seed " .. seed .. " produces a valid dungeon", function()
                local d = dungeon.generate(seed)
                assert.are.equal(grid.HEIGHT, #d.grid)
                assert.are.equal(dungeon.FLOOR,
                    d.grid[d.entrance.y][d.entrance.x])
                assert.are.equal(dungeon.FLOOR,
                    d.grid[d.treasure.y][d.treasure.x])
                assert.is_true(
                    d.entrance.x ~= d.treasure.x or d.entrance.y ~= d.treasure.y,
                    "entrance and treasure must differ")
                local dist = grid.manhattan(
                    d.entrance.x, d.entrance.y,
                    d.treasure.x, d.treasure.y)
                assert.is_true(dist >= dungeon.MIN_DOOR_TREASURE_DIST)
                -- Connectivity: the procgen must always leave a path from
                -- the entrance to the treasure, regardless of how many
                -- internal walls/pillars it carved.
                local path = ai.find_path(d,
                    d.entrance.x, d.entrance.y,
                    d.treasure.x, d.treasure.y)
                assert.is_truthy(path,
                    "expected entrance->treasure to remain reachable")
            end)
        end
    end)
end)
