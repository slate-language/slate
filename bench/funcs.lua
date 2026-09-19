-- The Lua twin of funcs.sl. The function is a local rather than a global, which is what a Lua
-- program writes and what keeps this a measurement of the call rather than of a table lookup --
-- globals.lua is where the lookup is measured.

local function add3(a, b, c)
    return a + b + c
end

local function run()
    local total, i = 0, 0

    while i < 4000000 do
        total = total + add3(i, 1, 2)
        i = i + 1
    end

    return total
end

print(run())
