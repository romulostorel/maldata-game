-- Animation orchestration on top of entity_gen.
--
-- An animation is just a flat array of frame images. anim_gen knows which
-- poses make up each kind and bakes them all up-front so render.lua can do
-- a constant-time lookup per draw.
--
-- Frame durations are returned alongside the frame array so the renderer
-- doesn't need to hardcode timing per entity.

local entity_gen = require("src.gen.entity_gen")
local palette    = require("src.palette")

local M = {}

M.IDLE_DUR = 0.55  -- s/frame; 1.1 s full cycle
M.WALK_DUR = 0.20  -- s/frame; 0.4 s full cycle

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

-- Bake the full animation table for a single entity type. Returned shape:
--   { idle = { Image, Image }, walk = { Image, Image },
--     idle_dur = 0.55, walk_dur = 0.20 }
function M.gen_entity_anims(type_key, seed)
    return {
        idle     = bake(type_key, IDLE_POSES, seed),
        walk     = bake(type_key, WALK_POSES, seed),
        idle_dur = M.IDLE_DUR,
        walk_dur = M.WALK_DUR,
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

    love.graphics.setColor(palette.void[1], palette.void[2], palette.void[3], 0.96)
    love.graphics.rectangle("fill", 0, 0, W, H)

    love.graphics.setColor(palette.paper)
    love.graphics.print("ENTITY ANIMATIONS — idle | walk  (F3 to toggle)", 16, 12)
    love.graphics.setColor(palette.bone)
    love.graphics.print("idle: gentle bob (~1.1s cycle).  walk: leg lift on bipeds (~0.4s).",
        16, 28)

    local cols, rows = 2, 3
    local scale       = 5
    local sprite_size = entity_gen.SIZE * scale
    local pad         = 4
    local pair_gap    = 16
    local panel_w     = sprite_size * 2 + pair_gap + pad * 2
    local panel_h     = sprite_size + pad * 2
    local gap_x, gap_y = 32, 36
    local total_w = cols * panel_w + (cols - 1) * gap_x
    local total_h = rows * panel_h + (rows - 1) * gap_y
    local x0 = math.floor((W - total_w) / 2)
    local y0 = math.floor((H - total_h) / 2) + 10

    for i, e in ipairs(debug_cache) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local x = x0 + col * (panel_w + gap_x)
        local y = y0 + row * (panel_h + gap_y)

        love.graphics.setColor(palette.stone_dark)
        love.graphics.rectangle("fill", x, y, panel_w, panel_h)
        love.graphics.setColor(palette.stone)
        love.graphics.rectangle("line", x, y, panel_w, panel_h)

        local idle_img = e.anims.idle[frame_index(#e.anims.idle, e.anims.idle_dur)]
        local walk_img = e.anims.walk[frame_index(#e.anims.walk, e.anims.walk_dur)]

        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(idle_img, x + pad, y + pad, 0, scale, scale)
        love.graphics.draw(walk_img, x + pad + sprite_size + pair_gap, y + pad,
            0, scale, scale)

        love.graphics.setColor(palette.paper)
        love.graphics.print(e.name, x + pad, y + panel_h + 6)
        love.graphics.setColor(palette.bone)
        love.graphics.print("idle           walk", x + pad, y + panel_h + 22)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

return M
