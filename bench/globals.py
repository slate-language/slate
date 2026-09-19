# The Python twin of globals.sl: arith.sl's loop written at module level, where every name is a key
# in the module dictionary rather than a slot in a frame. That is exactly the margin this benchmark
# exists to measure, and CPython has it for the same reason slate does.

total = 0
i = 0

while i < 6000000:
    total = total + i * 2 - 1
    i = i + 1

print(total)
