# The Ruby twin of closures.sl. A `def` does not close over the locals around it, so the closure is
# a lambda and `weigh.(v)` calls it; `scale` is read out of the enclosing frame, which the lambda
# keeps alive -- the arrangement slate keeps a scope for.

def run
  total = 0
  turns = 0
  scale = 3
  weigh = ->(v) { v * scale }

  while turns < 4_000_000
    total = total + weigh.(turns)
    turns = turns + 1
  end

  total
end

puts run
