<?php
// The PHP twin of csv.sl.
//
// `explode` is the split and `(int)` the conversion; `strlen` counts bytes, which is slate's
// character count here, this text being ASCII. `str_getcsv` would be the idiomatic reader for a real
// file and would not be the same work: it handles quoting.

function build($rows)
{
    $lines = [];
    $i = 0;

    while ($i < $rows) {
        $lines[] = $i . "," . ($i * 2) . ",name" . ($i % 100);
        $i = $i + 1;
    }

    return implode("\n", $lines);
}

function parse($text)
{
    $total = 0;

    foreach (explode("\n", $text) as $line) {
        $parts = explode(",", $line);

        $total = $total + (int) $parts[0] + (int) $parts[1] + strlen($parts[2]);
    }

    return $total;
}

function run()
{
    $text = build(20000);
    $total = 0;
    $turns = 0;

    while ($turns < 30) {
        $total = $total + parse($text);
        $turns = $turns + 1;
    }

    return $total;
}

echo run(), "\n";
