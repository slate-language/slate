-- The Lua twin of options.sl.
--
-- **Lua has neither destructuring nor a default, so the twin is `or`**, which is what a Lua program
-- writes. It is not quite the same rule: `or` takes the default for `false` as well as for absence,
-- where slate's pattern default takes it only where the key is missing. Every value here is a
-- number, so the two agree on this program.

local function sized(opts)
    local width = opts.width or 10
    local height = opts.height
    local scale = opts.scale or 2

    return width * height * scale
end

local function run(given, partial)
    local total, turns = 0, 0

    while turns < 2000000 do
        total = total + sized(given) + sized(partial)
        turns = turns + 1
    end

    return total
end

print(run({ width = 3, height = 4, scale = 5 }, { height = 4 }))
