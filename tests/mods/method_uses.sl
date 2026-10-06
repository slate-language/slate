import { Shape, Circle, Square, Box, Checker } from "./method_lib.sl"

radius(c: Circle) = c.r
side(q: Square) = q.side
need(b: Box) = b.size

val c = Checker()

round(s: Shape) = if s.isCircle() then radius(s) else 0.5
square(s: Circle | Square) = if s.isSquare() then side(s) else radius(s)
size(v: Box | string) = if c.isBox(v) then need(v) else v.length

print(round(Circle(1.5)), round(Square(2.5)), square(Square(2.5)), size({ size: 3 }), size("ab"))
