-- The Lua twin of strindex.sl.
--
-- **A Lua string is a byte array and `s:sub(i, i)` is a constant-time read**, so this walk is linear
-- where slate's is quadratic. It is also the twin that differs most in what it MEANS: Lua indexes
-- bytes and slate indexes characters, which are the same thing only because this text is ASCII.
--
-- Positions are 1-based, so the walk runs from 1 to #s rather than from 0.

local function run(s)
    local found, i = 0, 1

    while i <= #s do
        if s:sub(i, i) == "x" then
            found = found + 1
        end

        i = i + 1
    end

    return found
end

local parts = {}

for _ = 1, 1000 do
    parts[#parts + 1] = "abcdexfghi" .. "jklmnxopqr"
end

print(run(table.concat(parts)))
