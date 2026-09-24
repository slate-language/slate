# The Ruby twin of funcs.sl. A top-level `def` is a private method of Object, so `add3(i, 1, 2)` is a
# method call on `self` with an inline cache at the call site -- the nearest thing Ruby has to a
# plain function.

def add3(a, b, c)
  a + b + c
end

def run
  total = 0
  i = 0

  while i < 4_000_000
    total = total + add3(i, 1, 2)
    i = i + 1
  end

  total
end

puts run
