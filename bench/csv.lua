-- The Lua twin of csv.sl.
--
-- **Lua has no `split`**, so both splits are `gmatch` over a pattern, which is what a Lua program
-- writes. That is a real difference in KIND rather than in speed: slate and the other two call a
-- builtin that answers an array, and Lua runs a pattern matcher and iterates what it yields.
--
-- `tonumber` is the conversion and `#s` the length, which is bytes here and characters in slate --
-- the same number, this text being ASCII.

local function build(rows)
    local lines = {}

    for i = 0, rows - 1 do
        lines[#lines + 1] = i .. "," .. (i * 2) .. ",name" .. (i % 100)
    end

    return table.concat(lines, "\n")
end

local function parse(text)
    local total = 0

    for line in text:gmatch("[^\n]+") do
        local parts = {}

        for part in line:gmatch("[^,]+") do
            parts[#parts + 1] = part
        end

        total = total + tonumber(parts[1]) + tonumber(parts[2]) + #parts[3]
    end

    return total
end

local function run()
    local text = build(20000)
    local total, turns = 0, 0

    while turns < 30 do
        total = total + parse(text)
        turns = turns + 1
    end

    return total
end

print(run())
