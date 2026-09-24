<?php
// The PHP twin of dispatch.sl, written as `match` -- which PHP 8 grew, and which is the same
// construct slate has: a subject compared against literal patterns, answering a value.
//
// **PHP compiles a `match` whose arms are all literal strings to a HASH lookup into a jump table**,
// so this is the "one that could hash the subject once" dispatch.sl's header anticipates.

function kind($w)
{
    return match ($w) {
        "add" => 1,
        "sub" => 2,
        "mul" => 3,
        "div" => 4,
        "mod" => 5,
        default => 0,
    };
}

function run($words)
{
    $total = 0;
    $i = 0;

    while ($i < 5000000) {
        $total = $total + kind($words[$i % 6]);
        $i = $i + 1;
    }

    return $total;
}

echo run(["add", "sub", "mul", "div", "mod", "nope"]), "\n";
