package.path = "./?.lua;./?/init.lua;" .. package.path

local rand = require("src.rand")

describe("rand", function()
    it("returns integers in 1..n inclusive", function()
        local r = rand.new(1)
        for _ = 1, 100 do
            local v = r(7)
            assert.is_true(v >= 1 and v <= 7)
            assert.are.equal(math.floor(v), v)
        end
    end)

    it("is deterministic given the same seed", function()
        local a, b = rand.new(42), rand.new(42)
        for _ = 1, 50 do
            assert.are.equal(a(1000000), b(1000000))
        end
    end)

    it("produces independent streams from different seeds", function()
        local a, b = rand.new(1), rand.new(2)
        local diff = false
        for _ = 1, 10 do
            if a(1000000) ~= b(1000000) then diff = true; break end
        end
        assert.is_true(diff, "streams from different seeds collided 10 times in a row")
    end)

    it("handles seed=0 and negative seeds without erroring", function()
        assert.has_no.errors(function() rand.new(0)(10) end)
        assert.has_no.errors(function() rand.new(-1)(10) end)
        assert.has_no.errors(function() rand.new(-12345)(10) end)
    end)

    it("each rand.new() returns a fresh independent stream", function()
        local a = rand.new(7)
        a(1000); a(1000); a(1000)
        local b = rand.new(7) -- new instance, same seed: starts from scratch
        assert.are.equal(rand.new(7)(1000), b(1000))
    end)
end)
