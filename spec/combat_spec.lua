package.path = "./?.lua;./?/init.lua;" .. package.path

local combat  = require("src.combat")
local dungeon = require("src.dungeon")

-- Build a minimal dungeon-shaped table for LoS tests: a fixed-size open
-- floor grid that the test then walls a specific tile of. Avoids pulling
-- in the procgen and the seeded RNG just to ask "is this 5x5 patch
-- passable?".
local function open_dungeon(w, h)
    local g = {}
    for y = 1, h do
        g[y] = {}
        for x = 1, w do g[y][x] = dungeon.FLOOR end
    end
    return { grid = g }
end

local function actor(x, y, atk, range)
    return {
        x = x, y = y,
        atk = atk or 1,
        range = range or 1,
        hp = 10, max_hp = 10,
        alive = true,
    }
end

describe("combat", function()
    describe("in_range", function()
        it("counts the four cardinal neighbors at range 1", function()
            local a = actor(5, 5, 1, 1)
            assert.is_true(combat.in_range(a, actor(5, 4)))
            assert.is_true(combat.in_range(a, actor(6, 5)))
            assert.is_true(combat.in_range(a, actor(5, 6)))
            assert.is_true(combat.in_range(a, actor(4, 5)))
        end)

        it("excludes diagonals at range 1 (manhattan, not chebyshev)", function()
            local a = actor(5, 5, 1, 1)
            assert.is_false(combat.in_range(a, actor(6, 6)))
            assert.is_false(combat.in_range(a, actor(4, 4)))
            assert.is_false(combat.in_range(a, actor(6, 4)))
        end)

        it("includes ranged tiles up to attacker.range", function()
            local a = actor(5, 5, 1, 3)
            assert.is_true(combat.in_range(a, actor(5, 8)))   -- 3 down
            assert.is_true(combat.in_range(a, actor(8, 5)))   -- 3 right
            assert.is_true(combat.in_range(a, actor(7, 6)))   -- 2 + 1 = 3
            assert.is_false(combat.in_range(a, actor(8, 6)))  -- 3 + 1 = 4
        end)

        it("treats same tile as in range", function()
            local a = actor(5, 5, 1, 1)
            assert.is_true(combat.in_range(a, actor(5, 5)))
        end)

        describe("wall LoS for ranged attacks (range >= 2)", function()
            it("a wall on the cardinal line blocks the shot", function()
                local d = open_dungeon(10, 10)
                local a = actor(5, 5, 1, 2)
                local t = actor(5, 7)
                assert.is_true(combat.in_range(a, t, d), "open shot should land")
                d.grid[6][5] = dungeon.WALL
                assert.is_false(combat.in_range(a, t, d),
                    "wall between attacker and target must block ranged shot")
            end)

            it("a clear cardinal line stays in range when LoS is checked", function()
                local d = open_dungeon(10, 10)
                local a = actor(5, 5, 1, 2)
                assert.is_true(combat.in_range(a, actor(7, 5), d))
                assert.is_true(combat.in_range(a, actor(3, 5), d))
                assert.is_true(combat.in_range(a, actor(5, 3), d))
            end)

            it("diagonal manhattan-2 needs only ONE clear L-corner", function()
                local d = open_dungeon(10, 10)
                local a = actor(5, 5, 1, 2)
                local t = actor(6, 6)
                -- Wall one of the two corners — the OTHER L-path still
                -- offers a clear shot.
                d.grid[5][6] = dungeon.WALL
                assert.is_true(combat.in_range(a, t, d),
                    "diagonal shot routes through the still-open corner")
                -- Wall the second corner too — now the target is sealed.
                d.grid[6][5] = dungeon.WALL
                assert.is_false(combat.in_range(a, t, d),
                    "both corners walled = target is in a pocket")
            end)

            it("LoS check is skipped when no dungeon arg is passed", function()
                -- Backward-compat: monsters and old callers don't know
                -- about LoS — they reach adjacent targets unconditionally.
                local a = actor(5, 5, 1, 1)
                assert.is_true(combat.in_range(a, actor(6, 5)))
            end)

            it("range 1 (melee) ignores LoS — adjacency is unconditional", function()
                -- Even passing a dungeon, a melee attacker still reaches
                -- any cardinal-adjacent tile. There's no "between" cell
                -- at d=1 to obstruct, so the LoS branch is short-circuited.
                local d = open_dungeon(10, 10)
                local a = actor(5, 5, 1, 1)
                assert.is_true(combat.in_range(a, actor(6, 5), d))
                assert.is_true(combat.in_range(a, actor(5, 6), d))
            end)
        end)
    end)

    describe("attack", function()
        it("subtracts attacker.atk from target.hp", function()
            local a = actor(0, 0, 3)
            local t = actor(0, 0); t.hp = 10
            combat.attack(a, t)
            assert.are.equal(7, t.hp)
            assert.is_true(t.alive)
        end)

        it("clamps hp to 0 and marks the target dead on a lethal hit", function()
            local a = actor(0, 0, 50)
            local t = actor(0, 0); t.hp = 10
            combat.attack(a, t)
            assert.are.equal(0, t.hp)
            assert.is_false(t.alive)
        end)

        it("kills exactly when hp reaches 0", function()
            local a = actor(0, 0, 5)
            local t = actor(0, 0); t.hp = 5
            combat.attack(a, t)
            assert.are.equal(0, t.hp)
            assert.is_false(t.alive)
        end)

        it("does not modify the attacker", function()
            local a = actor(0, 0, 3)
            local t = actor(0, 0); t.hp = 10
            local snapshot = { hp = a.hp, atk = a.atk, range = a.range, alive = a.alive }
            combat.attack(a, t)
            assert.are.same(snapshot,
                { hp = a.hp, atk = a.atk, range = a.range, alive = a.alive })
        end)

        it("uses the explicit damage override when provided", function()
            local a = actor(0, 0, 3)
            local t = actor(0, 0); t.hp = 10
            combat.attack(a, t, 7)
            assert.are.equal(3, t.hp)
        end)

        it("returns the dealt damage (passive-aware caller can route it on)", function()
            local a = actor(0, 0, 3)
            local t = actor(0, 0); t.hp = 10
            assert.are.equal(3, combat.attack(a, t))
            assert.are.equal(5, combat.attack(a, t, 5))
        end)
    end)
end)
