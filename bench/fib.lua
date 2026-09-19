-- The Lua twin of fib.sl. `local function` rather than `local fib = function` so the name is in
-- scope inside its own body, which is what makes the recursion work in Lua.

local function fib(n)
    if n < 2 then
        return n
    end

    return fib(n - 1) + fib(n - 2)
end

print(fib(33))
