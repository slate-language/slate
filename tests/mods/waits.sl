export async slowly(x) =
    val v = await x
    v * 2
