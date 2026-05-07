-- Entity sprite generators (24×24, centered in 32×32 tiles by the renderer).
-- Each function paints a left-half silhouette, calls mirror_x for symmetry,
-- adds asymmetric props (weapon, shield, highlight), then runs outline in
-- `void`. Pure: same seed → same image.
--
-- Silhouette grammar (rough Y bands, used loosely so each creature has its
-- own proportions): head 5..10, torso 11..16, hips 17..18, legs 19..21,
-- feet 22. Mirror axis is between x=12 and x=13.

local rand    = require("src.rand")
local sprite  = require("src.gen.sprite_base")
local palette = require("src.palette")

local M = {}

M.SIZE = 24

-- ============================================================================
-- Monsters
-- ============================================================================

function M.gen_goblin(seed)
    local _ = rand.new(seed)  -- reserved for future jittered details
    local c = sprite.new_canvas(M.SIZE, M.SIZE)
    local body  = palette.moss
    local shade = palette.moss_dark
    local eye   = palette.gold_accent
    local belt  = palette.rust_dark

    -- Pointy ear jutting up-out from skull.
    sprite.set_pixel(c,  9, 11, body)
    sprite.set_pixel(c, 10, 10, body)

    -- Skull (4×4) hunched forward.
    sprite.fill_rect(c, 10, 11, 3, 3, body)
    sprite.fill_rect(c, 11, 10, 2, 1, body)

    -- Brow shadow.
    sprite.fill_rect(c, 10, 13, 3, 1, shade)

    -- Eye.
    sprite.set_pixel(c, 11, 12, eye)

    -- Hunched torso, narrower than head.
    sprite.fill_rect(c, 10, 14, 3, 4, body)
    sprite.fill_rect(c, 10, 17, 3, 1, shade)

    -- Belt.
    sprite.fill_rect(c, 10, 18, 3, 1, belt)

    -- Skinny arm hanging.
    sprite.fill_rect(c,  9, 14, 1, 4, body)

    -- Two short legs (mirror produces second leg with 2-px gap).
    sprite.fill_rect(c, 10, 19, 2, 3, body)

    -- Foot pad.
    sprite.fill_rect(c,  9, 22, 3, 1, shade)

    sprite.mirror_x(c)
    sprite.outline(c, palette.void)

    -- Crude club, asymmetric (no mirror), no extra outline so it stays slim.
    sprite.fill_rect(c, 17, 14, 2, 5, palette.rust)
    sprite.set_pixel(c, 18, 13, palette.rust_dark)

    return sprite.to_image(c)
end

function M.gen_orc(seed)
    local _ = rand.new(seed)
    local c = sprite.new_canvas(M.SIZE, M.SIZE)
    local body  = palette.rust
    local shade = palette.rust_dark
    local eye   = palette.blood
    local tusk  = palette.bone

    -- Big square skull.
    sprite.fill_rect(c,  8,  6, 5, 5, body)
    sprite.fill_rect(c,  8, 10, 5, 1, shade)

    -- Eye, deep-set.
    sprite.set_pixel(c, 10, 8, eye)

    -- Two tusks stick down from the chin.
    sprite.set_pixel(c, 11, 11, tusk)
    sprite.set_pixel(c, 11, 12, tusk)

    -- Thick neck.
    sprite.fill_rect(c,  9, 11, 4, 1, body)

    -- Massive shoulders + chest.
    sprite.fill_rect(c,  7, 12, 6, 5, body)
    sprite.fill_rect(c,  7, 15, 6, 1, shade)

    -- Burly arm.
    sprite.fill_rect(c,  6, 13, 1, 5, body)

    -- Belt slab.
    sprite.fill_rect(c,  8, 17, 5, 1, palette.void)

    -- Stocky legs.
    sprite.fill_rect(c,  8, 18, 5, 4, body)
    sprite.fill_rect(c,  8, 20, 5, 1, shade)

    -- Foot.
    sprite.fill_rect(c,  7, 22, 3, 1, palette.void)

    sprite.mirror_x(c)
    sprite.outline(c, palette.void)

    return sprite.to_image(c)
end

