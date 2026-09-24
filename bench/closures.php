<?php
// The PHP twin of closures.sl.
//
// **A PHP closure captures BY VALUE, when it is made**: `fn` copies `$scale` into the closure, so
// reading it later is a read of the closure's own copy rather than of a scope both share. slate
// keeps a scope so a later write would be seen; nothing writes `$scale` here, so the answer is the
// same and the work is a little less. `function () use (&$scale)` would share it and is not what PHP
// programs write for a value that never changes.

function run()
{
    $total = 0;
    $turns = 0;
    $scale = 3;
    $weigh = fn($v) => $v * $scale;

    while ($turns < 4000000) {
        $total = $total + $weigh($turns);
        $turns = $turns + 1;
    }

    return $total;
}

echo run(), "\n";
