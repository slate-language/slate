<?php
// The PHP twin of strwalk.sl.
//
// **A PHP string is bytes, and a character is reached through `mbstring`**: `mb_substr($s, $i, 1)`
// is the character at position `$i`, and it finds it by counting from the FRONT -- so this walk is
// quadratic in the length of the string, as slate's used to be and as Lua's is. `mb_str_split` into
// an array first would make every read constant time, at the price of a string per character, and
// would be a different program. `mb_strlen` counts from the front too, so the bound is taken once
// into a local, as the Lua twin does.

function run($s)
{
    $found = 0;
    $n = mb_strlen($s);
    $i = 0;

    while ($i < $n) {
        if (mb_substr($s, $i, 1) === "本") {
            $found = $found + 1;
        }

        $i = $i + 1;
    }

    return $found;
}

echo run(str_repeat("日本語あいうえおかきく" . "さしすせそたちつてと", 1000)), "\n";