function M.gen_slime(seed)
    local _ = rand.new(seed)
    local c = sprite.new_canvas(M.SIZE, M.SIZE)
    local body = palette.ice
    local belly = palette.arcane
    local hi   = palette.paper
    local eye  = palette.void

    -- Round-ish blob: pyramid on top, wide middle, settling base.
    sprite.fill_rect(c,  9, 12, 7, 1, body)   -- 9..15 x12
    sprite.fill_rect(c,  8, 13, 9, 1, body)
    sprite.fill_rect(c,  7, 14, 11, 6, body)  -- 7..17 wide middle
    sprite.fill_rect(c,  8, 20, 9, 1, body)
    sprite.fill_rect(c,  9, 21, 7, 1, body)

    -- Belly shadow band.
    sprite.fill_rect(c,  8, 19, 9, 1, belly)

    -- Two eyes (intentionally drawn whole — slime asymmetry would feel off).
    sprite.fill_rect(c, 10, 15, 1, 2, eye)
    sprite.fill_rect(c, 14, 15, 1, 2, eye)

    -- Specular highlight, top-left only — gives the blob volume.
    sprite.set_pixel(c,  9, 14, hi)
    sprite.set_pixel(c, 10, 13, hi)

    -- Drips at the base corners.
    sprite.set_pixel(c,  8, 22, body)
    sprite.set_pixel(c, 16, 22, body)

    sprite.outline(c, palette.void)
    return sprite.to_image(c)
end

-- ============================================================================
-- Heroes
-- ============================================================================

function M.gen_warrior(seed)
    local _ = rand.new(seed)
    local c = sprite.new_canvas(M.SIZE, M.SIZE)
    local armor = palette.bone
    local shade = palette.stone_light
    local skin  = palette.flesh
    local plume = palette.blood
    local trim  = palette.gold_accent

    -- Helmet plume.
    sprite.set_pixel(c, 12, 4, plume)
    sprite.set_pixel(c, 11, 5, plume)
    sprite.set_pixel(c, 12, 5, plume)

    -- Helm.
    sprite.fill_rect(c,  9,  6, 4, 4, armor)
    sprite.fill_rect(c,  9,  6, 4, 1, shade)

    -- Visor slit.
    sprite.fill_rect(c,  9,  8, 4, 1, palette.void)

    -- Chin (skin under helmet).
    sprite.fill_rect(c, 10, 10, 3, 1, skin)

    -- Pauldron.
    sprite.set_pixel(c,  7, 11, armor)
    sprite.set_pixel(c,  8, 11, armor)

    -- Cuirass.
    sprite.fill_rect(c,  8, 12, 5, 5, armor)
    sprite.fill_rect(c,  8, 12, 5, 1, shade)
    sprite.set_pixel(c, 12, 13, trim)
    sprite.set_pixel(c, 12, 14, trim)

    -- Arm.
    sprite.fill_rect(c,  7, 13, 1, 4, armor)

    -- Belt.
    sprite.fill_rect(c,  9, 17, 4, 1, palette.void)

    -- Greaves.
    sprite.fill_rect(c,  9, 18, 4, 4, armor)
    sprite.fill_rect(c,  9, 18, 4, 1, shade)

    -- Foot.
    sprite.fill_rect(c,  9, 22, 4, 1, palette.void)

    sprite.mirror_x(c)
    sprite.outline(c, palette.void)

    -- Asymmetric: shield on left flank, sword on right flank.
    sprite.fill_rect(c,  4, 13, 2, 6, palette.rust_dark)
    sprite.fill_rect(c,  4, 13, 2, 1, palette.bone)
    sprite.set_pixel(c,  5, 16, palette.gold_accent)

    sprite.fill_rect(c, 19,  8, 2, 9, palette.bone)
    sprite.set_pixel(c, 20,  7, palette.paper)
    sprite.fill_rect(c, 18, 17, 4, 1, palette.gold_accent)
    sprite.fill_rect(c, 19, 18, 2, 2, palette.rust)

    return sprite.to_image(c)
end

function M.gen_archer(seed)
    local _ = rand.new(seed)
    local c = sprite.new_canvas(M.SIZE, M.SIZE)
    local hood = palette.moss_dark
    local skin = palette.flesh
    local tunic = palette.moss
    local belt = palette.rust_dark
    local boots = palette.void

    -- Hood crown.
    sprite.fill_rect(c, 10,  6, 3, 1, hood)
    sprite.fill_rect(c,  9,  7, 4, 4, hood)

    -- Face shadow inside hood + nose/cheek showing.
    sprite.fill_rect(c, 10,  8, 3, 2, palette.void)
    sprite.set_pixel(c, 11,  9, skin)
    sprite.set_pixel(c, 12,  9, skin)
    sprite.fill_rect(c, 11, 10, 2, 1, skin)

    -- Cape over shoulders.
    sprite.fill_rect(c,  8, 11, 5, 4, hood)

    -- Belt.
    sprite.fill_rect(c,  9, 15, 4, 1, belt)

    -- Tunic body.
    sprite.fill_rect(c,  9, 16, 4, 3, tunic)

    -- Trousers.
    sprite.fill_rect(c,  9, 19, 4, 3, palette.rust_dark)

    -- Boots.
    sprite.fill_rect(c,  9, 22, 4, 1, boots)

    sprite.mirror_x(c)
    sprite.outline(c, palette.void)

    -- Asymmetric bow on the right side, drawn after outline so the curve
    -- and string stay crisp (1-px elements would smear under outline).
    sprite.set_pixel(c, 18,  7, palette.rust)
    sprite.fill_rect(c, 19,  8, 1, 9, palette.rust)
    sprite.set_pixel(c, 18, 17, palette.rust)
    sprite.fill_rect(c, 18,  9, 1, 7, palette.bone)
    sprite.set_pixel(c, 17, 12, palette.gold_accent)

    return sprite.to_image(c)
