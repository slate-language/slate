-- The Lua twin of dispatch.sl.
--
-- **Lua has no `match`, so the twin is the chain of comparisons a Lua program writes.** A table
-- keyed by the word would be the faster Lua and a different measurement -- it would answer with one
-- hash where slate's `match` compares the subject against each arm in turn.
--
-- Lua interns short strings, so `==` between two of them is a pointer comparison rather than a walk.

local function kind(w)
    if w == "add" then return 1 end
    if w == "sub" then return 2 end
    if w == "mul" then return 3 end
    if w == "div" then return 4 end
    if w == "mod" then return 5 end

    return 0
end

local function run(words)
    local total, i = 0, 0

    while i < 5000000 do
        total = total + kind(words[i % 6 + 1])
        i = i + 1
    end

    return total
end

print(run({ "add", "sub", "mul", "div", "mod", "nope" }))
