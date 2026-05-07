-- Make sure busted resolves project modules ('src.foo') from the repo root.
package.path = "./?.lua;./?/init.lua;" .. package.path

local grid = require("src.grid")

describe("grid", function()
    describe("constants", function()
        it("matches the v1 design (20x15 of 32px tiles)", function()
            assert.are.equal(20, grid.WIDTH)
            assert.are.equal(15, grid.HEIGHT)
            assert.are.equal(32, grid.TILE)
        end)

        it("centers the grid horizontally inside the 800px window", function()
            assert.are.equal(80, grid.OFFSET_X) -- (800 - 20*32) / 2
        end)
    end)

    describe("tile_to_pixel", function()
        it("places tile (1,1) at the grid origin", function()
            local x, y = grid.tile_to_pixel(1, 1)
            assert.are.equal(grid.OFFSET_X, x)
            assert.are.equal(grid.OFFSET_Y, y)
        end)

        it("steps by TILE on each axis", function()
            local x, y = grid.tile_to_pixel(2, 3)
            assert.are.equal(grid.OFFSET_X + grid.TILE, x)
            assert.are.equal(grid.OFFSET_Y + 2 * grid.TILE, y)
        end)

        it("places the last tile at the expected pixel", function()
            local x, y = grid.tile_to_pixel(grid.WIDTH, grid.HEIGHT)
            assert.are.equal(grid.OFFSET_X + (grid.WIDTH - 1) * grid.TILE, x)
            assert.are.equal(grid.OFFSET_Y + (grid.HEIGHT - 1) * grid.TILE, y)
        end)
    end)

    describe("pixel_to_tile", function()
        it("inverts tile_to_pixel for every tile origin", function()
            for ty = 1, grid.HEIGHT do
                for tx = 1, grid.WIDTH do
                    local px, py = grid.tile_to_pixel(tx, ty)
                    local rx, ry = grid.pixel_to_tile(px, py)
                    assert.are.equal(tx, rx)
                    assert.are.equal(ty, ry)
                end
            end
        end)

        it("rounds any pixel inside a tile down to that tile", function()
            local px, py = grid.tile_to_pixel(5, 7)
            local rx, ry = grid.pixel_to_tile(px + grid.TILE - 1, py + grid.TILE - 1)
            assert.are.equal(5, rx)
            assert.are.equal(7, ry)
        end)

        it("returns nil for points outside the grid", function()
            assert.is_nil(grid.pixel_to_tile(0, 0))
            assert.is_nil(grid.pixel_to_tile(799, 599))
            assert.is_nil(grid.pixel_to_tile(grid.OFFSET_X - 1, grid.OFFSET_Y))
            assert.is_nil(grid.pixel_to_tile(grid.OFFSET_X, grid.OFFSET_Y - 1))
            assert.is_nil(grid.pixel_to_tile(
                grid.OFFSET_X + grid.WIDTH * grid.TILE,
                grid.OFFSET_Y))
        end)
    end)

    describe("in_bounds", function()
        it("accepts the four corners", function()
            assert.is_true(grid.in_bounds(1, 1))
            assert.is_true(grid.in_bounds(grid.WIDTH, 1))
            assert.is_true(grid.in_bounds(1, grid.HEIGHT))
            assert.is_true(grid.in_bounds(grid.WIDTH, grid.HEIGHT))
        end)

        it("rejects off-by-one on each side", function()
            assert.is_false(grid.in_bounds(0, 1))
            assert.is_false(grid.in_bounds(1, 0))
            assert.is_false(grid.in_bounds(grid.WIDTH + 1, grid.HEIGHT))
            assert.is_false(grid.in_bounds(grid.WIDTH, grid.HEIGHT + 1))
        end)
    end)

    describe("neighbors", function()
        it("returns 4 cardinal neighbors for an interior tile, in N/E/S/W order", function()
            local n = grid.neighbors(5, 5)
            assert.are.equal(4, #n)
            assert.are.same({ 5, 4 }, n[1]) -- N
            assert.are.same({ 6, 5 }, n[2]) -- E
            assert.are.same({ 5, 6 }, n[3]) -- S
            assert.are.same({ 4, 5 }, n[4]) -- W
        end)

        it("clips to 2 neighbors at the top-left corner", function()
            local n = grid.neighbors(1, 1)
            assert.are.equal(2, #n)
        end)

        it("clips to 2 neighbors at the bottom-right corner", function()
            local n = grid.neighbors(grid.WIDTH, grid.HEIGHT)
            assert.are.equal(2, #n)
        end)

        it("clips to 3 neighbors along an edge", function()
            assert.are.equal(3, #grid.neighbors(1, 5))
            assert.are.equal(3, #grid.neighbors(5, 1))
        end)
    end)

    describe("manhattan", function()
        it("is zero for the same point", function()
            assert.are.equal(0, grid.manhattan(3, 3, 3, 3))
        end)

        it("is the sum of axis distances", function()
            assert.are.equal(7, grid.manhattan(1, 1, 4, 5))
        end)

        it("is symmetric", function()
            assert.are.equal(
                grid.manhattan(2, 9, 7, 1),
                grid.manhattan(7, 1, 2, 9))
        end)
    end)
end)
