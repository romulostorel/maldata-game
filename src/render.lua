-- Rendering: draws the dungeon grid, entrance/treasure markers, placed
-- monsters, the live hero, the planned A* path, and the build-phase
-- placement cursor. Sole consumer of love.graphics for the world view.

local grid     = require("src.grid")
local dungeon  = require("src.dungeon")
local state    = require("src.state")
local assets   = require("src.assets")
local viewport = require("src.viewport")

local M = {}

local COLOR_CURSOR_OK  = { 0.40, 1.00, 0.50, 0.30 }
local COLOR_CURSOR_BAD = { 1.00, 0.40, 0.40, 0.30 }
local COLOR_PATH_DOT   = { 1.00, 1.00, 1.00, 0.20 }

-- 24×24 entity sprites are blitted with a 4-px inset so they sit centered
-- inside their 32×32 tile.
local SPRITE_INSET = (grid.TILE - 24) / 2

-- Linear tile-to-tile glide. Less than STEP_INTERVAL (0.6s) so the entity
-- briefly rests on the destination tile before the next tick fires; the
-- pause makes each step legible while the glide kills the snap. Pure
-- render-side: state.lua still moves entities one full tile per tick.
local MOVE_DUR = 0.45

-- Resolve the pixel position the entity should be drawn at this frame.
-- Tracks the last-drawn (smooth) pixel pos and the last-seen tile coords
-- on the entity itself; when the tile coords change, starts a tween from
-- the last-drawn pixel to the new tile's pixel. New entities (first sight)
-- snap with no tween — that handles wave-queue spawns and slime splits
-- cleanly without a teleport-from-origin glitch.
local function smooth_pixel_pos(entity, px, py)
    local now = love.timer.getTime()

    if entity._smooth_tx == nil then
        entity._smooth_tx = entity.x
        entity._smooth_ty = entity.y
        entity._smooth_px = px
        entity._smooth_py = py
        return px, py
    end

    if entity._smooth_tx ~= entity.x or entity._smooth_ty ~= entity.y then
        entity._tween_from_px = entity._smooth_px
        entity._tween_from_py = entity._smooth_py
        entity._tween_to_px   = px
        entity._tween_to_py   = py
        entity._tween_at      = now
        entity._smooth_tx     = entity.x
        entity._smooth_ty     = entity.y
    end

    if entity._tween_at then
        local t = (now - entity._tween_at) / MOVE_DUR
        if t >= 1 then
            entity._smooth_px = entity._tween_to_px
            entity._smooth_py = entity._tween_to_py
            entity._tween_at  = nil
        else
            entity._smooth_px = entity._tween_from_px
                + (entity._tween_to_px - entity._tween_from_px) * t
            entity._smooth_py = entity._tween_from_py
                + (entity._tween_to_py - entity._tween_from_py) * t
        end
    else
        entity._smooth_px = px
        entity._smooth_py = py
    end

    return entity._smooth_px, entity._smooth_py
end

function M.draw_dungeon(d)
    love.graphics.setColor(1, 1, 1, 1)

    local floor_imgs = assets.tiles.floor
    local wall_imgs  = assets.tiles.wall
    local n_floor    = #floor_imgs
    local n_wall     = #wall_imgs

    for ty = 1, grid.HEIGHT do
        for tx = 1, grid.WIDTH do
            local px, py = grid.tile_to_pixel(tx, ty)
            local img

            if tx == d.entrance.x and ty == d.entrance.y then
                img = assets.tiles.door
            elseif tx == d.treasure.x and ty == d.treasure.y then
                img = assets.tiles.treasure
            elseif d.grid[ty][tx] == dungeon.WALL then
                img = wall_imgs[assets.tile_variation(tx, ty, n_wall)]
            else
                img = floor_imgs[assets.tile_variation(tx, ty, n_floor)]
            end

            love.graphics.draw(img, px, py)
        end
    end
end

