<?php
// The PHP twin of loops.sl. `foreach ($pairs as [$a, $b])` unpacks in the loop head, which is what
// slate's `for [a, b] in pairs` does. A PHP array built by appending is stored as a plain vector (a
// "packed" array) until something makes it a hash table, so this walk is over a vector.

function run($pairs)
{
    $total = 0;
    $turns = 0;

    while ($turns < 8000) {
        foreach ($pairs as [$a, $b]) {
            $total = $total + $a * $b;
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
