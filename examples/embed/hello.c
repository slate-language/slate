/* slate embedded in a C program.
 *
 * Build the archive and its header from the repository root, then this file against them; the
 * README beside it has the two commands. `slate_new` makes an interpreter of its own, `slate_eval`
 * runs a program on it, and `slate_error` says why one was refused. `slate_global` and `slate_call`
 * call a function the programs defined, with values C made, and read what it answered.
 *
 * Every `slate_eval` on one interpreter runs in one session: what an earlier call defined at its top
 * level -- a function, a `val`, a class, an import -- a later call can use.
 *
 * The traffic goes the other way too: `slate_register` names a C function programs can call, and
 * `slate_on_output` hands C every line a program prints instead of writing it to stdout.
 *
 * And a host with a loop of its own turns slate's from it: `slate_set_manual_loop` makes a program
 * come back before its timers fire, and `slate_pump` runs them when C says. */

#include <stdio.h>
#include <string.h>
#include <unistd.h>

#include "slate.h"

/* A C function a program calls as `host_add(a, b)`: each argument arrives as a handle, and the answer
 * goes back as a handle slate takes over -- `0` would be `null`. */
static uint64_t host_add(slate_vm *vm, uint64_t *argv, uint64_t argc, uint8_t *user) {
    (void)user;

    int64_t sum = 0;

    for (uint64_t i = 0; i < argc; i++)
        sum += slate_to_int(vm, argv[i]);

    return slate_int(vm, sum);
}

/* Every line a program prints, without its newline; `user` is what `slate_on_output` was handed. */
static void heard(uint8_t *bytes, uint64_t len, uint8_t *user) {
    printf("%s%.*s\n", (const char *)user, (int)len, (const char *)bytes);
}

static int32_t run(slate_vm *vm, const char *name, const char *program) {
    /* What C has printed goes out before what the slate program prints, so the two stay in order. */
    fflush(stdout);

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

    /* Define a function in one call and use it in the next. */
    printf("define: %d\n", run(vm, "define.sl", "double(n) = n * 2"));
    printf("use: %d\n", run(vm, "use.sl", "print(double(21))"));

    /* One slate refuses: the status is one and the diagnostic names the file we gave it. */
    printf("second run: %d\n", run(vm, "broken.sl", "nope()"));

    /* One that chooses its own status. */
    printf("third run: %d\n", run(vm, "exit.sl", "import { exit } from slate:process\nexit(3)"));

    /* Call `double` from C: a handle to the function, one to the argument, and one to the answer. */
    uint64_t twice = slate_global(vm, (uint8_t *)"double", 6);
    uint64_t args[] = { slate_int(vm, 21) };
    uint64_t answer = 0;

    if (slate_call(vm, twice, args, 1, &answer) == 0)
        printf("double(21) from C: %lld\n", (long long)slate_to_int(vm, answer));

    /* An array slate answers, printed as slate prints it. */
    run(vm, "list.sl", "listed(n) = [n, n * 2, \"done\"]");

    uint64_t lister = slate_global(vm, (uint8_t *)"listed", 6);
    uint64_t three[] = { slate_int(vm, 3) };
    uint64_t listed = 0;

    if (slate_call(vm, lister, three, 1, &listed) == 0)
        printf("listed(3) from C: %s (%d elements)\n", slate_show(vm, listed), (int)slate_len(vm, listed));

    slate_release(vm, lister);
    slate_release(vm, twice);
    slate_release(vm, args[0]);
    slate_release(vm, answer);
    slate_release(vm, three[0]);
    slate_release(vm, listed);

    /* A C function programs call by name, and C hearing what they print. */
    slate_register(vm, (uint8_t *)"host_add", 8, host_add, NULL);
    slate_on_output(vm, heard, (uint8_t *)"[slate] ");

    printf("host: %d\n", run(vm, "host.sl", "print(host_add(40, 2))\nprint(\"from\", \"slate\")"));

    /* Output back to stdout. */
    slate_on_output(vm, NULL, NULL);
    run(vm, "plain.sl", "print(host_add(1, 2, 3))");

    /* A host with a main loop of its own. In manual mode the program comes back at its first
     * suspension with its timer still pending, and C turns slate's loop from its own: here a short
     * sleep stands in for a `poll` on `slate_loop_fd` for up to `slate_loop_timeout` milliseconds. */
    slate_on_output(vm, heard, (uint8_t *)"[loop] ");
    slate_set_manual_loop(vm, 1);

    printf("armed: %d\n", run(vm, "timer.sl", "setTimeout(() -> print(\"tick\"), 20)\nprint(\"armed\")"));
    printf("pending: %d\n", slate_pump(vm));
    printf("descriptor: %s, wait: %s\n", slate_loop_fd(vm) >= 0 ? "yes" : "no",
           slate_loop_timeout(vm) > 0 ? "yes" : "no");

    int32_t busy;

    while ((busy = slate_pump(vm)) == 1)
        usleep(2000);

    printf("idle: %d\n", busy);

    slate_set_manual_loop(vm, 0);
    slate_free(vm);
    return 0;
}
