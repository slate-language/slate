export data Figure
    Circle(r)
    Rect(w, h)
    Empty

    area(self) = self match
        Circle(r) -> r * r * 3
        Rect(w, h) -> w * h
        Empty -> 0
