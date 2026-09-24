# The Ruby twin of nested.sl: loops.rb's loop inside a method that also holds a closure over one of
# its names. `each` with a two-parameter block unpacks each pair in the block's head, which is what
# slate's `for [a, b] in pairs` does -- and it is a block call per element, which is Ruby's walk.

def run(pairs)
  total = 0
  turns = 0
  scale = 1
  weigh = ->(v) { v * scale }

  while turns < 6000
    pairs.each do |a, b|
      total = total + weigh.(a * b)
    end

    turns = turns + 1
  end

  total
end

puts run((0...1000).map { |i| [i, i + 1] })
