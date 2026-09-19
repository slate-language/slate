# The Python twin of fib.sl.
#
# CPython's default recursion limit is 1000 frames and this goes 33 deep, so nothing has to be
# raised -- what the benchmark measures is the cost of a frame, not the ceiling on how many.


def fib(n):
    return n if n < 2 else fib(n - 1) + fib(n - 2)


print(fib(33))
