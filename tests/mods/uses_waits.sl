import { slowly } from "./waits.sl"

async main() =
    print(await slowly(21))

main()
