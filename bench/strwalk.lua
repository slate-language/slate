-- The Lua twin of strwalk.sl.
--
-- **LUA HAS NO CHARACTER INDEXING AND THIS IS THE IDIOMATIC SUBSTITUTE.** A Lua string is a byte
-- array: `s:sub(i, i)` is a constant-time read of one BYTE, which for this text would cut a
-- character into three. What `utf8` offers instead is `utf8.offset(s, n)`, the byte position where
-- the n-th character begins -- and it finds that by counting from the front, so the walk below is
-- quadratic in the length of the string exactly as slate's used to be.
--
-- **So Lua is NOT the yardstick on this benchmark**, which is the opposite of every other file here
-- and is a fact about Lua rather than about slate: the language that indexes bytes in constant time
-- has nothing that indexes characters in constant time at all. `utf8.len` counts from the front too,
-- so the loop bound is taken once into a local rather than being asked each turn -- which is the
-- fair reading, the slate program's `s.length` being one read of a number the string carries.
--
-- Positions are 1-based, so the walk runs from 1 to the character count.

local function run(s)
    local found = 0
    local n = utf8.len(s)
    local want = utf8.codepoint("本")

    for i = 1, n do
        if utf8.codepoint(s, utf8.offset(s, i)) == want then
            found = found + 1
        end
    end

    return found
end

local parts = {}

for _ = 1, 1000 do
    parts[#parts + 1] = "日本語あいうえおかきく" .. "さしすせそたちつてと"
end

print(run(table.concat(parts)))
