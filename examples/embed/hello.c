/* slate embedded in a C program.
 *
 * Build the archive and its header from the repository root, then this file against them; the
 * README beside it has the two commands. `slate_new` makes an interpreter of its own, `slate_eval`
 * runs a program on it, and `slate_error` says why one was refused. */

#include <stdio.h>
#include <string.h>

#include "libslate.a.h"

static int32_t run(slate_vm *vm, const char *name, const char *program) {
    int32_t code = slate_eval(vm, (uint8_t *)program, strlen(program), (uint8_t *)name, strlen(name));

    if (slate_error_len(vm) > 0)
        fprintf(stderr, "%s\n", slate_error(vm));

    return code;
}

int main(void) {
    printf("slate %s\n", slate_version());

    slate_vm *vm = slate_new(0);

    /* A program that runs, printing as it goes. */
    printf("first run: %d\n", run(vm, "hello.sl", "print(\"hello from C\")"));

    /* One slate refuses: the status is one and the diagnostic names the file we gave it. */
    printf("second run: %d\n", run(vm, "broken.sl", "nope()"));

    /* One that chooses its own status. */
    printf("third run: %d\n", run(vm, "exit.sl", "import { exit } from slate:process\nexit(3)"));

    slate_free(vm);
    return 0;
}
