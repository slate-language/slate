<?php
// The PHP twin of arith.sl. A PHP int is 64 bits, as slate's integer is -- but where slate wraps,
// PHP silently turns an overflowing int into a float. Nothing here comes near 2^63.

function run()
{
    $total = 0;
    $i = 0;

    while ($i < 10000000) {
        $total = $total + $i * 2 - 1;
        $i = $i + 1;
    }

    return $total;
}

echo run(), "\n";
