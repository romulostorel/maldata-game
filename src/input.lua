-- Mouse + keyboard routing for the build phase: maps left-click to tile
-- placement, right-click to undo (remove a placed monster), and number
-- keys to monster type selection. Routing only — placement and validation
-- live in state.lua.

local grid = require("src.grid")
local monster = require("src.monster")
local state = require("src.state")

local M = {}

local KEY_TO_TYPE = {
    ["1"] = monster.GOBLIN,
    ["2"] = monster.ORC,
    ["3"] = monster.SLIME,
}

function M.handle_mouse(game, px, py, button)
    local tx, ty = grid.pixel_to_tile(px, py)
    if not tx then return false end
    if button == 1 then
        return state.try_place_monster(game, tx, ty)
    elseif button == 2 then
        return state.try_remove_monster(game, tx, ty)
    end
    return false
end

function M.handle_key(game, key)
    local type_key = KEY_TO_TYPE[key]
    if not type_key then return false end
    return state.select_monster_type(game, type_key)
end

return M
