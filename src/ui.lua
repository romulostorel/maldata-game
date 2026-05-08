-- HUD, entity HP bars, result panel + restart button, phase icon.
-- Draws procgen chrome from assets.ui; this module never touches sprite_base.
-- World-rendering belongs in render.lua.

local grid    = require("src.grid")
local state   = require("src.state")
local assets  = require("src.assets")
local palette = require("src.palette")
local audio   = require("src.audio")
local hero    = require("src.hero")

local M = {}

local BAR_W        = 24       -- matches assets.HP_BAR_W
local BAR_H        = 6        -- matches assets.HP_BAR_H
local BAR_INNER_W  = BAR_W - 2
local BAR_INNER_H  = BAR_H - 2
local BAR_OFFSET_Y = grid.TILE - BAR_H - 2

local COLOR_BAR_HERO = palette.lighten(palette.moss, 0.20)
local COLOR_BAR_MONS = palette.blood

-- Result panel sits at (160, 160) and spans 480×280. The two action buttons
-- share its bottom row: RETRY (same dungeon, also bound to SPACE) on the
-- left, NEW DUNGEON (fresh seed, also bound to R) on the right. Both reuse
-- the same 200×50 asset; layout: 20 px panel padding + 200 button + 40 gap
-- + 200 button + 20 padding = 480.
local RETRY_BTN       = { x = 180, y = 380, w = 200, h = 50 }
local NEW_DUNGEON_BTN = { x = 420, y = 380, w = 200, h = 50 }

local PANEL = { x = 160, y = 160, w = 480, h = 280 }

-- Edge-detect for the per-button hover SFX. Tracked per button so moving
-- between them re-fires the cue.
local was_retry_hovered       = false
local was_new_dungeon_hovered = false

-- One-shot tutorial overlay. Set to true on the first input event and
-- never reset within a session (intentional — state.reset / R should not
-- pop the tutorial back open).
local tutorial_dismissed = false

local function draw_bar(entity, color)
    local px, py = grid.tile_to_pixel(entity.x, entity.y)
    local bar_x = math.floor(px + (grid.TILE - BAR_W) / 2)
    local bar_y = py + BAR_OFFSET_Y

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(assets.ui.hp_bar, bar_x, bar_y)

    local fill_w = math.floor(BAR_INNER_W * (entity.hp / entity.max_hp) + 0.5)
    if fill_w > 0 then
        love.graphics.setColor(color)
        love.graphics.rectangle("fill", bar_x + 1, bar_y + 1, fill_w, BAR_INNER_H)
    end
    love.graphics.setColor(1, 1, 1, 1)
end

function M.draw_hp_bars(game)
    if game.phase == state.PHASE_BUILD then return end

    for _, m in ipairs(game.monsters) do
        if m.alive then draw_bar(m, COLOR_BAR_MONS) end
    end
    for _, h in ipairs(game.heroes) do
        if h.alive then draw_bar(h, COLOR_BAR_HERO) end
    end

    love.graphics.setColor(1, 1, 1, 1)
end

-- Top chrome strip height. Sized to fit 4 HUD lines (phase / phase-info /
-- hotkeys / wave preview) at 16 px each + 12 px bottom padding. Constant
-- across phases so the strip never resizes mid-run.
local CHROME_H = 76

local function draw_chrome_strip()
    local W = love.graphics.getWidth()
    love.graphics.setColor(palette.stone_dark)
    love.graphics.rectangle("fill", 0, 0, W, CHROME_H)
    -- Faint paper line at the bottom: separates "chrome" from "play area"
    -- without screaming. Half-alpha keeps it as a hint, not a hard border.
    love.graphics.setColor(palette.paper[1], palette.paper[2], palette.paper[3], 0.45)
    love.graphics.rectangle("fill", 0, CHROME_H - 1, W, 1)
end

