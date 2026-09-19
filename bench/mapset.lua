-- The Lua twin of mapset.sl.
--
-- **Lua has neither a map type nor a set type: it has the table, and both are written with it.** So
-- the map is `m[k] = v` and the set is `s[k] = true`, which is the idiom every Lua program uses --
-- and it is a genuinely smaller amount of work than slate does, slate's `Map` hashing structurally
-- and consulting a class's own `==` where Lua compares keys by value or by reference.

local function run()
    local m, s, i = {}, {}, 0

    while i < 2000000 do
        m[i % 1000] = i
        s[i % 1000] = true
        i = i + 1
    end

    local total, k = 0, 0

    while k < 1000 do
        total = total + m[k]

        if s[k] then
            total = total + 1
        end

        k = k + 1
    end

    return total
end

print(run())
