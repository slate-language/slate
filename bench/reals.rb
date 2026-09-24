# The Ruby twin of reals.sl. A Ruby Float is a double and `i * 1.5` promotes the integer, so the
# arithmetic is the same sequence of operations on the same values. On a 64-bit build most doubles
# are "flonums", packed into the tagged word, so a float here costs no allocation either.

def run
  total = 0.0
  i = 0

  while i < 10_000_000
    total = total + i * 1.5 - 0.5
    i = i + 1
  end

  total
end

puts format("%.1f", run)
