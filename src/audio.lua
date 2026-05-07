-- Central audio API. The rest of the engine asks for sounds by name
-- (audio.play("ui_click")) — never touches sfx_gen or waveform directly.
--
-- audio.load() runs once at startup, generates every registered SFX with
-- sfx_gen, bakes a love.audio.Source per name, and pins its volume.
-- audio.play(name) clones the master Source so multiple instances of the
-- same SFX can overlap (LÖVE keeps a Source alive while it plays even when
-- no Lua reference holds it).
--
-- play() is a safe no-op when load() hasn't run — busted tests can require
-- this module without booting LÖVE's audio backend.

local sfx_gen  = require("src.gen.sfx_gen")
local waveform = require("src.gen.waveform")

local M = {}

-- Per-SFX bake recipe. `gen` returns a sample table; `volume` is the
-- master volume of the resulting Source (clones inherit it).
local SFX = {
    ui_hover         = { gen = sfx_gen.ui_hover,         volume = 0.30 },
    ui_click         = { gen = sfx_gen.ui_click,         volume = 0.55 },
    phase_transition = { gen = sfx_gen.phase_transition, volume = 0.70 },
    monster_place    = { gen = sfx_gen.monster_place,    volume = 0.65 },
    hero_footstep    = { gen = sfx_gen.hero_footstep,    volume = 0.20 },
    hero_attack      = { gen = sfx_gen.hero_attack,      volume = 0.50 },
    hit_impact       = { gen = sfx_gen.hit_impact,       volume = 0.55 },
}

local sources = {}

function M.load()
    for name, def in pairs(SFX) do
        local samples = def.gen()
        local src = waveform.to_source(samples, waveform.SAMPLE_RATE)
        src:setVolume(def.volume)
        sources[name] = src
    end
end

function M.play(name)
    local src = sources[name]
    if not src then return end
    src:clone():play()
end

return M
