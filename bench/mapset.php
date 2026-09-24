<?php
// The PHP twin of mapset.sl.
//
// **PHP has neither a map type nor a set type: it has the array, and both are written with it** --
// `$m[$k] = $v` and `$s[$k] = true`, with `isset` as the membership test. That is Lua's situation,
// and it goes one step further: the keys here are the integers 0 to 999 arriving in order, so PHP
// keeps both arrays as plain vectors and never hashes anything. It is a genuinely smaller amount of
// work than slate's structurally hashed `Map` and `Set`, and it is what a PHP program gets. (The
// `ds` extension's `Map` and `Set` are not in a standard build.)

function run()
{
    $m = [];
    $s = [];
    $i = 0;

    while ($i < 2000000) {
        $m[$i % 1000] = $i;
        $s[$i % 1000] = true;
        $i = $i + 1;
    }

    $total = 0;
    $k = 0;

    while ($k < 1000) {
        $total = $total + $m[$k];

        if (isset($s[$k])) {
            $total = $total + 1;
        }

        $k = $k + 1;
    }

    return $total;
}

echo run(), "\n";
