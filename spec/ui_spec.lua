package.path = "./?.lua;./?/init.lua;" .. package.path

local ui = require("src.ui")

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
end)
