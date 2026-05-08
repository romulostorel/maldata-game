-- Procedural dungeon generator: deterministic given a seed.
-- v1.5 layout: rectangular room with walled perimeter, plus 1-3 internal
-- wall segments (each with a 1-tile gap) that subdivide the floor into
-- smaller rooms / corridors, plus a handful of single-tile pillars to
-- break up open areas. Connectivity is preserved by construction: every
-- wall and pillar is only kept if A* still finds a path from the door to
-- the treasure after it is placed.
-- Pure logic — no LÖVE calls, runs headless under busted.

local grid = require("src.grid")
local rand = require("src.rand")

local M = {}

M.FLOOR = 0
M.WALL = 1
M.MIN_DOOR_TREASURE_DIST = 6

-- Interior wall segments: how many to attempt and the spacing rules. Two
-- to three lines is the sweet spot on a 20×15 grid — fewer feels empty,
-- more chops the space into corridors so narrow there's no room to place
-- monsters around them. Each segment has exactly one gap (door) on its
-- length so the regions on either side stay reachable.
M.WALL_LINES_MIN = 2
M.WALL_LINES_MAX = 3

-- Free-standing pillars sprinkled on remaining floor: visual texture +
-- extra micro-decisions for path-routing. Range chosen so the dungeon
-- still has plenty of open tiles for monster placement.
M.PILLARS_MIN = 2
M.PILLARS_MAX = 5

-- Spacing between two parallel internal walls. Walls closer than this
-- create dead-2-tile corridors with no room to plant a monster between.
local PARALLEL_SPACING = 3

local function build_room(W, H)
    local g = {}
    for y = 1, H do
        g[y] = {}
        for x = 1, W do
            local on_border = (x == 1 or x == W or y == 1 or y == H)
            g[y][x] = on_border and M.WALL or M.FLOOR
        end
    end
    return g
end

-- Random non-corner perimeter tile.
local function random_door(rng, W, H)
    local edge = rng(4) -- 1=top 2=right 3=bottom 4=left
    if edge == 1 then return rng(W - 2) + 1, 1 end
    if edge == 2 then return W, rng(H - 2) + 1 end
    if edge == 3 then return rng(W - 2) + 1, H end
    return 1, rng(H - 2) + 1
end

local function random_interior(rng, W, H)
    return rng(W - 2) + 1, rng(H - 2) + 1
end

-- The cell immediately inside the door, so we can avoid placing a wall
-- right where the heroes are about to step from. Without this, an internal
-- wall could sit one tile inside the door and force the entire wave to
-- queue on the threshold while pathing around it — visually broken even
-- if technically connected.
local function door_inner(W, H, dx, dy)
    if dy == 1 then return dx, 2 end
    if dy == H then return dx, H - 1 end
    if dx == 1 then return 2, dy end
    return W - 1, dy
end

-- BFS connectivity probe used by every "attempt to add an obstacle" step.
-- Local instead of pulling ai.find_path so dungeon.lua stays independent
-- of the pathfinding module (and avoids the require cycle: ai already
-- pulls dungeon for its WALL constant).
local BFS_DIRS = { { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } }
local function path_exists(g, sx, sy, gx, gy)
    local H = #g
    local W = #g[1]
    local visited = {}
    local function key(x, y) return y * (W + 1) + x end
    local stack = { { sx, sy } }
    visited[key(sx, sy)] = true
    while #stack > 0 do
        local node = table.remove(stack)
        local cx, cy = node[1], node[2]
        if cx == gx and cy == gy then return true end
        for _, d in ipairs(BFS_DIRS) do
            local nx, ny = cx + d[1], cy + d[2]
            if nx >= 1 and nx <= W and ny >= 1 and ny <= H
               and not visited[key(nx, ny)]
               and (g[ny][nx] ~= M.WALL or (nx == gx and ny == gy)) then
                visited[key(nx, ny)] = true
                table.insert(stack, { nx, ny })
            end
        end
    end
    return false
end

-- Pick a candidate row/col for an internal wall, far enough from existing
-- parallel walls. Returns nil if no candidate fits — the caller then
-- skips this attempt rather than crowding the layout.
local function pick_axis(rng, range_lo, range_hi, used)
    for _ = 1, 8 do
        local v = range_lo + rng(range_hi - range_lo + 1) - 1
        local ok = true
        for _, u in ipairs(used) do
            if math.abs(v - u) < PARALLEL_SPACING then ok = false; break end
        end
        if ok then return v end
    end
    return nil
end

