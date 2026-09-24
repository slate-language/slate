<?php
// The PHP twin of options.sl.
//
// An array with `??` for a default is what PHP writes where slate writes a pattern default. Named
// arguments with defaults called through `...$opts` would be the other spelling, and would unpack
// the array into a new frame's parameters on every call.

function sized($opts)
{
    $width = $opts["width"] ?? 10;
    $height = $opts["height"];
    $scale = $opts["scale"] ?? 2;

    return $width * $height * $scale;
}

function run($given, $partial)
{
    $total = 0;
    $turns = 0;

    while ($turns < 2000000) {
        $total = $total + sized($given) + sized($partial);
        $turns = $turns + 1;
    }

    return $total;
}

echo run(["width" => 3, "height" => 4, "scale" => 5], ["height" => 4]), "\n";
