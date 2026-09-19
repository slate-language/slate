-- The Lua twin of alloc.sl. A table with two named fields is what slate's `{ x: i, y: i + 1 }` is,
-- and Lua's incremental collector is what has to take it away again.

local function run()
    local total, i = 0, 0

    while i < 3000000 do
        local p = { x = i, y = i + 1 }

        total = total + p.x + p.y
        i = i + 1
    end

    return total
end

print(run())
