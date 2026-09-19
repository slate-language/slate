-- The Lua twin of sorting.sl.
--
-- **`table.sort` sorts IN PLACE**, where slate's `sorted` answers a new array -- so the copy slate's
-- builtin makes is written out here, or the second turn would be sorting an already sorted array and
-- the two would not be doing the same work.
--
-- Lua's default comparison on numbers is `<`, which is slate's default too.

local function build(n)
    local xs, seed = {}, 1

    for i = 1, n do
        seed = (seed * 16807) % 2147483647
        xs[i] = seed
    end

    return xs
end

local function run()
    local xs = build(20000)
    local total, turns = 0, 0

    while turns < 200 do
        local ys = {}

        for i = 1, 20000 do
            ys[i] = xs[i]
        end

        table.sort(ys)

        total = total + ys[1] + ys[20000]
        turns = turns + 1
    end

    return total
end

print(run())
