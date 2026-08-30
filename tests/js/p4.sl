val xs = [1, 2]
val more = [0, ...xs, 3]
print(more)
val props = { a: 1, b: 2 }
val merged = { ...props, b: 3, c: 4 }
print(merged)
print({ ...props })
val said = try
    val bad = { ...null }
    "no"
catch e
    e.message
print(said)
val said2 = try
    val bad = [...5]
    "no"
catch e
    e.message
print(said2)
