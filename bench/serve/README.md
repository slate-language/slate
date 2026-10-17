# The server benchmark

`run.sh` loads the same three-endpoint server written in slate, `slate js` under node, node, Bun and
Go, and reports one table. Its header says every option.

## Profiling the slate server

`SLATE_PROFILE=1` writes the interpreter's profile to stderr **when the program ends**, which a server
never does. Send the running process `SIGUSR1` instead and it writes the same report at once, then
starts counting again from nothing, so each signal gives the interval since the last one:

```
SLATE_PROFILE=1 ./slate bench/serve/server.sl 2> profile.txt &
pid=$!
# ... apply load ...
kill -USR1 $pid
# profile.txt now holds the first interval; send load, signal again for the next
kill $pid
```

- The report is the one `SLATE_PROFILE` prints at exit. Collections, collector time, allocator steps
  and the per-builtin calls and microseconds are per interval; `heap in use` and `heap high water` are
  levels and are not reset. `wall` is the time since the previous dump.
- **A program's own `onSignal("SIGUSR1", ...)` wins**: while it has a handler on that signal the
  signal is the program's and nothing is dumped.
- Instruction kinds need a build with `--features profile`; the report says so when they are not
  counted.
- Interpreter only. Under `slate js` the program is node's, and node's profiler is the instrument:
  `node --cpu-prof`.
- For a profile of where the native code spends its time, macOS `sample <pid>` still applies, as in
  `bench/profile.sl`.

`scripts/profile-signal-check.sh` is the end-to-end check of this: it starts a program that does not
end, sends the signal twice and reads two reports off stderr while the process stays alive.
