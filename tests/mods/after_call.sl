import { slowly } from "./waits.sl"

async main() =
    print(await slowly(1))

main()

missing_in_the_entry