-- Apply a horizontal wall at row y with a 1-tile gap at column gap_x.
-- Returns the list of cells changed so the caller can revert if the
-- placement breaks connectivity.
local function apply_h_wall(g, W, y, gap_x)
    local touched = {}
    for x = 2, W - 1 do
        if x ~= gap_x and g[y][x] ~= M.WALL then
            table.insert(touched, { x = x, y = y, prev = g[y][x] })
            g[y][x] = M.WALL
        end
    end
    return touched
end

local function apply_v_wall(g, H, x, gap_y)
    local touched = {}
    for y = 2, H - 1 do
        if y ~= gap_y and g[y][x] ~= M.WALL then
            table.insert(touched, { x = x, y = y, prev = g[y][x] })
            g[y][x] = M.WALL
        end
    end
    return touched
end

local function revert(g, touched)
    for _, c in ipairs(touched) do g[c.y][c.x] = c.prev end
end

-- Carve up to WALL_LINES_MAX internal wall segments. Each must keep the
-- door↔treasure path intact AND must not seal the door's inner tile off
-- from its neighborhood (which would force the whole wave to bottleneck
-- on the threshold even if technically reachable through a long detour).
local function carve_walls(rng, g, W, H, entrance, treasure)
    local target = M.WALL_LINES_MIN
        + rng(M.WALL_LINES_MAX - M.WALL_LINES_MIN + 1) - 1
    local h_used, v_used = {}, {}
    local inner_x, inner_y = door_inner(W, H, entrance.x, entrance.y)

    for _ = 1, target do
        local orient = rng(2)  -- 1 = horizontal, 2 = vertical
        local touched
        if orient == 1 then
            local y = pick_axis(rng, 3, H - 2, h_used)
            if y then
                local gap_x = 2 + rng(W - 2) - 1  -- 2..W-1
                touched = apply_h_wall(g, W, y, gap_x)
                if path_exists(g, entrance.x, entrance.y, treasure.x, treasure.y)
                   and g[inner_y][inner_x] == M.FLOOR then
                    table.insert(h_used, y)
                else
                    revert(g, touched)
                end
            end
        else
            local x = pick_axis(rng, 3, W - 2, v_used)
            if x then
                local gap_y = 2 + rng(H - 2) - 1
                touched = apply_v_wall(g, H, x, gap_y)
                if path_exists(g, entrance.x, entrance.y, treasure.x, treasure.y)
                   and g[inner_y][inner_x] == M.FLOOR then
                    table.insert(v_used, x)
                else
                    revert(g, touched)
                end
            end
        end
    end
end

-- Sprinkle pillars: single-tile walls on currently-floor cells. Each
-- candidate must (a) not sit on entrance/treasure or their immediate
-- neighbors, (b) not be a door's inner tile, (c) preserve connectivity.
-- Bounded retries — if the dungeon is dense, we just place fewer.
local function carve_pillars(rng, g, W, H, entrance, treasure)
    local target = M.PILLARS_MIN
        + rng(M.PILLARS_MAX - M.PILLARS_MIN + 1) - 1
    local placed = 0
    local attempts = 0
    local inner_x, inner_y = door_inner(W, H, entrance.x, entrance.y)

    while placed < target and attempts < 40 do
        attempts = attempts + 1
        local x, y = random_interior(rng, W, H)
        local valid = g[y][x] == M.FLOOR
            and not (x == entrance.x and y == entrance.y)
            and not (x == treasure.x and y == treasure.y)
            and not (x == inner_x and y == inner_y)
            and grid.manhattan(x, y, treasure.x, treasure.y) >= 2
        if valid then
            g[y][x] = M.WALL
            if path_exists(g, entrance.x, entrance.y, treasure.x, treasure.y) then
                placed = placed + 1
            else
                g[y][x] = M.FLOOR
            end
        end
    end
end

function M.generate(seed)
    local rng = rand.new(seed)
    local W, H = grid.WIDTH, grid.HEIGHT

    local g = build_room(W, H)

    local dx, dy = random_door(rng, W, H)
    g[dy][dx] = M.FLOOR -- carve the door

    local tx, ty = random_interior(rng, W, H)
    for _ = 1, 100 do
        if grid.manhattan(dx, dy, tx, ty) >= M.MIN_DOOR_TREASURE_DIST then
            break
        end
        tx, ty = random_interior(rng, W, H)
    end

    local entrance = { x = dx, y = dy }
    local treasure = { x = tx, y = ty }

    carve_walls(rng, g, W, H, entrance, treasure)
    carve_pillars(rng, g, W, H, entrance, treasure)

    return {
        seed = seed,
        grid = g,
        entrance = entrance,
        treasure = treasure,
    }
end

return M
