package.path = "./?.lua;./?/init.lua;" .. package.path

local ui = require("src.ui")

-- The button rect is private to ui.lua; these tests pin the geometry by
-- hitting known points relative to its declared location (300,380,200,50).
describe("ui", function()
    describe("is_restart_clicked", function()
        it("returns true for clicks inside the button", function()
            assert.is_true(ui.is_restart_clicked(400, 405)) -- center
            assert.is_true(ui.is_restart_clicked(300, 380)) -- top-left corner
            assert.is_true(ui.is_restart_clicked(500, 430)) -- bottom-right corner
        end)

        it("returns false for clicks outside the button", function()
            assert.is_false(ui.is_restart_clicked(0, 0))
            assert.is_false(ui.is_restart_clicked(299, 405)) -- 1px left
            assert.is_false(ui.is_restart_clicked(501, 405)) -- 1px right
            assert.is_false(ui.is_restart_clicked(400, 379)) -- 1px above
            assert.is_false(ui.is_restart_clicked(400, 431)) -- 1px below
        end)
    end)
end)
