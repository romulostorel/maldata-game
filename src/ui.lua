-- HUD, entity HP bars, result panel + restart button, phase icon.
-- Draws procgen chrome from assets.ui; this module never touches sprite_base.
-- World-rendering belongs in render.lua.

local grid    = require("src.grid")
local state   = require("src.state")
local assets  = require("src.assets")
local palette = require("src.palette")
local audio   = require("src.audio")

local M = {}

local BAR_W        = 24       -- matches assets.HP_BAR_W
local BAR_H        = 6        -- matches assets.HP_BAR_H
local BAR_INNER_W  = BAR_W - 2
local BAR_INNER_H  = BAR_H - 2
local BAR_OFFSET_Y = grid.TILE - BAR_H - 2

local COLOR_BAR_HERO = palette.lighten(palette.moss, 0.20)
local COLOR_BAR_MONS = palette.blood

local RESTART_BTN = { x = 300, y = 380, w = 200, h = 50 }

-- Result-screen panel: positioned so the title (~y=200) and button (y=380)
-- both sit comfortably inside its 480×280 frame.
local PANEL = { x = 160, y = 160, w = 480, h = 280 }

-- Edge-detect for the restart-button hover SFX. Reset whenever the result
-- panel isn't drawn, so re-entering the panel can fire ui_hover again.
local was_restart_hovered = false

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

function M.draw_hud(game)
    -- Phase icon in the top-right corner so it never overlaps HUD text.
    local icon = assets.ui.phase_icon[game.phase]
    if icon then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(icon, love.graphics.getWidth() - 32, 8)
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

    love.graphics.setColor(palette.stone_light)
    local hotkeys
    if game.phase == state.PHASE_BUILD then
        hotkeys = "[LMB] place  [RMB] remove  [SPACE] start invasion  [R] new dungeon  [ESC] quit"
    elseif game.phase == state.PHASE_INVASION then
        hotkeys = "[SPACE] pause/resume    [.] step    [R] new run    [ESC] quit"
    else
        hotkeys = "[SPACE] back to build    [R] new run    [ESC] quit"
    end
    love.graphics.print(hotkeys, 8, 40)

    love.graphics.setColor(1, 1, 1, 1)
end

function M.draw_result(game)
    if game.phase ~= state.PHASE_RESULT then
        was_restart_hovered = false
        return
    end

    love.graphics.setColor(palette.void[1], palette.void[2], palette.void[3], 0.65)
    love.graphics.rectangle("fill", 0, 0,
        love.graphics.getWidth(), love.graphics.getHeight())

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(assets.ui.panel, PANEL.x, PANEL.y)

    local font = love.graphics.getFont()
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
    local title_scale = 4
    local tw = font:getWidth(title) * title_scale
    love.graphics.print(title,
        (love.graphics.getWidth() - tw) / 2, 200,
        0, title_scale, title_scale)

    local mx, my = love.mouse.getPosition()
    local hovered = M.is_restart_clicked(mx, my)
    if hovered and not was_restart_hovered then
        audio.play("ui_hover")
    end
    was_restart_hovered = hovered
    local btn_img = hovered and assets.ui.button_hover or assets.ui.button_idle

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(btn_img, RESTART_BTN.x, RESTART_BTN.y)

    local btn_text = "RESTART"
    local btn_scale = 2
    local btw = font:getWidth(btn_text) * btn_scale
    local bth = font:getHeight() * btn_scale
    love.graphics.setColor(palette.paper)
    love.graphics.print(btn_text,
        RESTART_BTN.x + (RESTART_BTN.w - btw) / 2,
        RESTART_BTN.y + (RESTART_BTN.h - bth) / 2,
        0, btn_scale, btn_scale)

    love.graphics.setColor(1, 1, 1, 1)
end

function M.is_restart_clicked(mx, my)
    return mx >= RESTART_BTN.x and mx <= RESTART_BTN.x + RESTART_BTN.w
       and my >= RESTART_BTN.y and my <= RESTART_BTN.y + RESTART_BTN.h
end

return M
