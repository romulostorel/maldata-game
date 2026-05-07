package.path = "./?.lua;./?/init.lua;" .. package.path

local ai = require("src.ai")
local dungeon = require("src.dungeon")
local grid = require("src.grid")

-- Build a tiny synthetic dungeon from string rows: '#' wall, '.' floor.
-- Useful for layouts that the v1 generator can't produce (e.g. obstacles
-- inside an empty room, fully blocked corridors).
local function dungeon_from(rows)
    local g = {}
    for y, row in ipairs(rows) do
        g[y] = {}
        for x = 1, #row do
            local c = row:sub(x, x)
            g[y][x] = (c == "#") and dungeon.WALL or dungeon.FLOOR
        end
    end
    return { grid = g }
end

describe("ai.find_path", function()
    it("returns an empty path when start equals goal", function()
        local d = dungeon_from({
            "#####",
            "#...#",
            "#####",
        })
        local path = ai.find_path(d, 3, 2, 3, 2)
        assert.are.equal(0, #path)
    end)

    it("returns a Manhattan-length path in an empty room", function()
        local d = dungeon_from({
            "######",
            "#....#",
            "#....#",
            "#....#",
            "######",
        })
        local path = ai.find_path(d, 2, 2, 5, 4)
        local expected = grid.manhattan(2, 2, 5, 4)
        assert.is_not_nil(path)
        assert.are.equal(expected, #path)
        -- last step must land on the goal
        assert.are.equal(5, path[#path].x)
        assert.are.equal(4, path[#path].y)
    end)

    it("routes around an interior wall", function()
        local d = dungeon_from({
            "#######",
            "#..#..#",
            "#..#..#",
            "#.....#",
            "#######",
        })
        local path = ai.find_path(d, 2, 2, 6, 2)
        assert.is_not_nil(path)
        -- The optimal detour goes down to row 4 and back up: length > Manhattan.
        assert.is_true(#path > grid.manhattan(2, 2, 6, 2))
    end)

    it("returns nil when goal is unreachable", function()
        local d = dungeon_from({
            "#####",
            "#.#.#",
            "#####",
        })
        assert.is_nil(ai.find_path(d, 2, 2, 4, 2))
    end)

    it("treats is_blocked tiles as impassable", function()
        local d = dungeon_from({
            "#####",
            "#...#",
            "#####",
        })
        -- Block the only path at (3,2): goal (4,2) becomes unreachable.
        local function blocked(x, y) return x == 3 and y == 2 end
        assert.is_nil(ai.find_path(d, 2, 2, 4, 2, blocked))
    end)

    it("allows the goal tile even if is_blocked says so", function()
        local d = dungeon_from({
            "#####",
            "#...#",
            "#####",
        })
        local function blocked(x, y) return x == 4 and y == 2 end
        local path = ai.find_path(d, 2, 2, 4, 2, blocked)
        assert.is_not_nil(path)
        assert.are.equal(2, #path)
    end)

    it("works on the real v1 dungeon (entrance to treasure)", function()
        local d = dungeon.generate(7)
        local path = ai.find_path(d,
            d.entrance.x, d.entrance.y,
            d.treasure.x, d.treasure.y)
        assert.is_not_nil(path)
        -- v1 layout is a single empty room; path is exactly Manhattan.
        local expected = grid.manhattan(
            d.entrance.x, d.entrance.y,
            d.treasure.x, d.treasure.y)
        assert.are.equal(expected, #path)
    end)
end)
