<?php
// The PHP twin of methods.sl, written with a real `class`.
//
// The properties are declared, for calls.php's reason: that gives each a fixed slot, which is a
// faster read than slate's keyed field and is how PHP is written since dynamic properties were
// deprecated. No type declarations anywhere, slate's fields and parameters being untyped.

class Vec
{
    public function __construct(public $x, public $y)
    {
    }

    public function dot($o)
    {
        return $this->x * $o->x + $this->y * $o->y;
    }

    public function scaled($k)
    {
        return $this->x * $k + $this->y * $k;
    }
}

function run()
{
    $a = new Vec(2, 3);
    $b = new Vec(5, 7);
    $total = 0;
    $i = 0;

    while ($i < 3000000) {
        $total = $total + $a->dot($b) + $b->scaled(1);
        $i = $i + 1;
    }

    return $total;
}

echo run(), "\n";
