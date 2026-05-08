-- Active visual-effect registry. Spawn from main.lua's combat hook, then
-- update + draw each frame. Effects are cosmetic — losing one to a phase
-- transition or game reset is fine, hence the simple list-and-cull design.
--
-- Spawn helpers take tile coords (matching how callers think) and resolve
-- to pixel centers internally.

local grid       = require("src.grid")
local effect_gen = require("src.gen.effect_gen")

local M = {}

local list = {}

local function tile_center(tx, ty)
    local px, py = grid.tile_to_pixel(tx, ty)
    return px + grid.TILE / 2, py + grid.TILE / 2
end

function M.clear()
    list = {}
end

function M.spawn_hit(tx, ty)
    local cx, cy = tile_center(tx, ty)
    list[#list + 1] = effect_gen.new_hit_burst(cx, cy)
end

function M.spawn_scatter(tx, ty)
    local cx, cy = tile_center(tx, ty)
    list[#list + 1] = effect_gen.new_death_scatter(cx, cy)
end

function M.spawn_damage(tx, ty, amount, color)
    local cx, cy = tile_center(tx, ty)
    list[#list + 1] = effect_gen.new_damage_popup(cx, cy, amount, color)
end

-- Travelling projectile from one tile center to another. kind ∈
-- {"arrow", "bolt"} drives the visual (Archer/Mage respectively). Spawn
-- only for the FIRST swing of an attacker per tick — splash hits already
-- get hit bursts + damage popups, and adding a projectile for each one
-- would visually flood the AoE moment.
function M.spawn_projectile(from_tx, from_ty, to_tx, to_ty, kind)
    local fx, fy = tile_center(from_tx, from_ty)
    local tx, ty = tile_center(to_tx, to_ty)
    list[#list + 1] = effect_gen.new_projectile(fx, fy, tx, ty, kind)
end

function M.update(dt)
    local i = 1
    while i <= #list do
        local e = list[i]
        e.t = e.t + dt
        if e.t >= e.life then
            table.remove(list, i)
        else
            i = i + 1
        end
    end
end

function M.draw()
    for _, e in ipairs(list) do
        e.draw(e)
    end
end

return M
