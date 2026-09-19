-- The Lua twin of arith.sl. Lua 5.5 has a 64-bit integer subtype, so this stays integer arithmetic
-- exactly as slate's does and the answer prints without a decimal point.

local function run()
    local total, i = 0, 0

    while i < 10000000 do
        total = total + i * 2 - 1
        i = i + 1
    end

    return total
end

print(run())
