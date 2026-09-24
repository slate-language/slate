# The Ruby twin of sorting.sl.
#
# `sort` answers a new array, which is what slate's `sorted` does. On an array of Integers CRuby
# compares without calling back into the program, which is slate's arrangement and not JavaScript's.

def build(n)
  xs = []
  seed = 1

  n.times do
    seed = (seed * 16807) % 2147483647
    xs << seed
  end

  xs
end

def run
  xs = build(20_000)
  total = 0
  turns = 0

  while turns < 200
    ys = xs.sort

    total = total + ys[0] + ys[19_999]
    turns = turns + 1
  end

  total
end

puts run
