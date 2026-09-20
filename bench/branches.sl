// Ordinary decision-making code, of the kind real programs are mostly made of: a bare `if`, a
// three-way `if`/`elif`/`elif`/`else` chain with a nested `if` inside one of its arms, an early
// `continue`, a five-armed `match` on a small integer, an `if` used as an EXPRESSION whose value is
// read, and -- every thousandth turn -- a `try`/`catch` around a call that faults on a rare input.
//
// **Every other program in `bench/` is a straight-line loop.** Nineteen of the twenty-two have no
// `if`, `match` or `try` at all, so none of them can see a branch misprediction, a `match`'s arm
// search, or the cost `Tick` pays once per statement. This is the one benchmark that branches,
// dispatches and ticks the way ordinary code does, so a change to any of those three shows up here
// and nowhere else in the set.
//
// **The input is a small linear congruential generator written out in-program** (Park-Miller:
// `seed = seed * 16807 % (2^31 - 1)`), so every twin walks the identical deterministic sequence with
// no library random source to disagree about. `seed` and every value derived from it stay ordinary
// machine integers under 2^31, and the one product taken (`seed * 16807`, at most ~3.6e13) stays
// comfortably under 2^53 -- so slate's 64-bit integers, Lua's 64-bit integers, JavaScript's doubles
// and Python's arbitrary-precision integers all agree exactly, turn for turn. No division is used
// anywhere in the loop, so the truncating/floor-division difference between the four never comes up.

risky(r)
    if r == 0 then throw "boom"

    0

run()
    var seed = 1
    var i = 0
    var flag_count = 0
    var chain_total = 0
    var nested_count = 0
    var continue_count = 0
    var expr_sum = 0
    var match_total = 0
    var fault_count = 0

    while i < 2000000
        seed = (seed * 16807) % 2147483647

        val r = seed % 1000

        i = i + 1

        // a bare `if`, no `else`
        if r % 7 == 0
            flag_count = flag_count + 1

        // an `if`/`elif`/`elif`/`else` chain, with a nested `if` inside the first arm
        if r < 100
            chain_total = chain_total + 1

            if r % 13 == 0
                nested_count = nested_count + 1
        elif r < 400
            chain_total = chain_total + 2
        elif r < 700
            chain_total = chain_total + 3
        else
            chain_total = chain_total + 4

        // an early `continue`, taken about one turn in a hundred
        if r % 97 == 0
            continue_count = continue_count + 1
            continue

        // a `match` on a small integer: four explicit arms and a default
        val k = r % 5

        k match
            0 -> match_total = match_total + 10
            1 -> match_total = match_total + 20
            2 -> match_total = match_total + 30
            3 -> match_total = match_total + 40
            _ -> match_total = match_total + 50

        // an `if` used as an EXPRESSION, its value read rather than discarded
        val bonus = if r % 2 == 0 then 1 else 2

        expr_sum = expr_sum + bonus

        // every thousandth turn, a rare fault guarded by `try`/`catch` -- cheap and almost never
        // taken, so what this measures is the handler's set-up cost rather than the fault itself
        if i % 1000 == 0
            try
                fault_count = fault_count + risky(r)
            catch e
                fault_count = fault_count + 1

    flag_count + chain_total * 3 + nested_count * 7 + continue_count * 11 + expr_sum * 13 + match_total * 17 + fault_count * 19

print(run())
