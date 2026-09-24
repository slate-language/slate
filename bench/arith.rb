# The Ruby twin of arith.sl. Ruby's Integer is arbitrary precision, as Python's is, so this loop
# never wraps; below 2^62 a Ruby integer is an immediate (a tagged word) and costs no allocation.

def run
  total = 0
  i = 0

  while i < 10_000_000
    total = total + i * 2 - 1
    i = i + 1
  end

  total
end

puts run
