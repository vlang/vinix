# ARM64 asynchronous signal return

This probe runs an ordinary dynamic musl executable under an isolated kernel.
Real `SIGALRM` signals use `sigaction(SA_SIGINFO | SA_RESTART)` and a repeated
`setitimer`. Aligned busy work, allocation/string/setjmp calls, and blocking pipe
I/O must survive before the final case runs.

The final case briefly subtracts eight from SP inside one assembly block and
waits for a real signal using a global address in a register. It performs no
SP-based memory access or function call, then restores SP before C resumes.
The handler records the public interrupted SP/PC without editing the signal
frame. Linux accepts this interrupted context: the **current signal-frame** SP
must be aligned, but the interrupted SP need not be aligned while executing
register-only instructions. See [Linux v6.12 ARM64 signal return](https://github.com/torvalds/linux/blob/v6.12/arch/arm64/kernel/signal.c).

The static test init reaps the dynamic child and reports its actual exit or
signal. Success requires both `SIGNAL-RETURN-PASS` and
`SIGNAL-RETURN-CHILD-EXIT status=0`; a crash, panic, missing marker, or timeout
fails. PID 1 stays alive until the existing kernel-gaps controller stops its
owned VM. No desktop, Android, application state, network, or credentials are
involved.

Build the ARM64 kernel and stage the genuine musl runtime first, then run:

```sh
python3 tests/aarch64-sigreturn/run.py \
  --kernel-dir kernel \
  --state-dir /tmp/vinix-sigreturn-after
```

The runner uses `aarch64-linux-musl-gcc` from PATH; override it with `--cc` or
`VINIX_AARCH64_CC`. `--musl` selects the real ARM64 loader/libc image. When the
kernel is built in a worktree without boot dependencies, `--runner-root` selects
the repository containing the standard `scripts/run-aarch64.sh` and kernel-gaps helper.
Each invocation requires a fresh state directory and snapshots its kernel,
sources, ELF files, runtime, and SHA-256 receipts. Use a distinct directory for
the older kernel: it should pass the aligned controls, observe an interrupted
SP ending in eight, and report child signal 11 instead of success.

For a Linux ARM64 control, run the same built ELF through the same staged musl
image, using a directory containing the loader and a
`libc.musl-aarch64.so.1` symlink to that loader:

```sh
./ld-musl-aarch64.so.1 --library-path . ./signal-return-probe
```
