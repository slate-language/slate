<?php
// The PHP twin of nested.sl: loops.php's loop inside a function that also holds a closure over one
// of its names -- which PHP captures by value when the closure is made, as closures.php says.

function run($pairs)
{
    $total = 0;
    $turns = 0;
    $scale = 1;
    $weigh = fn($v) => $v * $scale;

    while ($turns < 6000) {
        foreach ($pairs as [$a, $b]) {
            $total = $total + $weigh($a * $b);
        }

        $turns = $turns + 1;
    }

    return $total;
}

$pairs = [];

for ($i = 0; $i < 1000; $i++) {
    $pairs[] = [$i, $i + 1];
}

echo run($pairs), "\n";
