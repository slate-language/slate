<?php
// The PHP twin of strindex.sl.
//
// **`$s[$i]` is a constant-time read of one BYTE**, so this walk is linear. The text is ASCII, so a
// byte is a character and the unit is slate's; strwalk.php is where that stops being true.

function run($s)
{
    $found = 0;
    $i = 0;

    while ($i < strlen($s)) {
        if ($s[$i] === "x") {
            $found = $found + 1;
        }

        $i = $i + 1;
    }

    return $found;
}

echo run(str_repeat("abcdexfghi" . "jklmnxopqr", 1000)), "\n";
