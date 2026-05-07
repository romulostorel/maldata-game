-- Entry point: wires LÖVE callbacks to the game state and input router.

local render = require("src.render")
local state = require("src.state")
local input = require("src.input")

local BG_R, BG_G, BG_B = 26 / 255, 26 / 255, 46 / 255 -- #1a1a2e

local game

local function rand_seed()
    return math.random(1, 2147483646)
end

function love.load()
    love.graphics.setBackgroundColor(BG_R, BG_G, BG_B)
    love.graphics.setDefaultFilter("nearest", "nearest")
    love.keyboard.setKeyRepeat(false)

    math.randomseed(os.time())
    game = state.new(rand_seed())
end

function love.update(dt)
    -- Logic update hook. Future stages: state:update(dt).
end

function love.draw()
    render.draw_dungeon(game.dungeon)
    render.draw_monsters(game.monsters)
    render.draw_path(game)
    render.draw_hero(game.hero)
    render.draw_build_cursor(game)

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
    elseif game.phase == state.PHASE_RESULT then
        love.graphics.print(
            ("outcome: %s"):format(game.outcome or "?"),
            8, 24)
    end

    love.graphics.print(
        "[SPACE] advance / step turn    [R] new run    [ESC] quit",
        8, 40)
end

function love.keypressed(key)
    if key == "escape" then
        love.event.quit()
    elseif key == "space" then
        if game.phase == state.PHASE_INVASION then
            state.step_invasion(game)
        else
            state.advance(game)
        end
    elseif key == "r" then
        state.reset(game, rand_seed())
    else
        input.handle_key(game, key)
    end
end

function love.mousepressed(x, y, button)
    input.handle_mouse(game, x, y, button)
end
