export point(x) =
    var p = { x: x }
    p.hash = () -> p.x
    p.equals = o -> o.x == p.x
    p
