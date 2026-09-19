-- The Lua twin of reals.sl. Lua's float subtype is a double, the same as slate's real, and `i * 1.5`
-- promotes the integer exactly as slate does.

local function run()
    local total, i = 0.0, 0

    while i < 10000000 do
        total = total + i * 1.5 - 0.5
        i = i + 1
    end

    return total
end

print(string.format("%.1f", run()))
