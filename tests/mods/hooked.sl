export point(x) =
    var p = { x: x }
    p.hash = () -> p.x
    p["=="] = o -> o.x == p.x
    p
