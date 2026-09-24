-- The LuaJIT twin of strwalk.sl, for the one program whose Lua twin LuaJIT cannot run.
--
-- **LuaJIT is Lua 5.1 and has no `utf8` library**, which strwalk.lua is written with, so it has no
-- way at all to reach the n-th character except by walking to it. Writing `utf8.offset` out in Lua
-- -- counting lead bytes from the front for every index, as strwalk.lua's C call does -- was tried
-- and took twelve seconds in the interpreter: the same quadratic walk, but in bytecode rather than
-- in C, which would make this row measure how slow an interpreted byte loop is rather than anything
-- the slate program does.
--
-- **So this twin keeps a byte CURSOR and steps it one character per turn**, which is what a LuaJIT
-- program walking UTF-8 writes. That makes it LINEAR -- the same amount of work as the Python and
-- JavaScript twins, whose index is constant time, and as slate, whose string remembers where it last
-- was -- where strwalk.lua is quadratic. A character is compared as the bytes it is made of, which is
-- what comparing code points amounts to for well-formed text. The count of characters, the loop's
-- bound, is taken once, as in strwalk.lua.
--
-- `run.sh` and `check.sh` run this file in place of strwalk.lua under `luajit`, and only there.

local byte = string.byte

-- How many bytes the character starting with lead byte `b` takes.
local function width(b)
    if b < 0x80 then
        return 1
    elseif b < 0xE0 then
        return 2
    elseif b < 0xF0 then
        return 3
    else
        return 4
    end
end

local function length(s)
    local n, p = 0, 1

    while p <= #s do
        p = p + width(byte(s, p))
        n = n + 1
    end

    return n
end

local function run(s)
    local found = 0
    local n = length(s)
    local want = "本"
    local p = 1

    for _ = 1, n do
        local w = width(byte(s, p))

        if s:sub(p, p + w - 1) == want then
            found = found + 1
        end

        p = p + w
    end

    return found
end

local parts = {}

for _ = 1, 1000 do
    parts[#parts + 1] = "日本語あいうえおかきく" .. "さしすせそたちつてと"
end

print(run(table.concat(parts)))
