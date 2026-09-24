# The Ruby twin of globals.sl: arith.rb's loop with every name a GLOBAL.
#
# **A Ruby local written at the top of a file is still a frame slot**, and it is not visible inside a
# `def` either, so it is not what a slate module-level name is. The Ruby name every piece of the
# program can see is a `$global`, so that is what this uses -- as the Lua twin uses a Lua global.
# Each `$` access looks its name up in the interpreter's global-variable table rather than reading a
# slot, which is the margin this benchmark exists to measure.

$total = 0
$i = 0

while $i < 6_000_000
  $total = $total + $i * 2 - 1
  $i = $i + 1
end

puts $total
