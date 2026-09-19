-- The Lua twin of strings.sl.
--
-- **THE IDIOMATIC LUA IS `table.concat` AND THIS IS DELIBERATELY NOT THAT.** A Lua string is
-- immutable, so `out = out .. x` copies the whole string on every turn and the loop is quadratic --
-- which is exactly what the slate program does and exactly what this file is here to compare. A
-- buffer and one join at the end is what a Lua program should be written with and is a different
-- measurement.
--
-- `#out` counts bytes and slate's `.length` counts characters; the text is ASCII, so they agree.

local function run()
    local out, i = "", 0

    while i < 150000 do
        out = out .. "x" .. (i % 10)
        i = i + 1
    end

    return #out
end

print(run())
