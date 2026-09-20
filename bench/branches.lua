-- The Lua twin of branches.sl.
--
-- Lua has no `match`, so the twin is the same chain of comparisons `dispatch.lua` writes -- and no
-- `continue`, so the early exit is Lua's own idiom for it, a `goto` to a label at the bottom of the
-- loop body. `pcall` is Lua's `try`: it returns `true` plus the call's result on success and `false`
-- plus the error object on failure, and `error()` is `throw`.
--
-- Lua 5.5's integers are 64-bit, and every value here stays under 2^31 with the one product taken
-- (`seed * 16807`) under 2^53, so this is exact integer arithmetic throughout and prints the same
-- answer as the other three.

local function risky(r)
    if r == 0 then error("boom") end
    return 0
end

local function run()
    local seed = 1
    local i = 0
    local flag_count = 0
    local chain_total = 0
    local nested_count = 0
    local continue_count = 0
    local expr_sum = 0
    local match_total = 0
    local fault_count = 0

    while i < 2000000 do
        seed = (seed * 16807) % 2147483647

        local r = seed % 1000

        i = i + 1

        if r % 7 == 0 then
            flag_count = flag_count + 1
        end

        if r < 100 then
            chain_total = chain_total + 1

            if r % 13 == 0 then
                nested_count = nested_count + 1
            end
        elseif r < 400 then
            chain_total = chain_total + 2
        elseif r < 700 then
            chain_total = chain_total + 3
        else
            chain_total = chain_total + 4
        end

        if r % 97 == 0 then
            continue_count = continue_count + 1
            goto continue
        end

        do
            local k = r % 5

            if k == 0 then
                match_total = match_total + 10
            elseif k == 1 then
                match_total = match_total + 20
            elseif k == 2 then
                match_total = match_total + 30
            elseif k == 3 then
                match_total = match_total + 40
            else
                match_total = match_total + 50
            end

            local bonus
            if r % 2 == 0 then bonus = 1 else bonus = 2 end

            expr_sum = expr_sum + bonus
        end

        if i % 1000 == 0 then
            local ok, result = pcall(risky, r)

            if ok then
                fault_count = fault_count + result
            else
                fault_count = fault_count + 1
            end
        end

        ::continue::
    end

    return flag_count + chain_total * 3 + nested_count * 7 + continue_count * 11 +
        expr_sum * 13 + match_total * 17 + fault_count * 19
end

print(run())
