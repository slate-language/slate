# The Ruby twin of fields.sl.
#
# A Hash rather than an object, because that is what slate's `{ a: 0 }` is: a value keyed by a name,
# with nothing declared about which names it has. The keys are Symbols, Ruby's idiom for a
# record-like hash; a Symbol hashes by identity, which is cheaper than slate hashing a string.

def run
  o = { a: 0, b: 1, c: 2 }
  i = 0

  while i < 5_000_000
    o[:a] = o[:a] + o[:b] + o[:c]
    i = i + 1
  end

  o[:a]
end

puts run
