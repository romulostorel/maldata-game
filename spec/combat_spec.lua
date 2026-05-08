package.path = "./?.lua;./?/init.lua;" .. package.path

local combat = require("src.combat")

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
