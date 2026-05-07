-- Animation orchestration on top of entity_gen.
--
-- An animation is just a flat array of frame images. anim_gen knows which
-- poses make up each kind and bakes them all up-front so render.lua can do
-- a constant-time lookup per draw.
--
-- Frame durations are returned alongside the frame array so the renderer
-- doesn't need to hardcode timing per entity.

local entity_gen = require("src.gen.entity_gen")
local sprite     = require("src.gen.sprite_base")
local palette    = require("src.palette")

local M = {}

M.IDLE_DUR   = 0.55  -- s/frame; 1.1 s full cycle
M.WALK_DUR   = 0.20  -- s/frame; 0.4 s full cycle
M.ATTACK_DUR = 0.18  -- single-frame display time
M.DEATH_DUR  = 0.70  -- corpse lingers this long, then disappears

local IDLE_POSES = { "idle_a", "idle_b" }
local WALK_POSES = { "walk_a", "walk_b" }

local function bake(type_key, poses, seed)
    local gen = entity_gen.GENERATORS[type_key]
    local frames = {}
    for i, pose in ipairs(poses) do
        frames[i] = gen(pose, seed)
    end
    return frames
end

-- Attack frame: idle pose with every non-outline pixel mixed toward `paper`.
-- The whole sprite "blooms" pale for one tick, reading as the strike moment.
local function bake_attack(type_key, seed)
    local c = entity_gen.CANVAS_GENERATORS[type_key]("idle_a", seed)
    sprite.tint_filter(c, palette.paper, 0.55, palette.void)
    return sprite.to_image(c)
end

-- Death frame: idle pose flattened to a stone-dark silhouette. Outline and
-- internal void details (eyes, fold) survive, so the entity stays
-- recognizable as a corpse.
local function bake_death(type_key, seed)
    local c = entity_gen.CANVAS_GENERATORS[type_key]("idle_a", seed)
    sprite.recolor_filter(c, palette.stone_dark, palette.void)
    return sprite.to_image(c)
end

-- Bake the full animation table for a single entity type. Returned shape:
--   { idle = { Image, Image }, walk = { Image, Image },
--     attack = Image, death = Image,
--     idle_dur, walk_dur, attack_dur, death_dur }
function M.gen_entity_anims(type_key, seed)
    return {
        idle       = bake(type_key, IDLE_POSES, seed),
        walk       = bake(type_key, WALK_POSES, seed),
        attack     = bake_attack(type_key, seed),
        death      = bake_death(type_key, seed),
        idle_dur   = M.IDLE_DUR,
        walk_dur   = M.WALK_DUR,
        attack_dur = M.ATTACK_DUR,
        death_dur  = M.DEATH_DUR,
    }
end

-- ============================================================================
-- Debug screen (F3): 6 entities, each shown with idle + walk cycling live
-- side by side at 6× scale.
-- ============================================================================

local DEBUG_ROWS = {
    { "goblin",  101 },
    { "orc",     102 },
    { "slime",   103 },
    { "warrior", 201 },
    { "archer",  202 },
    { "mage",    203 },
}

local debug_cache = nil

local function build_debug_cache()
    local cache = {}
    for i, row in ipairs(DEBUG_ROWS) do
        local name, seed = row[1], row[2]
        cache[i] = { name = name, anims = M.gen_entity_anims(name, seed) }
    end
    return cache
end

local function frame_index(num_frames, dur)
    return math.floor(love.timer.getTime() / dur) % num_frames + 1
end

function M.draw_debug()
    if not debug_cache then debug_cache = build_debug_cache() end

    local W, H = love.graphics.getWidth(), love.graphics.getHeight()
    local font = love.graphics.getFont()

    love.graphics.setColor(palette.void[1], palette.void[2], palette.void[3], 0.96)
    love.graphics.rectangle("fill", 0, 0, W, H)

    love.graphics.setColor(palette.paper)
    love.graphics.print("ENTITY ANIMATIONS  (F3 to toggle)", 16, 12)
    love.graphics.setColor(palette.bone)
    love.graphics.print(
        "idle: ~1.1s bob.  walk: ~0.4s leg cycle.  attack: paper flash.  death: stone silhouette.",
        16, 28)

    local SCALE   = 3
    local SPR     = entity_gen.SIZE * SCALE  -- 72 px
    local LABEL_W = 70
    local CELL_W  = SPR + 14
    local ROW_H   = SPR + 6

    local cols     = { "idle", "walk", "attack", "death" }
    local total_w  = LABEL_W + #cols * CELL_W
    local x0       = math.floor((W - total_w) / 2)
    local header_y = 56
    local y0       = header_y + 18

    love.graphics.setColor(palette.bone)
    for i, name in ipairs(cols) do
        local tx = x0 + LABEL_W + (i - 1) * CELL_W + math.floor((SPR - font:getWidth(name)) / 2)
        love.graphics.print(name, tx, header_y)
    end

    for r, e in ipairs(debug_cache) do
        local row_y = y0 + (r - 1) * ROW_H

        love.graphics.setColor(palette.paper)
        love.graphics.print(e.name, x0, row_y + math.floor(SPR / 2) - 6)

        local cells = {
            e.anims.idle[frame_index(#e.anims.idle, e.anims.idle_dur)],
            e.anims.walk[frame_index(#e.anims.walk, e.anims.walk_dur)],
            e.anims.attack,
            e.anims.death,
        }

        for i, img in ipairs(cells) do
            local cx = x0 + LABEL_W + (i - 1) * CELL_W
            love.graphics.setColor(palette.stone_dark)
            love.graphics.rectangle("fill", cx, row_y, SPR, SPR)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(img, cx, row_y, 0, SCALE, SCALE)
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
end

return M
