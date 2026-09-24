<?php
// The PHP twin of fib.sl. A PHP call does not recurse on the C stack, and 33 deep is nothing to its
// own, so what this measures is the cost of a frame.

function fib($n)
{
    return $n < 2 ? $n : fib($n - 1) + fib($n - 2);
}

echo fib(33), "\n";
