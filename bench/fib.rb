# The Ruby twin of fib.sl. Recursion 33 deep is nowhere near Ruby's stack limit, so what this
# measures is the cost of a method frame.

def fib(n)
  n < 2 ? n : fib(n - 1) + fib(n - 2)
end

puts fib(33)
