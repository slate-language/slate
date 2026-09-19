-- The Lua twin of fields.sl. A Lua table's named field IS a hash entry, which is what slate's object
-- field is too -- so this is the closest correspondence of any benchmark here.

local function run()
    local o = { a = 0, b = 1, c = 2 }
    local i = 0

    while i < 5000000 do
        o.a = o.a + o.b + o.c
        i = i + 1
    end

    return o.a
end

print(run())
