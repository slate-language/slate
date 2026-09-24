<?php
// The PHP twin of funcs.sl. A function declared in the file is bound when the file is compiled, so
// `add3` at the call site is resolved once and cached rather than looked up per call.

function add3($a, $b, $c)
{
    return $a + $b + $c;
}

function run()
{
    $total = 0;
    $i = 0;

    while ($i < 4000000) {
        $total = $total + add3($i, 1, 2);
        $i = $i + 1;
    }

    return $total;
}

echo run(), "\n";
