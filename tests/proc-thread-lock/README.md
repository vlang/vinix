# Process inspection and thread attachment lock regression

Two inspector threads repeatedly read `/proc/<pid>/stat`, `status`, the main
thread's `comm`, and an explicit process CPU clock while their process creates
and joins 128 threads. They then inspect 32 children through their explicit
PIDs. Each child waits on a pipe until an inspector has read its `stat` and
`status`, then execs while inspection continues. The test checks inspection
data and requires concurrent progress; the runner's timeout also catches a
kernel-wide deadlock.

This reproduces a desktop freeze caused by inconsistent lock order: process
inspection took the process-table lock before the thread-list lock, while
thread attachment took them in reverse order. Both must take the table lock
first, including TID allocation and PID namespace numbering.

Build the requested kernel, then boot an isolated guest with:

```sh
VINIX_QEMU_SMP=4 python3 tests/kernel-gaps/run.py \
  --source tests/proc-thread-lock/test.c --arch aarch64 \
  --kernel-dir kernel --expect 'VINIX PROC THREAD LOCK: PASS'
```

Repeat with `--arch x86_64` and the x86-64 kernel directory. The shared runner
uses two CPUs for x86-64, which is enough to exercise the opposing lock paths.
