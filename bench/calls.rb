# The Ruby twin of calls.sl: a method call that allocates, once per iteration.
#
# Ruby has no way to declare an object's layout -- an instance variable is added by assigning it --
# but CRuby gives objects built the same way one "shape" and caches the slot at each `@n` read, so a
# field read here is closer to a slot than slate's keyed lookup is. That is Ruby's own
# implementation, not something this file chose.

class Counter
  attr_reader :n

  def initialize(n)
    @n = n
  end

  def bump(by)
    Counter.new(@n + by)
  end
end

def run
  c = Counter.new(0)
  i = 0

  while i < 2_000_000
    c = c.bump(1)
    i = i + 1
  end

  c.n
end

puts run
