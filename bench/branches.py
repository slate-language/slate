# The Python twin of branches.sl.
#
# Python's `match`/`case`, like `dispatch.py`'s, is the same construct slate has -- a subject compared
# against literal patterns in order -- so this is a direct translation rather than a workaround.
# `continue` and `try`/`except` are Python's own words for the same thing, and the `if`-as-expression
# becomes Python's conditional expression, `a if cond else b`.
#
# Python's integers are arbitrary precision, so nothing here can overflow; the values are kept under
# 2^31 anyway so the four twins are doing arithmetic of the same shape.


def risky(r):
    if r == 0:
        raise ValueError("boom")

    return 0


def run():
    seed = 1
    i = 0
    flag_count = 0
    chain_total = 0
    nested_count = 0
    continue_count = 0
    expr_sum = 0
    match_total = 0
    fault_count = 0

    while i < 2000000:
        seed = (seed * 16807) % 2147483647

        r = seed % 1000

        i = i + 1

        if r % 7 == 0:
            flag_count = flag_count + 1

        if r < 100:
            chain_total = chain_total + 1

            if r % 13 == 0:
                nested_count = nested_count + 1
        elif r < 400:
            chain_total = chain_total + 2
        elif r < 700:
            chain_total = chain_total + 3
        else:
            chain_total = chain_total + 4

        if r % 97 == 0:
            continue_count = continue_count + 1
            continue

        k = r % 5

        match k:
            case 0:
                match_total = match_total + 10
            case 1:
                match_total = match_total + 20
            case 2:
                match_total = match_total + 30
            case 3:
                match_total = match_total + 40
            case _:
                match_total = match_total + 50

        bonus = 1 if r % 2 == 0 else 2

        expr_sum = expr_sum + bonus

        if i % 1000 == 0:
            try:
                fault_count = fault_count + risky(r)
            except ValueError:
                fault_count = fault_count + 1

    return (flag_count + chain_total * 3 + nested_count * 7 + continue_count * 11 +
            expr_sum * 13 + match_total * 17 + fault_count * 19)


print(run())
