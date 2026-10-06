// The exporting half of `tests_method_predicates.sysl`: a data type whose members test the receiver
// and a class whose member tests an argument, each read by a call in the importing file.
export data Shape
    Circle(r: real)
    Square(side: real)

    isCircle(self) = self is Circle
    isSquare(self) -> this is Square =
        val yes = self is Square
        yes

export type Box = { size: integer }

export class Checker
    var seen = 0

    isBox(self, v: Box | string) -> v is Box =
        if !(v is object) then return false
        v.size is integer
