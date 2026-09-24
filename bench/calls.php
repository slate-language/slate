<?php
// The PHP twin of calls.sl: a method call that allocates, once per iteration.
//
// **The property is DECLARED, which gives it a fixed slot** -- a different thing from slate's keyed
// field, as `__slots__` would be in Python. PHP deprecated undeclared ("dynamic") properties in 8.2,
// so a declared one is simply what PHP is written with now, and the twin follows the language.

class Counter
{
    public function __construct(public $n)
    {
    }

    public function bump($by)
    {
        return new Counter($this->n + $by);
    }
}

function run()
{
    $c = new Counter(0);
    $i = 0;

    while ($i < 2000000) {
        $c = $c->bump(1);
        $i = $i + 1;
    }

    return $c->n;
}

echo run(), "\n";
