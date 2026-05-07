package.path = "./?.lua;./?/init.lua;" .. package.path

local input = require("src.input")
local state = require("src.state")
local monster = require("src.monster")
local grid = require("src.grid")

local function find_free_tile(s)
    for y = 2, grid.HEIGHT - 1 do
        for x = 2, grid.WIDTH - 1 do
            if not (x == s.dungeon.treasure.x and y == s.dungeon.treasure.y) then
                return x, y
            end
        end
    end
end

describe("input", function()
    describe("handle_mouse", function()
        it("places a monster on left-click over a valid tile", function()
            local s = state.new(7)
            local tx, ty = find_free_tile(s)
            local px, py = grid.tile_to_pixel(tx, ty)
            local placed = input.handle_mouse(s,
                px + grid.TILE / 2, py + grid.TILE / 2, 1)
            assert.is_true(placed)
            assert.are.equal(1, #s.monsters)
            assert.are.equal(tx, s.monsters[1].x)
            assert.are.equal(ty, s.monsters[1].y)
        end)

        it("right-click on an empty tile is a no-op", function()
            local s = state.new(7)
            local tx, ty = find_free_tile(s)
            local px, py = grid.tile_to_pixel(tx, ty)
            assert.is_false(input.handle_mouse(s, px, py, 2))
            assert.are.equal(0, #s.monsters)
        end)

        it("right-click on a placed monster removes it", function()
            local s = state.new(7)
            local tx, ty = find_free_tile(s)
            local px, py = grid.tile_to_pixel(tx, ty)
            assert.is_true(input.handle_mouse(s, px + grid.TILE / 2, py + grid.TILE / 2, 1))
            assert.are.equal(1, #s.monsters)
            assert.is_true(input.handle_mouse(s, px + grid.TILE / 2, py + grid.TILE / 2, 2))
            assert.are.equal(0, #s.monsters)
        end)

        it("ignores middle-click and other buttons", function()
            local s = state.new(7)
            local tx, ty = find_free_tile(s)
            local px, py = grid.tile_to_pixel(tx, ty)
            assert.is_false(input.handle_mouse(s, px, py, 3))
        end)

        it("ignores clicks outside the grid", function()
            local s = state.new(7)
            assert.is_false(input.handle_mouse(s, 0, 0, 1))
            assert.is_false(input.handle_mouse(s, 799, 599, 1))
            assert.are.equal(0, #s.monsters)
        end)
    end)

    describe("handle_key", function()
        it("selects monster types via 1/2/3", function()
            local s = state.new(7)
            assert.is_true(input.handle_key(s, "1"))
            assert.are.equal(monster.GOBLIN, s.selected_monster_type)
            assert.is_true(input.handle_key(s, "2"))
            assert.are.equal(monster.ORC, s.selected_monster_type)
            assert.is_true(input.handle_key(s, "3"))
            assert.are.equal(monster.SLIME, s.selected_monster_type)
        end)

        it("switches to the wall tool with 4", function()
            local s = state.new(7)
            assert.is_true(input.handle_key(s, "4"))
            assert.are.equal(state.TOOL_WALL, s.selected_tool)
        end)

        it("monster keys also restore the monster tool", function()
            local s = state.new(7)
            input.handle_key(s, "4")
            assert.are.equal(state.TOOL_WALL, s.selected_tool)
            input.handle_key(s, "2")
            assert.are.equal(state.TOOL_MONSTER, s.selected_tool)
            assert.are.equal(monster.ORC, s.selected_monster_type)
        end)

        it("ignores unrelated keys", function()
            local s = state.new(7)
            assert.is_false(input.handle_key(s, "a"))
            assert.is_false(input.handle_key(s, "9"))
            assert.is_false(input.handle_key(s, "space"))
        end)
    end)

    describe("wall tool routing", function()
        it("left-click places a wall when wall tool is active", function()
            local s = state.new(7)
            local tx, ty = find_free_tile(s)
            state.select_tool(s, state.TOOL_WALL)
            local px, py = grid.tile_to_pixel(tx, ty)
            assert.is_true(input.handle_mouse(s,
                px + grid.TILE / 2, py + grid.TILE / 2, 1))
            assert.are.equal(0, #s.monsters)
        end)

        it("right-click removes a wall when wall tool is active", function()
            local s = state.new(7)
            local tx, ty = find_free_tile(s)
            state.select_tool(s, state.TOOL_WALL)
            local px, py = grid.tile_to_pixel(tx, ty)
            input.handle_mouse(s, px + grid.TILE / 2, py + grid.TILE / 2, 1)
            assert.is_true(input.handle_mouse(s,
                px + grid.TILE / 2, py + grid.TILE / 2, 2))
        end)

        it("wall tool does not place monsters", function()
            local s = state.new(7)
            local tx, ty = find_free_tile(s)
            state.select_tool(s, state.TOOL_WALL)
            local px, py = grid.tile_to_pixel(tx, ty)
            input.handle_mouse(s, px + grid.TILE / 2, py + grid.TILE / 2, 1)
            assert.are.equal(0, #s.monsters)
        end)
    end)
end)
