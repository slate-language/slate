<?php
// The PHP twin of branches.sl.
//
// The five-armed `match` is a `switch`, because each arm is a statement here and PHP's own `match` is
// an expression; a `switch` over integer literals compiles to a jump table. `continue` and
// `try`/`catch` are PHP's own words, and the `if`-as-expression is the conditional operator.
// PHP's ints are 64 bits and the values stay under 2^31, so nothing here overflows.

function risky($r)
{
    if ($r === 0) {
        throw new Exception("boom");
    }

    return 0;
}

function run()
{
    $seed = 1;
    $i = 0;
    $flag_count = 0;
    $chain_total = 0;
    $nested_count = 0;
    $continue_count = 0;
    $expr_sum = 0;
    $match_total = 0;
    $fault_count = 0;

    while ($i < 2000000) {
        $seed = ($seed * 16807) % 2147483647;

        $r = $seed % 1000;

        $i = $i + 1;

        if ($r % 7 === 0) {
            $flag_count = $flag_count + 1;
        }

        if ($r < 100) {
            $chain_total = $chain_total + 1;

            if ($r % 13 === 0) {
                $nested_count = $nested_count + 1;
            }
        } elseif ($r < 400) {
            $chain_total = $chain_total + 2;
        } elseif ($r < 700) {
            $chain_total = $chain_total + 3;
        } else {
            $chain_total = $chain_total + 4;
        }

        if ($r % 97 === 0) {
            $continue_count = $continue_count + 1;
            continue;
        }

        $k = $r % 5;

        switch ($k) {
            case 0:
                $match_total = $match_total + 10;
                break;
            case 1:
                $match_total = $match_total + 20;
                break;
            case 2:
                $match_total = $match_total + 30;
                break;
            case 3:
                $match_total = $match_total + 40;
                break;
            default:
                $match_total = $match_total + 50;
        }

        $bonus = $r % 2 === 0 ? 1 : 2;

        $expr_sum = $expr_sum + $bonus;

        if ($i % 1000 === 0) {
            try {
                $fault_count = $fault_count + risky($r);
            } catch (Exception $e) {
                $fault_count = $fault_count + 1;
            }
        }
    }

    return $flag_count + $chain_total * 3 + $nested_count * 7 + $continue_count * 11 +
        $expr_sum * 13 + $match_total * 17 + $fault_count * 19;
}

echo run(), "\n";
