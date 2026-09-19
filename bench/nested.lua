-- The Lua twin of nested.sl: loops.lua's loop inside a function that also holds a closure over one
-- of its names. The pair is taken apart by index for loops.lua's reason.

local function run(pairs_)
    local total, turns = 0, 0
    local scale = 1
    local weigh = function(v) return v * scale end

    while turns < 6000 do
        for _, p in ipairs(pairs_) do
            total = total + weigh(p[1] * p[2])
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
