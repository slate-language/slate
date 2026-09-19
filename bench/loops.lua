-- The Lua twin of loops.sl.
--
-- **Lua has no destructuring in a loop head**, so the pair is taken apart by two index reads -- which
-- is what a Lua program writes and is strictly less work than slate's pattern match per turn. The
-- difference is named here rather than hidden by rewriting the slate side, the destructuring head
-- being the shape ordinary slate code has.

local function run(pairs_)
    local total, turns = 0, 0

    while turns < 8000 do
        for _, p in ipairs(pairs_) do
            total = total + p[1] * p[2]
        end

        turns = turns + 1
    end

    return total
end

local pairs_ = {}

for i = 0, 999 do
    pairs_[#pairs_ + 1] = { i, i + 1 }
end

print(run(pairs_))
