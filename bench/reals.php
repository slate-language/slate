<?php
// The PHP twin of reals.sl. A PHP float is a double and `$i * 1.5` promotes the int, so the
// arithmetic is the same sequence of operations on the same values. `echo` of a float prints
// fourteen significant digits in exponent form at this size, so the answer is formatted explicitly.

function run()
{
    $total = 0.0;
    $i = 0;

    while ($i < 10000000) {
        $total = $total + $i * 1.5 - 0.5;
        $i = $i + 1;
    }

    return $total;
}

printf("%.1f\n", run());
