<?php
// The PHP twin of globals.sl: arith.php's loop written at the top of the file.
//
// **PHP HAS NO MARGIN HERE, AND THAT IS PHP'S DESIGN RATHER THAN THIS FILE'S CHOICE.** A variable at
// the top of a script is a global -- it lives in the global symbol table, where `global $total` in a
// function finds it -- but the script's own code still reaches it through a compiled slot bound to
// that table's entry once, so each access here is a slot read. The benchmark measures what it costs
// to write a loop at module level, and in PHP that costs nothing extra.

$total = 0;
$i = 0;

while ($i < 6000000) {
    $total = $total + $i * 2 - 1;
    $i = $i + 1;
}

echo $total, "\n";
