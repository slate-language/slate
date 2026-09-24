<?php
// The PHP twin of fields.sl.
//
// An associative array rather than an object, because that is what slate's `{ a: 0 }` is: a value
// keyed by a name, with nothing declared about which names it has. **A PHP array is a VALUE**, copied
// on write when shared -- here it is held by one variable, so every write is in place.

function run()
{
    $o = ["a" => 0, "b" => 1, "c" => 2];
    $i = 0;

    while ($i < 5000000) {
        $o["a"] = $o["a"] + $o["b"] + $o["c"];
        $i = $i + 1;
    }

    return $o["a"];
}

echo run(), "\n";
