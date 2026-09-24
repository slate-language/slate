<?php
// The PHP twin of sorting.sl.
//
// `sort` sorts IN PLACE, so the copy slate's `sorted` makes is written out: an array is a value, and
// `$ys = $xs` followed by a write to `$ys` copies it. The comparison is PHP's own on integers and
// never calls back into the program, which is slate's arrangement.

function build($n)
{
    $xs = [];
    $seed = 1;

    for ($k = 0; $k < $n; $k++) {
        $seed = ($seed * 16807) % 2147483647;
        $xs[] = $seed;
    }

    return $xs;
}

function run()
{
    $xs = build(20000);
    $total = 0;
    $turns = 0;

    while ($turns < 200) {
        $ys = $xs;
        sort($ys);

        $total = $total + $ys[0] + $ys[19999];
        $turns = $turns + 1;
    }

    return $total;
}

echo run(), "\n";
