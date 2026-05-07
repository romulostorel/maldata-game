-- HUD, entity HP bars, result screen, and the restart button.
-- May call love.graphics; world-rendering belongs in render.lua.

local grid  = require("src.grid")
local state = require("src.state")

local M = {}

-- HP bar geometry, drawn inside the tile against its bottom edge.
local BAR_W        = grid.TILE * 0.7
local BAR_H        = 3
local BAR_OFFSET_Y = grid.TILE - BAR_H - 2

local COLOR_BAR_BG    = { 0.10, 0.10, 0.10 }
local COLOR_BAR_HERO  = { 0.40, 0.95, 0.50 }
local COLOR_BAR_MONS  = { 0.95, 0.40, 0.40 }

local RESTART_BTN = { x = 300, y = 380, w = 200, h = 50 }

local function draw_bar(entity, color)
    local px, py = grid.tile_to_pixel(entity.x, entity.y)
    local bar_x = px + (grid.TILE - BAR_W) / 2
    local bar_y = py + BAR_OFFSET_Y

    love.graphics.setColor(COLOR_BAR_BG)
    love.graphics.rectangle("fill", bar_x, bar_y, BAR_W, BAR_H)

    love.graphics.setColor(color)
    local fill = BAR_W * (entity.hp / entity.max_hp)
    love.graphics.rectangle("fill", bar_x, bar_y, fill, BAR_H)
end

function M.draw_hp_bars(game)
    -- HP only matters once the invasion is under way; hide bars during build
    -- to avoid drawing meaningless full bars on every freshly placed monster.
    if game.phase == state.PHASE_BUILD then return end

    for _, m in ipairs(game.monsters) do
        if m.alive then draw_bar(m, COLOR_BAR_MONS) end
    end
    if game.hero and game.hero.alive then
        draw_bar(game.hero, COLOR_BAR_HERO)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

function M.draw_hud(game)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(
        ("PHASE: %s    seed: %d    FPS: %d")
            :format(game.phase:upper(), game.seed, love.timer.getFPS()),
        8, 8)

    if game.phase == state.PHASE_BUILD then
        love.graphics.print(
            ("[1] goblin   [2] orc   [3] slime    selected: %s    placed: %d/%d")
                :format(game.selected_monster_type, #game.monsters, state.MAX_MONSTERS),
            8, 24)
    elseif game.phase == state.PHASE_INVASION and game.hero then
        love.graphics.print(
            ("hero: %s    HP %d/%d    ATK %d    range %d")
                :format(game.hero.class, game.hero.hp, game.hero.max_hp,
                    game.hero.atk, game.hero.range),
            8, 24)
    end

    love.graphics.print(
        "[SPACE] advance / step turn    [R] new run    [ESC] quit",
        8, 40)
end

function M.draw_result(game)
    if game.phase ~= state.PHASE_RESULT then return end

    love.graphics.setColor(0, 0, 0, 0.65)
    love.graphics.rectangle("fill", 0, 0,
        love.graphics.getWidth(), love.graphics.getHeight())

    local font = love.graphics.getFont()
    local title, color
    if game.outcome == state.OUTCOME_TREASURE_STOLEN then
        title = "TREASURE STOLEN"
        color = { 1.00, 0.55, 0.30 }
    elseif game.outcome == state.OUTCOME_HERO_DEAD then
        title = "HERO DEFEATED"
        color = { 0.50, 1.00, 0.60 }
    else
        title = "RUN OVER"
        color = { 0.85, 0.85, 0.85 }
    end

    love.graphics.setColor(color)
    local title_scale = 4
    local tw = font:getWidth(title) * title_scale
    love.graphics.print(title,
        (love.graphics.getWidth() - tw) / 2, 200,
        0, title_scale, title_scale)

    -- Restart button (hover highlight).
    local mx, my = love.mouse.getPosition()
    local hovered = M.is_restart_clicked(mx, my)

    love.graphics.setColor(hovered and { 0.45, 0.45, 0.65 } or { 0.30, 0.30, 0.50 })
    love.graphics.rectangle("fill",
        RESTART_BTN.x, RESTART_BTN.y, RESTART_BTN.w, RESTART_BTN.h)
    love.graphics.setColor(1, 1, 1)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line",
        RESTART_BTN.x, RESTART_BTN.y, RESTART_BTN.w, RESTART_BTN.h)
    love.graphics.setLineWidth(1)

    local btn_text = "RESTART"
    local btn_scale = 2
    local btw = font:getWidth(btn_text) * btn_scale
    local bth = font:getHeight() * btn_scale
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
