-- The Lua twin of globals.sl: arith.sl's loop with every name a GLOBAL rather than a local.
--
-- A Lua global is a key in the environment table, so this is a hash lookup per access where the
-- local version is a register read -- the same margin slate's module-level bindings sit at.

total = 0
i = 0

while i < 6000000 do
    total = total + i * 2 - 1
    i = i + 1
end

print(total)
