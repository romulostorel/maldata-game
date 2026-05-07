-- A* pathfinding on the dungeon grid. 4-connected, unit-cost movement,
-- Manhattan heuristic (admissible for cardinal-only motion). Pure logic.
--
-- find_path(dungeon, sx, sy, gx, gy[, is_blocked]) returns an array of
-- {x, y} tiles from start (excluded) to goal (included), or nil on no path.
-- is_blocked(x, y) -> bool marks extra impassable tiles (e.g. monsters);
-- walls are always impassable.

local grid = require("src.grid")
local dungeon = require("src.dungeon")

local M = {}

local DIRS = { { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } }

-- Pack (x, y) into a single integer key. Safe while x,y < 100000.
local KEY_MULT = 100000

local function key(x, y)
    return x * KEY_MULT + y
end

local function unkey(k)
    return math.floor(k / KEY_MULT), k % KEY_MULT
end

local function reconstruct(came_from, current_k)
    local path = {}
    while came_from[current_k] do
        local x, y = unkey(current_k)
        table.insert(path, 1, { x = x, y = y })
        current_k = came_from[current_k]
    end
    return path
end

function M.find_path(dungeon_data, sx, sy, gx, gy, is_blocked)
    is_blocked = is_blocked or function() return false end

    local h = #dungeon_data.grid
    local w = #dungeon_data.grid[1]

    local function passable(x, y)
        if x < 1 or x > w or y < 1 or y > h then return false end
        if dungeon_data.grid[y][x] == dungeon.WALL then return false end
        if is_blocked(x, y) then return false end
        return true
    end

    local start_k = key(sx, sy)
    local goal_k  = key(gx, gy)

    local open      = { [start_k] = true }
    local came_from = {}
    local g_score   = { [start_k] = 0 }
    local f_score   = { [start_k] = grid.manhattan(sx, sy, gx, gy) }

    while next(open) do
        -- Pop the open node with the lowest f. Linear scan; the grid is
        -- tiny (<= a few hundred tiles) so a heap is unnecessary overhead.
        local current_k, current_f = nil, math.huge
        for k in pairs(open) do
            if f_score[k] < current_f then
                current_k = k
                current_f = f_score[k]
            end
        end

        if current_k == goal_k then
            return reconstruct(came_from, current_k)
        end

        open[current_k] = nil
        local cx, cy = unkey(current_k)

        for i = 1, #DIRS do
            local nx, ny = cx + DIRS[i][1], cy + DIRS[i][2]
            -- Allow the goal tile even if marked blocked, so callers can
            -- pathfind onto an obstructed objective without special-casing.
            if passable(nx, ny) or (nx == gx and ny == gy) then
                local nk = key(nx, ny)
                local tentative_g = g_score[current_k] + 1
                if not g_score[nk] or tentative_g < g_score[nk] then
                    came_from[nk] = current_k
                    g_score[nk]   = tentative_g
                    f_score[nk]   = tentative_g + grid.manhattan(nx, ny, gx, gy)
                    open[nk]      = true
                end
            end
        end
    end

    return nil
end

return M
