# The Ruby twin of mapset.sl, using `Hash` and `Set`.
#
# Ruby's rule is `hash` and `eql?`, which is slate's rule rather than JavaScript's -- a class
# defining both is keyed by value here exactly as a slate class writing `hash` and `==` is. Every key
# in this program is a small integer, so nothing rests on that. `Set` is built into the core since
# Ruby 3.5; before that it was a Hash underneath.

def run
  m = {}
  s = Set.new
  i = 0

  while i < 2_000_000
    m[i % 1000] = i
    s.add(i % 1000)
    i = i + 1
  end

  total = 0
  k = 0

  while k < 1000
    total = total + m[k]

    if s.include?(k)
      total = total + 1
    end

    k = k + 1
  end

  total
end

puts run
