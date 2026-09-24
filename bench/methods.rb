# The Ruby twin of methods.sl, written with a real `class`.
#
# `attr_reader` is the idiomatic accessor and is what `o.x` calls; CRuby runs it without pushing a
# Ruby frame. Instance variables are cached by object shape, as calls.rb says, so a field read is
# nearer a slot read than slate's is.

class Vec
  attr_reader :x, :y

  def initialize(x, y)
    @x = x
    @y = y
  end

  def dot(o)
    @x * o.x + @y * o.y
  end

  def scaled(k)
    @x * k + @y * k
  end
end

def run
  a = Vec.new(2, 3)
  b = Vec.new(5, 7)
  total = 0
  i = 0

  while i < 3_000_000
    total = total + a.dot(b) + b.scaled(1)
    i = i + 1
  end

  total
end

puts run
