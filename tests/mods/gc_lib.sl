export make(n) =
    var xs = []
    var i = 0
    while i < n
        push(xs, s"item ${i}")
        i += 1
    xs

export val tag = "kept across a collection"
