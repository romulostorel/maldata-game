package.path = "./?.lua;./?/init.lua;" .. package.path

local monster = require("src.monster")

describe("monster", function()
    describe("TYPES", function()
        it("matches the v1 stat sheet", function()
            assert.are.equal(5,  monster.TYPES[monster.GOBLIN].hp)
            assert.are.equal(2,  monster.TYPES[monster.GOBLIN].atk)
            assert.are.equal(1,  monster.TYPES[monster.GOBLIN].range)
            assert.are.equal(2,  monster.TYPES[monster.GOBLIN].cost)

            assert.are.equal(10, monster.TYPES[monster.ORC].hp)
            assert.are.equal(4,  monster.TYPES[monster.ORC].atk)
            assert.are.equal(1,  monster.TYPES[monster.ORC].range)
            assert.are.equal(4,  monster.TYPES[monster.ORC].cost)

            assert.are.equal(8,  monster.TYPES[monster.SLIME].hp)
            assert.are.equal(3,  monster.TYPES[monster.SLIME].atk)
            assert.are.equal(1,  monster.TYPES[monster.SLIME].range)
            assert.are.equal(3,  monster.TYPES[monster.SLIME].cost)
        end)
    end)

    describe("new", function()
        it("creates an entity with full HP and the requested position", function()
            local m = monster.new(monster.GOBLIN, 5, 7)
            assert.are.equal(monster.GOBLIN, m.type)
            assert.are.equal(5, m.x)
            assert.are.equal(7, m.y)
            assert.are.equal(5, m.hp)
            assert.are.equal(5, m.max_hp)
            assert.are.equal(2, m.atk)
            assert.are.equal(1, m.range)
            assert.are.equal(2, m.cost)
            assert.is_true(m.alive)
        end)

        it("uses the requested type's stats", function()
            local orc = monster.new(monster.ORC, 1, 1)
            assert.are.equal(10, orc.hp)
            assert.are.equal(4, orc.atk)

            local slime = monster.new(monster.SLIME, 1, 1)
            assert.are.equal(8, slime.hp)
            assert.are.equal(3, slime.atk)
        end)
    end)

    describe("new_mini_slime", function()
        it("creates a smaller slime flagged as mini", function()
            local m = monster.new_mini_slime(4, 9)
            assert.are.equal(monster.SLIME, m.type)
            assert.are.equal(4, m.x); assert.are.equal(9, m.y)
            assert.are.equal(monster.MINI_SLIME.hp,  m.hp)
            assert.are.equal(monster.MINI_SLIME.hp,  m.max_hp)
            assert.are.equal(monster.MINI_SLIME.atk, m.atk)
            assert.are.equal(1, m.range)
            assert.are.equal(0, m.cost)
            assert.is_true(m.alive)
            assert.is_true(m.is_mini)
        end)

        it("uses smaller stats than the parent slime", function()
            assert.is_true(monster.MINI_SLIME.hp  < monster.TYPES[monster.SLIME].hp)
            assert.is_true(monster.MINI_SLIME.atk < monster.TYPES[monster.SLIME].atk)
        end)
    end)

    describe("effective_atk", function()
        it("returns base atk when goblin has no neighbors", function()
            local g = monster.new(monster.GOBLIN, 5, 5)
            assert.are.equal(g.atk, monster.effective_atk(g, { g }))
        end)

        it("adds GOBLIN_CLUSTER_BONUS per cardinal-adjacent alive goblin", function()
            local g  = monster.new(monster.GOBLIN, 5, 5)
            local n1 = monster.new(monster.GOBLIN, 5, 4)
            local n2 = monster.new(monster.GOBLIN, 6, 5)
            local list = { g, n1, n2 }
            assert.are.equal(g.atk + 2 * monster.GOBLIN_CLUSTER_BONUS,
                monster.effective_atk(g, list))
        end)

        it("ignores diagonal goblins", function()
            local g    = monster.new(monster.GOBLIN, 5, 5)
            local diag = monster.new(monster.GOBLIN, 6, 6)
            assert.are.equal(g.atk, monster.effective_atk(g, { g, diag }))
        end)

        it("ignores dead goblins", function()
            local g  = monster.new(monster.GOBLIN, 5, 5)
            local n1 = monster.new(monster.GOBLIN, 5, 4); n1.alive = false
            assert.are.equal(g.atk, monster.effective_atk(g, { g, n1 }))
        end)

        it("ignores non-goblin neighbors", function()
            local g  = monster.new(monster.GOBLIN, 5, 5)
            local o  = monster.new(monster.ORC,    5, 4)
            local s  = monster.new(monster.SLIME,  6, 5)
            assert.are.equal(g.atk, monster.effective_atk(g, { g, o, s }))
        end)

        it("returns base atk for non-goblin types regardless of neighbors", function()
            local o  = monster.new(monster.ORC, 5, 5)
            local n1 = monster.new(monster.GOBLIN, 5, 4)
            local n2 = monster.new(monster.ORC,    6, 5)
            assert.are.equal(o.atk, monster.effective_atk(o, { o, n1, n2 }))
        end)

        it("caps naturally at the four cardinal neighbors", function()
            local g  = monster.new(monster.GOBLIN, 5, 5)
            local n  = {}
            for _, p in ipairs({ { 5, 4 }, { 5, 6 }, { 4, 5 }, { 6, 5 } }) do
                table.insert(n, monster.new(monster.GOBLIN, p[1], p[2]))
            end
            local list = { g, n[1], n[2], n[3], n[4] }
            assert.are.equal(g.atk + 4 * monster.GOBLIN_CLUSTER_BONUS,
                monster.effective_atk(g, list))
        end)
    end)
end)
