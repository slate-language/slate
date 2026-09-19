-- The Lua twin of closures.sl. `scale` is an upvalue of `weigh`, which is Lua's own word for exactly
-- the thing slate keeps a scope for -- so of all the twins here this is the closest match in
-- mechanism as well as in shape.

local function run()
    local total, turns = 0, 0
    local scale = 3
    local weigh = function(v) return v * scale end

    while turns < 4000000 do
        total = total + weigh(turns)
        turns = turns + 1
    end

    return total
end

print(run())
