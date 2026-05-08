package.path = "./?.lua;./?/init.lua;" .. package.path

local ui      = require("src.ui")
local state   = require("src.state")
local monster = require("src.monster")

-- The two button rects are private to ui.lua; these tests pin the geometry
-- by hitting known points: RETRY at (180,380,200,50), NEW_DUNGEON at
-- (420,380,200,50) — both 50 px tall, 200 px wide, separated by a 40 px gap.
describe("ui", function()
    describe("is_retry_clicked", function()
        it("returns true for clicks inside the retry button", function()
            assert.is_true(ui.is_retry_clicked(280, 405)) -- center
            assert.is_true(ui.is_retry_clicked(180, 380)) -- top-left corner
            assert.is_true(ui.is_retry_clicked(380, 430)) -- bottom-right corner
        end)

        it("returns false for clicks outside the retry button", function()
            assert.is_false(ui.is_retry_clicked(0, 0))
            assert.is_false(ui.is_retry_clicked(179, 405)) -- 1px left
            assert.is_false(ui.is_retry_clicked(381, 405)) -- 1px right (gap)
            assert.is_false(ui.is_retry_clicked(280, 379)) -- 1px above
            assert.is_false(ui.is_retry_clicked(280, 431)) -- 1px below
        end)
    end)

    describe("is_new_dungeon_clicked", function()
        it("returns true for clicks inside the new dungeon button", function()
            assert.is_true(ui.is_new_dungeon_clicked(520, 405)) -- center
            assert.is_true(ui.is_new_dungeon_clicked(420, 380)) -- top-left corner
            assert.is_true(ui.is_new_dungeon_clicked(620, 430)) -- bottom-right corner
        end)

        it("returns false for clicks outside the new dungeon button", function()
            assert.is_false(ui.is_new_dungeon_clicked(0, 0))
            assert.is_false(ui.is_new_dungeon_clicked(419, 405)) -- 1px left (gap)
            assert.is_false(ui.is_new_dungeon_clicked(621, 405)) -- 1px right
            assert.is_false(ui.is_new_dungeon_clicked(520, 379)) -- 1px above
            assert.is_false(ui.is_new_dungeon_clicked(520, 431)) -- 1px below
        end)

        it("buttons do not overlap", function()
            -- A point in the gap (between x=380 and x=420) hits neither.
            assert.is_false(ui.is_retry_clicked(400, 405))
            assert.is_false(ui.is_new_dungeon_clicked(400, 405))
        end)
    end)

    describe("tool_at", function()
        -- Toolbar geometry is private (TOOLBAR_X=8, TOOLBAR_Y=22, CELL=28,
        -- TOOL_PAIR_W = 28+4+12+18 = 62). Cell i sits at x = 8 + (i-1)*62
        -- and spans 28 px horizontally, y=22..50.

        it("returns goblin for clicks on the first cell", function()
            local t = ui.tool_at(20, 36) -- center of first cell
            assert.is_not_nil(t)
            assert.are.equal(state.TOOL_MONSTER, t.kind)
            assert.are.equal(monster.GOBLIN, t.type_key)
        end)

        it("returns orc for clicks on the second cell", function()
            local t = ui.tool_at(8 + 62 + 14, 36) -- second cell center
            assert.is_not_nil(t)
            assert.are.equal(monster.ORC, t.type_key)
        end)

        it("returns slime for clicks on the third cell", function()
            local t = ui.tool_at(8 + 62 * 2 + 14, 36)
            assert.is_not_nil(t)
            assert.are.equal(monster.SLIME, t.type_key)
        end)

        it("returns the wall tool for clicks on the fourth cell", function()
            local t = ui.tool_at(8 + 62 * 3 + 14, 36)
            assert.is_not_nil(t)
            assert.are.equal(state.TOOL_WALL, t.kind)
        end)

        it("returns nil for clicks above or below the toolbar", function()
            assert.is_nil(ui.tool_at(20, 10)) -- above
            assert.is_nil(ui.tool_at(20, 60)) -- below
        end)

        it("returns nil for clicks in the gaps between cells", function()
            -- Right edge of first cell is x=36; second cell starts at x=70.
            -- Anything in (36, 70) horizontal lands in the gap.
            assert.is_nil(ui.tool_at(50, 36))
        end)

        it("returns nil for clicks past the last cell", function()
            -- 4th cell ends at x = 8 + 62*3 + 28 = 222. Far right is empty.
            assert.is_nil(ui.tool_at(500, 36))
        end)
    end)
end)
