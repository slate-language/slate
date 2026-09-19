// Method calls on a class instance, with nothing allocated in the loop.
//
// **`calls.sl` measures a method call AND an allocation, which is the shape ordinary code has; this
// measures the dispatch alone.** A method is found by walking the receiver's proto chain, so what is
// paid per call is a field read that misses on the object, a hit on the class, the receiver rule
// that decides what `self` is, and then the frame.

class Vec
    var x
    var y

    dot(self, o) = self.x * o.x + self.y * o.y
    scaled(self, k) = self.x * k + self.y * k
end Vec

run()
    val a = Vec(2, 3)
    val b = Vec(5, 7)
    var total = 0
    var i = 0

    while i < 3000000
        total = total + a.dot(b) + b.scaled(1)
        i = i + 1

    total

print(run())
