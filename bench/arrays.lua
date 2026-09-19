-- The Lua twin of arrays.sl.
--
-- Lua has no array separate from its table, so `xs[#xs + 1] = v` is the push and `ipairs` is the
-- walk -- both what a Lua program writes. Positions are 1-based, so the index walk runs from 1.

local function build(n)
    local xs = {}
    local i = 0

    while i < n do
        xs[#xs + 1] = i * 2
        i = i + 1
    end

    return xs
end

local function by_index(xs)
    local total, i = 0, 1

    while i <= #xs do
        total = total + xs[i]
        i = i + 1
    end

    return total
end

local function by_walk(xs)
    local total = 0

    for _, v in ipairs(xs) do
        total = total + v
    end

    return total
end

local function run()
    local xs = build(500000)
    local total, turns = 0, 0

    while turns < 10 do
        total = total + by_index(xs) + by_walk(xs)
        turns = turns + 1
    end

    return total
end

print(run())
