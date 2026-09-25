/* A C program with its own main, running a slate program through libslate.a. */
#include <stdio.h>
#include <string.h>

#include "libslate.a.h"

int main(void) {
    printf("slate major version: %d\n", slate_version_major());

    const char *program = "print(\"hello from C\")\n";
    int32_t code = slate_run_source((uint8_t *)program, strlen(program));
    printf("slate_run_source returned %d\n", code);

    /* A second run in the same process, of a program slate refuses: the diagnostic goes to
       stdout as it does for `slate <file>`, and the status is 1. */
    const char *refused = "nope()\n";
    code = slate_run_source((uint8_t *)refused, strlen(refused));
    printf("second run returned %d\n", code);

    return 0;
}
