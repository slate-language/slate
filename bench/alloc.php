<?php
// The PHP twin of alloc.sl.
//
// An associative array rather than an object, for fields.php's reason. PHP reference counts, so each
// array is freed on the line that drops it and the cycle collector never sees it -- CPython's
// bargain, not slate's tracing collector.

function run()
{
    $total = 0;
    $i = 0;

    while ($i < 3000000) {
        $p = ["x" => $i, "y" => $i + 1];

        $total = $total + $p["x"] + $p["y"];
        $i = $i + 1;
    }

    return $total;
}

echo run(), "\n";
