-- Central audio API. The rest of the engine asks for sounds by name
-- (audio.play("ui_click")) — never touches sfx_gen or waveform directly.
--
-- audio.load() runs once at startup, generates every registered SFX with
-- sfx_gen, bakes one or more love.audio.Sources per name, and pins their
-- volume. SFX flagged with `variants = N` get N distinct bakes (different
-- jitter seeds), and audio.play picks one at random — kills auditory
-- fatigue on cues that fire repeatedly (footstep, attack, hit).
--
-- audio.play(name) clones the master Source so multiple instances can
-- overlap (LÖVE keeps a Source alive while it plays even when no Lua
-- reference holds it). It's a safe no-op when load() hasn't run — busted
-- tests can require this module without booting LÖVE's audio backend.

local sfx_gen  = require("src.gen.sfx_gen")
local waveform = require("src.gen.waveform")

local M = {}

-- Per-SFX bake recipe.
--   gen      — function(seed) returning a sample table.
--   volume   — master volume of the resulting Source (clones inherit it).
--   variants — optional integer; when set, audio.load bakes that many
--              distinct sources with different seeds and play() picks one
--              uniformly at random.
local SFX = {
    ui_hover               = { gen = sfx_gen.ui_hover,               volume = 0.30 },
    ui_click               = { gen = sfx_gen.ui_click,               volume = 0.55 },
    phase_transition       = { gen = sfx_gen.phase_transition,       volume = 0.70 },
    monster_place          = { gen = sfx_gen.monster_place,          volume = 0.65 },
    hero_footstep          = { gen = sfx_gen.hero_footstep,          volume = 0.20, variants = 4 },
    hero_attack            = { gen = sfx_gen.hero_attack,            volume = 0.50, variants = 3 },
    hit_impact             = { gen = sfx_gen.hit_impact,             volume = 0.55, variants = 3 },
    monster_attack_goblin  = { gen = sfx_gen.monster_attack_goblin,  volume = 0.50, variants = 3 },
    monster_attack_orc     = { gen = sfx_gen.monster_attack_orc,     volume = 0.55, variants = 3 },
    monster_attack_slime   = { gen = sfx_gen.monster_attack_slime,   volume = 0.50, variants = 3 },
    monster_death_goblin   = { gen = sfx_gen.monster_death_goblin,   volume = 0.65 },
    monster_death_orc      = { gen = sfx_gen.monster_death_orc,      volume = 0.70 },
    monster_death_slime    = { gen = sfx_gen.monster_death_slime,    volume = 0.65 },
    hero_death             = { gen = sfx_gen.hero_death,             volume = 0.75 },
    victory_sting          = { gen = sfx_gen.victory_sting,          volume = 0.65 },
    defeat_sting           = { gen = sfx_gen.defeat_sting,           volume = 0.65 },
}

-- Each entry in `sources` is an array of one or more Sources, even for
-- single-variant SFX, so play() doesn't need to branch on shape.
local sources = {}

-- Prime spacing keeps successive seeds far apart in the LCG state space,
-- so variants come out with audibly different noise textures.
local SEED_STEP = 7919

function M.load()
    for name, def in pairs(SFX) do
        local count = def.variants or 1
        local list = {}
        for i = 1, count do
            local seed = def.variants and (i * SEED_STEP) or nil
            local samples = def.gen(seed)
            local src = waveform.to_source(samples, waveform.SAMPLE_RATE)
            src:setVolume(def.volume)
            list[i] = src
        end
        sources[name] = list
    end
end

function M.play(name)
    local list = sources[name]
    if not list then return end
    local pick = list[math.random(1, #list)]
    pick:clone():play()
end

return M
