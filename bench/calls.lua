-- The Lua twin of calls.sl: a method call that allocates, once per iteration.
--
-- The metatable idiom stands in for slate's `class`, as in methods.lua; what is measured here that
-- methods.lua leaves out is the `setmetatable` and the table it makes on every turn.

local Counter = {}

Counter.__index = Counter

function Counter.new(n)
    return setmetatable({ n = n }, Counter)
end

function Counter:bump(by)
    return Counter.new(self.n + by)
end

local function run()
    local c, i = Counter.new(0), 0

    while i < 2000000 do
        c = c:bump(1)
        i = i + 1
    end

    return c.n
end

print(run())