end

function M.gen_mage(seed)
    local _ = rand.new(seed)
    local c = sprite.new_canvas(M.SIZE, M.SIZE)
    local robe = palette.arcane
    local skin = palette.flesh
    local beard = palette.bone

    -- Tall pointed wizard hat.
    sprite.set_pixel(c, 12, 3, robe)
    sprite.fill_rect(c, 11, 4, 2, 1, robe)
    sprite.fill_rect(c, 11, 5, 2, 1, robe)
    sprite.fill_rect(c, 10, 6, 3, 1, robe)

    -- Wide hat brim.
    sprite.fill_rect(c,  9, 7, 4, 1, robe)

    -- Face.
    sprite.fill_rect(c, 10, 8, 3, 2, skin)
    sprite.set_pixel(c, 11, 9, palette.void)

    -- Beard.
    sprite.fill_rect(c, 10, 10, 3, 2, beard)

    -- Shoulders.
    sprite.fill_rect(c,  9, 12, 4, 2, robe)

    -- Long robe (no leg detail) flaring slightly at the bottom.
    sprite.fill_rect(c,  9, 14, 4, 7, robe)
    sprite.fill_rect(c,  8, 21, 5, 1, robe)

    -- Robe central fold.
    sprite.fill_rect(c, 12, 14, 1, 7, palette.void)

    sprite.mirror_x(c)
    sprite.outline(c, palette.void)

    -- Asymmetric staff with glowing orb (drawn after outline for crisp glow).
    sprite.fill_rect(c, 18,  9, 1, 13, palette.rust_dark)
    sprite.fill_rect(c, 17,  6, 3, 3, palette.ember)
    sprite.set_pixel(c, 18,  7, palette.gold_accent)
    sprite.set_pixel(c, 17,  7, palette.paper)

    return sprite.to_image(c)
end

-- ============================================================================
-- Debug screen (F3): all six entities at 6× scale on a 3×2 grid.
-- ============================================================================

local debug_cache = nil

local function build_debug_cache()
    return {
        { "goblin",  M.gen_goblin(101)  },
        { "orc",     M.gen_orc(102)     },
        { "slime",   M.gen_slime(103)   },
        { "warrior", M.gen_warrior(201) },
        { "archer",  M.gen_archer(202)  },
        { "mage",    M.gen_mage(203)    },
    }
end

function M.draw_debug()
    if not debug_cache then debug_cache = build_debug_cache() end

    local W, H = love.graphics.getWidth(), love.graphics.getHeight()

    love.graphics.setColor(palette.void[1], palette.void[2], palette.void[3], 0.96)
    love.graphics.rectangle("fill", 0, 0, W, H)

    love.graphics.setColor(palette.paper)
    love.graphics.print("ENTITIES — static silhouettes  (F3 to toggle)", 16, 12)
    love.graphics.setColor(palette.bone)
    love.graphics.print("24x24 sprites at 6x scale; outline in 'void'; weapons asymmetric",
        16, 28)

    local cols, rows = 3, 2
    local scale = 6
    local sprite_size = M.SIZE * scale
    local pad = 4
    local panel = sprite_size + pad * 2
    local gap_x, gap_y = 32, 50
    local total_w = cols * panel + (cols - 1) * gap_x
    local total_h = rows * panel + (rows - 1) * gap_y
    local x0 = math.floor((W - total_w) / 2)
    local y0 = math.floor((H - total_h) / 2) + 12

    for i, e in ipairs(debug_cache) do
        local name, img = e[1], e[2]
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local x = x0 + col * (panel + gap_x)
        local y = y0 + row * (panel + gap_y)

        love.graphics.setColor(palette.stone_dark)
        love.graphics.rectangle("fill", x, y, panel, panel)
        love.graphics.setColor(palette.stone)
        love.graphics.rectangle("line", x, y, panel, panel)

        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(img, x + pad, y + pad, 0, scale, scale)

        love.graphics.setColor(palette.paper)
        love.graphics.print(name, x, y + panel + 8)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

return M
