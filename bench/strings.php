<?php
// The PHP twin of strings.sl.
//
// This is the naive form, `$out = $out . "x" . ...`, for comparison with the other twins; the
// idiomatic PHP is `.=`, which appends in place. A PHP string is bytes and `strlen` counts them --
// the same number as slate's characters, this text being ASCII.

function run()
{
    $out = "";
    $i = 0;

    while ($i < 150000) {
        $out = $out . "x" . ($i % 10);
        $i = $i + 1;
    }

    return strlen($out);
}

echo run(), "\n";
