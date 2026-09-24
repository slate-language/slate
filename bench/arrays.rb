# The Ruby twin of arrays.sl. `<<` is the push, `xs[i]` the index and `each` the walk -- a block
# call per element, which is how Ruby walks anything.

def build(n)
  xs = []
  i = 0

  while i < n
    xs << i * 2
    i = i + 1
  end

  xs
end

def by_index(xs)
  total = 0
  i = 0

  while i < xs.length
    total = total + xs[i]
    i = i + 1
  end

  total
end

def by_walk(xs)
  total = 0

  xs.each do |v|
    total = total + v
  end

  total
end

def run
  xs = build(500_000)
  total = 0
  turns = 0

  while turns < 10
    total = total + by_index(xs) + by_walk(xs)
    turns = turns + 1
  end

  total
end

puts run
