<?php
// The PHP twin of arrays.sl. `$xs[] =` is the push, `$xs[$i]` the index and `foreach` the walk.
//
// **A PHP array is one type for both lists and maps**, but one built by appending from zero is kept
// as a plain vector (a "packed" array), so this is the same work as slate's array. `count` reads a
// stored number.

function build($n)
{
    $xs = [];
    $i = 0;

    while ($i < $n) {
        $xs[] = $i * 2;
        $i = $i + 1;
    }

    return $xs;
}

function by_index($xs)
{
    $total = 0;
    $i = 0;

    while ($i < count($xs)) {
        $total = $total + $xs[$i];
        $i = $i + 1;
    }

    return $total;
}

function by_walk($xs)
{
    $total = 0;

    foreach ($xs as $v) {
        $total = $total + $v;
    }

    return $total;
}

function run()
{
    $xs = build(500000);
    $total = 0;
    $turns = 0;

    while ($turns < 10) {
        $total = $total + by_index($xs) + by_walk($xs);
        $turns = $turns + 1;
    }

    return $total;
}

echo run(), "\n";