function M.draw_hud(game)
    draw_chrome_strip()

    -- Phase icon centered vertically in the chrome strip, top-right corner.
    local icon = assets.ui.phase_icon[game.phase]
    if icon then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(icon, love.graphics.getWidth() - 32,
            math.floor((CHROME_H - 24) / 2))
    end

    love.graphics.setColor(palette.paper)
    love.graphics.print(
        ("PHASE: %s    seed: %d    FPS: %d")
            :format(game.phase:upper(), game.seed, love.timer.getFPS()),
        8, 8)

    if game.phase == state.PHASE_BUILD then
        love.graphics.setColor(palette.bone)
        local sel = game.selected_tool == state.TOOL_WALL
            and "wall"
            or game.selected_monster_type
        love.graphics.print(
            ("[1] goblin (2)  [2] orc (4)  [3] slime (3)  [4] wall (%d)    selected: %s    budget: %d/%d")
                :format(state.WALL_COST, sel, state.spent_budget(game), state.BUDGET),
            8, 24)
    elseif game.phase == state.PHASE_INVASION then
        love.graphics.setColor(palette.bone)
        local alive = 0
        for _, h in ipairs(game.heroes) do
            if h.alive then alive = alive + 1 end
        end
        love.graphics.print(
            ("heroes: %d alive   queued: %d    %s")
                :format(alive, #game.hero_queue,
                    game.auto_step and "[AUTO]" or "[PAUSED]"),
            8, 24)
    end

    -- Hotkeys: bone (was stone_light, which vanished against the dungeon).
    -- Against the new chrome strip, bone reads cleanly without competing
    -- with the brighter paper headline above.
    love.graphics.setColor(palette.bone)
    local hotkeys
    if game.phase == state.PHASE_BUILD then
        hotkeys = "[LMB] place  [RMB] remove  [SPACE] start invasion  [R] new dungeon  [ESC] quit"
    elseif game.phase == state.PHASE_INVASION then
        hotkeys = "[SPACE] pause/resume    [.] step    [R] new dungeon    [ESC] quit"
    else
        hotkeys = "[SPACE] retry same dungeon    [R] new dungeon    [ESC] quit"
    end
    love.graphics.print(hotkeys, 8, 40)

    if game.phase == state.PHASE_BUILD and game.wave_preview then
        M.draw_wave_preview(game)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

-- Wave preview shown during BUILD: a row of mini-cards (sprite + class +
-- stats) in the dead space below the grid. Each card carries the class
-- color on its border so the trio reads at a glance — sprite identifies
-- the threat, numbers tell you how dangerous.
local CARD_W, CARD_H = 140, 46
local CARD_GAP = 20
local CARD_Y = 550
local HEADER_Y = 534

local function draw_hero_card(x, y, h, font)
    local class_color = hero.CLASSES[h.class].color

    love.graphics.setColor(palette.stone_dark)
    love.graphics.rectangle("fill", x, y, CARD_W, CARD_H)
    love.graphics.setColor(class_color)
    love.graphics.rectangle("line", x + 0.5, y + 0.5, CARD_W - 1, CARD_H - 1)

    -- Idle frame 1 of the live entity sprite. 24×24, vertically centered.
    local sprite = assets.entity[h.class].idle[1]
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(sprite, x + 8, y + math.floor((CARD_H - 24) / 2))

    -- Class name in class color, stats in bone underneath.
    love.graphics.setColor(class_color)
    love.graphics.print(h.class:upper(), x + 40, y + 6)

    love.graphics.setColor(palette.bone)
    love.graphics.print(
        ("HP %d   ATK %d"):format(h.hp, h.atk),
        x + 40, y + 24)
end

function M.draw_wave_preview(game)
    if #game.wave_preview == 0 then return end

    local W = love.graphics.getWidth()
    local n = #game.wave_preview
    local total = n * CARD_W + (n - 1) * CARD_GAP
    local x0 = math.floor((W - total) / 2)

    local font = love.graphics.getFont()
    love.graphics.setColor(palette.stone_light)
    local hdr = "INCOMING WAVE"
    love.graphics.print(hdr, math.floor((W - font:getWidth(hdr)) / 2), HEADER_Y)

    for i, h in ipairs(game.wave_preview) do
        draw_hero_card(x0 + (i - 1) * (CARD_W + CARD_GAP), CARD_Y, h, font)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

