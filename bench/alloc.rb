# The Ruby twin of alloc.sl.
#
# A Hash rather than an object, for fields.rb's reason. Ruby traces rather than reference counting,
# as slate does, so the dropped hashes wait for a minor collection of its generational heap -- the
# same bargain as slate's collector, made with a nursery that slate does not have.

def run
  total = 0
  i = 0

  while i < 3_000_000
    p = { x: i, y: i + 1 }

    total = total + p[:x] + p[:y]
    i = i + 1
  end

  total
end

puts run
