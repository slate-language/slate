// A module that goes wrong, so the suite can ask what a fault raised in another file carries. The
// LINE NUMBERS BELOW ARE ASSERTED by `modules.sl`, so a line added above one of them moves it.
export breaks(x) = x \ 0

export async breaksAfterParking(x) =
    val waited = await x

    waited \ 0