-- Per-entity animation state lives lazily on the entity table itself
-- (`_anim_phase`). Phase is seeded from the entity's spawn position so two
-- monsters in adjacent tiles don't bob in lockstep.
local function frame_for(entity, frames, frame_dur)
    if not entity._anim_phase then
        entity._anim_phase = ((entity.x or 0) * 0.13 + (entity.y or 0) * 0.31) % 1
    end
    local t = love.timer.getTime() + entity._anim_phase
    return frames[math.floor(t / frame_dur) % #frames + 1]
end

-- Resolve which animation frame to draw for an entity this tick. Priority:
--   1. Death linger (anims.death for death_dur, then nil so the corpse vanishes)
--   2. Attack flash (anims.attack for attack_dur)
--   3. Loop animation (idle for monsters, walk for the moving hero)
-- Returns nil if the entity should not be drawn at all.
local function pick_image(entity, anims, loop_kind)
    local now = love.timer.getTime()

    if entity._death_at then
        if now - entity._death_at < anims.death_dur then return anims.death end
        return nil
    end
    if not entity.alive then return nil end

    if entity._attack_at and now - entity._attack_at < anims.attack_dur then
        return anims.attack
    end

    if loop_kind == "walk" then
        return frame_for(entity, anims.walk, anims.walk_dur)
    end
    return frame_for(entity, anims.idle, anims.idle_dur)
end

function M.draw_monsters(monsters)
    love.graphics.setColor(1, 1, 1, 1)
    for _, m in ipairs(monsters) do
        local anims = assets.entity[m.type]
        local img   = pick_image(m, anims, "idle")
        if img then
            local px, py = grid.tile_to_pixel(m.x, m.y)
            local sx, sy = smooth_pixel_pos(m, px, py)
            -- Mini-slimes (slime split) render at 70% scale to read as "smaller
            -- threats" without needing a separate sprite set. 24×24 base sprite
            -- centered inside the tile via SPRITE_INSET; scaled draw stays
            -- centered by using the matching half-pixel offset.
            if m.is_mini then
                local s = 0.7
                local ox = (24 * (1 - s)) / 2
                love.graphics.draw(img,
                    sx + SPRITE_INSET + ox, sy + SPRITE_INSET + ox,
                    0, s, s)
            else
                love.graphics.draw(img, sx + SPRITE_INSET, sy + SPRITE_INSET)
            end
        end
    end
end

-- Orc-corpse marker: a faded blood splotch that persists past the orc's
-- death animation so the player sees the tile is still blocked. Drawn as a
-- plain rect — no sprite asset needed for the v1.5 readout.
function M.draw_corpses(corpses)
    if not corpses then return end
    for _, c in ipairs(corpses) do
        local px, py = grid.tile_to_pixel(c.x, c.y)
        love.graphics.setColor(0.45, 0.10, 0.10, 0.55)
        love.graphics.rectangle("fill",
            px + 6, py + 6, grid.TILE - 12, grid.TILE - 12)
    end
    love.graphics.setColor(1, 1, 1, 1)
end

function M.draw_path(game)
    if game.phase ~= state.PHASE_INVASION then return end
    love.graphics.setColor(COLOR_PATH_DOT)
    for _, h in ipairs(game.heroes) do
        if h.alive then
            local path = state.hero_path(game, h)
            if path then
                for _, p in ipairs(path) do
                    local px, py = grid.tile_to_pixel(p.x, p.y)
                    love.graphics.circle("fill",
                        px + grid.TILE / 2, py + grid.TILE / 2,
                        grid.TILE * 0.10)
                end
            end
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

function M.draw_heroes(heroes)
    if not heroes then return end
    love.graphics.setColor(1, 1, 1, 1)
    for _, h in ipairs(heroes) do
        local anims = assets.entity[h.class]
        local img   = pick_image(h, anims, "walk")
        if img then
            local px, py = grid.tile_to_pixel(h.x, h.y)
            local sx, sy = smooth_pixel_pos(h, px, py)
            love.graphics.draw(img, sx + SPRITE_INSET, sy + SPRITE_INSET)
        end
    end
end

function M.draw_build_cursor(game)
    if game.phase ~= state.PHASE_BUILD then return end
    local mx, my = viewport.mouse_position()
    local tx, ty = grid.pixel_to_tile(mx, my)
    if not tx then return end

    local px, py = grid.tile_to_pixel(tx, ty)
    local ok
    if game.selected_tool == state.TOOL_WALL then
        ok = state.can_place_wall(game, tx, ty)
            or state.can_remove_wall(game, tx, ty)
    else
        ok = state.can_place_monster(game, tx, ty)
    end
    love.graphics.setColor(ok and COLOR_CURSOR_OK or COLOR_CURSOR_BAD)
    love.graphics.rectangle("fill", px, py, grid.TILE, grid.TILE)
    love.graphics.setColor(1, 1, 1, 1)
end

return M
