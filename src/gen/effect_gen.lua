-- Visual effect factories. Each `new_*` returns a self-contained effect
-- table with `t`, `life`, and a `draw(self)` closure. The effects.lua
-- registry advances `t` and removes them when `t >= life`.
--
-- Effects use love.math.random for per-spawn variety — they're cosmetic and
-- don't need to be reproducible from a seed (gameplay determinism is
-- preserved by state.lua / combat.lua, which never call into here).

local palette = require("src.palette")

local M = {}

local function jitter(amount)
    return (love.math.random() - 0.5) * amount
end

-- Hit burst: a small ring of paper-colored sparks racing outward, fading
-- linearly. ~0.3 s total, easy on the eye, signals "the hit landed".
function M.new_hit_burst(cx, cy)
    local count = 7
    local particles = {}
    for i = 1, count do
        local angle = (i - 1) / count * math.pi * 2 + jitter(0.4)
        local speed = 70 + love.math.random() * 50
        particles[i] = {
            ox = cx, oy = cy,
            vx = math.cos(angle) * speed,
            vy = math.sin(angle) * speed,
        }
    end
    return {
        kind = "hit",
        t = 0,
        life = 0.30,
        particles = particles,
        draw = function(self)
            local fade = 1 - self.t / self.life
            love.graphics.setColor(palette.paper[1], palette.paper[2], palette.paper[3], fade)
            for _, p in ipairs(self.particles) do
                local px = p.ox + p.vx * self.t
                local py = p.oy + p.vy * self.t
                love.graphics.rectangle("fill", math.floor(px), math.floor(py), 2, 2)
            end
            love.graphics.setColor(1, 1, 1, 1)
        end,
    }
end

local SCATTER_COLORS = {
    palette.stone_light,
    palette.stone,
    palette.bone,
}

-- Death scatter: more particles than the hit burst, slight upward bias,
-- gravity pulling them back down. Reads as "the body broke apart in a puff".
function M.new_death_scatter(cx, cy)
    local count = 14
    local particles = {}
    for i = 1, count do
        local angle = (i - 1) / count * math.pi * 2 + jitter(0.6)
        local speed = 40 + love.math.random() * 50
        particles[i] = {
            ox = cx + jitter(6),
            oy = cy + jitter(6),
            vx = math.cos(angle) * speed,
            vy = math.sin(angle) * speed - 30,
            color = SCATTER_COLORS[((i - 1) % #SCATTER_COLORS) + 1],
        }
    end
    return {
        kind = "death",
        t = 0,
        life = 0.55,
        particles = particles,
        draw = function(self)
            local fade = 1 - self.t / self.life
            for _, p in ipairs(self.particles) do
                local px = p.ox + p.vx * self.t
                local py = p.oy + p.vy * self.t + 110 * self.t * self.t  -- gravity
                love.graphics.setColor(p.color[1], p.color[2], p.color[3], fade)
                love.graphics.rectangle("fill", math.floor(px), math.floor(py), 2, 2)
            end
            love.graphics.setColor(1, 1, 1, 1)
        end,
    }
end

-- Damage number popup: integer text rises ~30 px and holds full alpha for
-- the first 70% of life, then fades. Color is per-target (caller decides):
-- typically blood for hero damage, paper for monster damage.
function M.new_damage_popup(cx, cy, amount, color)
    color = color or palette.blood
    return {
        kind = "damage",
        t = 0,
        life = 0.80,
        cx = cx + jitter(6),  -- slight x-jitter so stacked hits don't overlap perfectly
        cy = cy,
        amount = amount,
        color = color,
        draw = function(self)
            local progress = self.t / self.life
            local fade
            if progress < 0.7 then
                fade = 1
            else
                fade = 1 - (progress - 0.7) / 0.3
            end
            local rise = 30 * progress
            local font = love.graphics.getFont()
            local text = tostring(self.amount)
            local scale = 2
            local tw = font:getWidth(text) * scale
            local th = font:getHeight() * scale
            local x = self.cx - tw / 2
            local y = self.cy - th / 2 - 14 - rise

            love.graphics.setColor(palette.void[1], palette.void[2], palette.void[3], fade * 0.9)
            love.graphics.print(text, x + 1, y + 1, 0, scale, scale)

            love.graphics.setColor(self.color[1], self.color[2], self.color[3], fade)
            love.graphics.print(text, x, y, 0, scale, scale)

            love.graphics.setColor(1, 1, 1, 1)
        end,
    }
end

return M