local function count_defeated(heroes)
    local n = 0
    for _, h in ipairs(heroes) do
        if not h.alive then n = n + 1 end
    end
    return n
end

local function draw_button(btn, label, hovered, hint_key, font)
    local btn_img = hovered and assets.ui.button_hover or assets.ui.button_idle
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(btn_img, btn.x, btn.y)

    local scale = 1.5
    local tw = font:getWidth(label) * scale
    local th = font:getHeight() * scale
    love.graphics.setColor(palette.paper)
    love.graphics.print(label,
        btn.x + (btn.w - tw) / 2,
        btn.y + (btn.h - th) / 2,
        0, scale, scale)

    -- Tiny key hint above the button so the player sees both the click
    -- target and the hotkey at the same glance.
    if hint_key then
        love.graphics.setColor(palette.bone)
        local hw = font:getWidth(hint_key)
        love.graphics.print(hint_key, btn.x + (btn.w - hw) / 2, btn.y - 16)
    end
end

-- Stat chip: filled rect in a dimmed copy of the accent color, 1 px border
-- in the accent itself, paper-colored label centered. Used for the W/L
-- session counters on the result panel.
local function draw_chip(x, y, w, h, label, accent, font)
    love.graphics.setColor(palette.darken(accent, 0.7))
    love.graphics.rectangle("fill", x, y, w, h)
    love.graphics.setColor(accent)
    love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1)

    local scale = 1.5
    local tw = font:getWidth(label) * scale
    local th = font:getHeight() * scale
    love.graphics.setColor(palette.paper)
    love.graphics.print(label,
        x + (w - tw) / 2, y + (h - th) / 2, 0, scale, scale)
end

-- W/L chip layout. Two 100×32 chips centered horizontally with a 60 px
-- gap, sitting between the heroes-defeated label (~y=290) and the action
-- buttons (y=380).
local CHIP_W, CHIP_H = 100, 32
local CHIP_GAP = 60
local CHIP_Y = 318

local CHIP_W_COLOR = palette.lighten(palette.moss, 0.15)
local CHIP_L_COLOR = palette.lighten(palette.blood, 0.10)

function M.draw_result(game)
    if game.phase ~= state.PHASE_RESULT then
        was_retry_hovered       = false
        was_new_dungeon_hovered = false
        return
    end

    -- Heavier overlay (was 0.65) so the dungeon doesn't compete with the
    -- panel for attention.
    love.graphics.setColor(palette.void[1], palette.void[2], palette.void[3], 0.85)
    love.graphics.rectangle("fill", 0, 0,
        love.graphics.getWidth(), love.graphics.getHeight())

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(assets.ui.panel, PANEL.x, PANEL.y)

    local font = love.graphics.getFont()
    local W = love.graphics.getWidth()
    local title, color
    if game.outcome == state.OUTCOME_TREASURE_STOLEN then
        title = "TREASURE STOLEN"
        color = palette.ember
    elseif game.outcome == state.OUTCOME_HERO_DEAD then
        title = "HERO DEFEATED"
        color = palette.lighten(palette.moss, 0.20)
    else
        title = "RUN OVER"
        color = palette.bone
    end

    love.graphics.setColor(color)
    local title_scale = 3
    local tw = font:getWidth(title) * title_scale
    love.graphics.print(title, (W - tw) / 2, 188, 0, title_scale, title_scale)

    -- Big focal stat: "X / Y" in paper at scale 2.5, then a small
    -- "heroes defeated" caption right under it. The number is the eye
    -- target; the caption is just context.
    local big = ("%d / %d"):format(count_defeated(game.heroes), game.num_heroes)
    local big_scale = 2.5
    local bw = font:getWidth(big) * big_scale
    love.graphics.setColor(palette.paper)
    love.graphics.print(big, (W - bw) / 2, 240, 0, big_scale, big_scale)

    local cap = "heroes defeated"
    local cw = font:getWidth(cap)
    love.graphics.setColor(palette.stone_light)
    love.graphics.print(cap, (W - cw) / 2, 285)

    -- W/L chips with semantic colors so the player reads "good thing /
    -- bad thing" before reading the numbers.
    local total_w = CHIP_W * 2 + CHIP_GAP
    local chip_x  = math.floor((W - total_w) / 2)
    draw_chip(chip_x, CHIP_Y, CHIP_W, CHIP_H,
        ("%d W"):format(game.session.wins), CHIP_W_COLOR, font)
    draw_chip(chip_x + CHIP_W + CHIP_GAP, CHIP_Y, CHIP_W, CHIP_H,
        ("%d L"):format(game.session.losses), CHIP_L_COLOR, font)

    local mx, my = love.mouse.getPosition()

    local retry_hov = M.is_retry_clicked(mx, my)
    if retry_hov and not was_retry_hovered then audio.play("ui_hover") end
    was_retry_hovered = retry_hov
    draw_button(RETRY_BTN, "RETRY", retry_hov, "[SPACE]", font)

    local new_hov = M.is_new_dungeon_clicked(mx, my)
    if new_hov and not was_new_dungeon_hovered then audio.play("ui_hover") end
    was_new_dungeon_hovered = new_hov
    draw_button(NEW_DUNGEON_BTN, "NEW DUNGEON", new_hov, "[R]", font)

    love.graphics.setColor(1, 1, 1, 1)
