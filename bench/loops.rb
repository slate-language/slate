# The Ruby twin of loops.sl. `pairs.each do |a, b|` unpacks each pair in the block's head, which is
# what slate's `for [a, b] in pairs` does. Ruby's `for` exists and is `each` underneath, so the
# idiomatic spelling costs the same block call either way.

def run(pairs)
  total = 0
  turns = 0

  while turns < 8000
    pairs.each do |a, b|
      total = total + a * b
    end

    turns = turns + 1
  end

  total
end

puts run((0...1000).map { |i| [i, i + 1] })
