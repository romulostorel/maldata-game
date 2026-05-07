package.path = "./?.lua;./?/init.lua;" .. package.path

local hero = require("src.hero")
local rand = require("src.rand")

describe("hero", function()
    describe("CLASSES", function()
        it("matches the v1 stat sheet", function()
            local w = hero.CLASSES[hero.WARRIOR]
            assert.are.equal(15, w.hp); assert.are.equal(3, w.hp_var)
            assert.are.equal(4,  w.atk); assert.are.equal(1, w.atk_var)
            assert.are.equal(1,  w.range)

            local a = hero.CLASSES[hero.ARCHER]
            assert.are.equal(10, a.hp); assert.are.equal(2, a.hp_var)
            assert.are.equal(5,  a.atk); assert.are.equal(1, a.atk_var)
            assert.are.equal(1,  a.range)

            local m = hero.CLASSES[hero.MAGE]
            assert.are.equal(8, m.hp); assert.are.equal(2, m.hp_var)
            assert.are.equal(6, m.atk); assert.are.equal(2, m.atk_var)
            assert.are.equal(1, m.range)
        end)
    end)

    describe("new", function()
        it("places the hero at the requested tile and starts alive at full HP", function()
            local h = hero.new(rand.new(1), 5, 7)
            assert.are.equal(5, h.x)
            assert.are.equal(7, h.y)
            assert.is_true(h.alive)
            assert.are.equal(h.max_hp, h.hp)
        end)

        it("rolls a known class and stays within the variance band", function()
            -- Sample a few seeds and verify hp/atk fall inside [base-var, base+var].
            for seed = 1, 50 do
                local h = hero.new(rand.new(seed), 1, 1)
                local c = hero.CLASSES[h.class]
                assert.is_not_nil(c, "unknown class: " .. tostring(h.class))
                assert.is_true(h.hp >= c.hp - c.hp_var and h.hp <= c.hp + c.hp_var,
                    ("seed=%d class=%s hp=%d outside [%d,%d]")
                        :format(seed, h.class, h.hp, c.hp - c.hp_var, c.hp + c.hp_var))
                assert.is_true(h.atk >= c.atk - c.atk_var and h.atk <= c.atk + c.atk_var,
                    ("seed=%d class=%s atk=%d outside [%d,%d]")
                        :format(seed, h.class, h.atk, c.atk - c.atk_var, c.atk + c.atk_var))
                assert.are.equal(c.range, h.range)
            end
        end)

        it("is deterministic given the same rand stream", function()
            local h1 = hero.new(rand.new(7), 1, 1)
            local h2 = hero.new(rand.new(7), 1, 1)
            assert.are.equal(h1.class, h2.class)
            assert.are.equal(h1.hp, h2.hp)
            assert.are.equal(h1.atk, h2.atk)
        end)

        it("samples all three classes across enough seeds", function()
            local seen = {}
            for seed = 1, 60 do
                seen[hero.new(rand.new(seed), 1, 1).class] = true
            end
            assert.is_true(seen[hero.WARRIOR], "warrior not rolled in 60 seeds")
            assert.is_true(seen[hero.ARCHER],  "archer not rolled in 60 seeds")
            assert.is_true(seen[hero.MAGE],    "mage not rolled in 60 seeds")
        end)
    end)
end)