end

local function inside(btn, mx, my)
    return mx >= btn.x and mx <= btn.x + btn.w
       and my >= btn.y and my <= btn.y + btn.h
end

function M.is_retry_clicked(mx, my)
    return inside(RETRY_BTN, mx, my)
end

function M.is_new_dungeon_clicked(mx, my)
    return inside(NEW_DUNGEON_BTN, mx, my)
end

-- First-boot tutorial: drawn over the build phase until any input arrives.
-- Inverts the usual roguelike framing ("you are the dungeon, not the hero")
-- and shows the controls. Hidden during invasion/result, and once dismissed
-- it stays gone for the rest of the session — including across R/new-dungeon.
local TUTORIAL_PANEL = { x = 160, y = 160, w = 480, h = 280 }

function M.draw_tutorial(game)
    if tutorial_dismissed then return end
    if game.phase ~= state.PHASE_BUILD then return end

    love.graphics.setColor(palette.void[1], palette.void[2], palette.void[3], 0.70)
    love.graphics.rectangle("fill", 0, 0,
        love.graphics.getWidth(), love.graphics.getHeight())

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(assets.ui.panel, TUTORIAL_PANEL.x, TUTORIAL_PANEL.y)

    local font = love.graphics.getFont()
    local W = love.graphics.getWidth()

    local title = "WELCOME TO THE DUNGEON"
    local title_scale = 2
    local tw = font:getWidth(title) * title_scale
    love.graphics.setColor(palette.ember)
    love.graphics.print(title, (W - tw) / 2, TUTORIAL_PANEL.y + 24,
        0, title_scale, title_scale)

    local body = {
        "You ARE the dungeon. A wave of heroes invades through",
        "the door — your monsters and walls must stop them",
        "from reaching the throne.",
        "",
        "1 / 2 / 3   pick a monster",
        "4           switch to wall tool",
        "LMB         place    RMB    remove",
        "SPACE       launch invasion",
    }
    love.graphics.setColor(palette.bone)
    for i, line in ipairs(body) do
        local lw = font:getWidth(line)
        love.graphics.print(line, (W - lw) / 2, TUTORIAL_PANEL.y + 80 + (i - 1) * 16)
    end

    local hint = "[click or press any key to dismiss]"
    love.graphics.setColor(palette.stone_light)
    local hw = font:getWidth(hint)
    love.graphics.print(hint, (W - hw) / 2, TUTORIAL_PANEL.y + TUTORIAL_PANEL.h - 24)

    love.graphics.setColor(1, 1, 1, 1)
end

function M.dismiss_tutorial()
    tutorial_dismissed = true
end

function M.tutorial_visible()
    return not tutorial_dismissed
end

return M
