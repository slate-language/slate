// A `for` variable is a `val`: a write to it is refused with the machine's own sentence.
//
// JavaScript would let `let` take the write, so the emitted program used to carry on with the new
// value. `js_spell.sysl` refuses it at the write, naming the variable, exactly as the interpreter does.

plain()
    for x in [1, 2]
        try
            x = 6
        catch e
            print(e.message)
        print(x)

compound()
    for x in [10]
        try
            x += 1
        catch e
            print(e.message)
        print(x)

fromClosure()
    for i in 0..<2
        val show = () ->
            try
                i = 9
            catch e
                print(e.message)
            i
        print(show())

destructured()
    for [a, b] in [[1, 2]]
        try
            a = 3
        catch e
            print(e.message)
        print(a, b)

shadowed()
    for x in [1]
        var x = 5
        x = 6
        print(x)

shadowedByParameter()
    for x in [1]
        val bump = (x) ->
            x = x + 1
            x
        print(bump(7), x)

afterTheLoop()
    var x = 1
    for y in [1]
        print(y)
    x = 2
    x

plain()
compound()
fromClosure()
destructured()
shadowed()
shadowedByParameter()
print(afterTheLoop())
