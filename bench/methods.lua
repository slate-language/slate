-- The Lua twin of methods.sl.
--
-- **Lua has no class, so the twin is the metatable idiom** -- a table of methods reached through
-- `__index`, which is one indirection exactly as slate's proto chain is. `a:dot(b)` is the call
-- syntax that passes the receiver, which is what slate's `self` parameter takes.

local Vec = {}

Vec.__index = Vec

function Vec.new(x, y)
    return setmetatable({ x = x, y = y }, Vec)
end

function Vec:dot(o)
    return self.x * o.x + self.y * o.y
end

function Vec:scaled(k)
    return self.x * k + self.y * k
end

local function run()
    local a, b = Vec.new(2, 3), Vec.new(5, 7)
    local total, i = 0, 0

    while i < 3000000 do
        total = total + a:dot(b) + b:scaled(1)
        i = i + 1
    end

    return total
end

print(run())
