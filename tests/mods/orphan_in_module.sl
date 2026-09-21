// Padding, and it is what makes the program below able to fail the way it must not. A span
// belonging to the other file still LOCATES in this one -- an offset is an offset -- so a report
// drawn against the wrong file quotes a line of this comment, which exists, reads plausibly, and
// has nothing whatever to do with the fault.
import { fails_after_parking } from "./awaited_faulty.sl"

fails_after_parking(1)
