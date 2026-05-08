-- Renders the game into a fixed 800×600 canvas, then blits the canvas into
-- the actual window scaled and centered. All draw and hit-test code stays
-- in canvas coordinates; this module owns the canvas <-> window transform
-- and recomputes it on resize / fullscreen toggle.
--
-- main.lua wires the lifecycle: init() once love.graphics is alive, then
-- recompute_layout() on resize. UI and render code reads mouse coords via
-- mouse_position() so hover/click checks see canvas coords directly.

local M = {}

M.CANVAS_W = 800
M.CANVAS_H = 600

local canvas    = nil
local scale     = 1
local offset_x  = 0
local offset_y  = 0

function M.init()
    canvas = love.graphics.newCanvas(M.CANVAS_W, M.CANVAS_H)
    canvas:setFilter("nearest", "nearest")
    M.recompute_layout()
end

-- Picks the largest fractional scale that fits the current window while
-- preserving the canvas aspect, then centers the canvas (letterbox bars on
-- the long side). Pixel art tolerates the fractional scale because the
-- canvas itself is rendered at integer pixel positions; only the final
-- blit uses sub-pixel sampling.
function M.recompute_layout()
    local ww, wh = love.graphics.getDimensions()
    scale = math.max(1, math.min(ww / M.CANVAS_W, wh / M.CANVAS_H))
    offset_x = math.floor((ww - M.CANVAS_W * scale) / 2)
    offset_y = math.floor((wh - M.CANVAS_H * scale) / 2)
end

function M.canvas() return canvas end
function M.scale()  return scale  end
function M.offset() return offset_x, offset_y end

-- Convert window-space coords (e.g. love.mousepressed args, OS cursor) to
-- canvas-space coords used everywhere else in the project.
function M.window_to_canvas(wx, wy)
    return (wx - offset_x) / scale, (wy - offset_y) / scale
end

function M.mouse_position()
    return M.window_to_canvas(love.mouse.getPosition())
end

-- Initial windowed size: largest integer scale that fits ~85% of desktop.
-- Integer keeps pixels perfectly square at boot; user-driven resize and
-- fullscreen fall back to fractional via recompute_layout.
function M.suggest_initial_size()
    local dw, dh = love.window.getDesktopDimensions()
    local s = math.max(1, math.min(
        math.floor(dw * 0.90 / M.CANVAS_W),
        math.floor(dh * 0.85 / M.CANVAS_H)
    ))
    return M.CANVAS_W * s, M.CANVAS_H * s
end

return M
