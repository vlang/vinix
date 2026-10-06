# Linux listen backlog regression

`backlogfixture/core.v` exercises the backlog values used by Linux applications, including
Rust's `listen(fd, -1)`. Negative values and `INT_MAX` must return promptly,
with the kernel limiting allocation to its supported maximum. Previously a
negative value became an invalid UNIX socket queue capacity and hung startup.

The probe tests `-1`, `INT_MIN`, `INT_MAX`, `0`, `1`, `128`, and `4096`. For each
value it first invokes the raw syscall with an additional upper-register word
to verify truncation to Linux's 32-bit `int` argument, then invokes `listen`
through libc. It connects a real UNIX stream client and sends a byte before accepting.
It calls `listen` again with `-1` and `0` while the connection is queued, then
accepts that connection and verifies bytes in both directions. Every descriptor
is closed and every socket pathname removed after each case.

Build the static ARM64 fixture from the repository root:

```sh
CC=clang python3 tests/listen-backlog/run.py --arch aarch64 --build-only \
  --state-dir /tmp/vinix-listen-backlog-build
```

The runner uses the native libc declarations in `backlog-native-abi.h` and
adds a PID1 driver that waits after the original probe returns. Run it in an
isolated guest with a separately built kernel:

```sh
python3 tests/listen-backlog/run.py --arch aarch64 \
  --state-dir /tmp/vinix-listen-backlog-build-2 \
  --kernel-dir /path/to/worktree/kernel --guest-state-dir /tmp/vlb-arm
```

Use `--arch x86_64` with `CC_AMD64=x86_64-linux-musl-gcc` for the other
architecture. Success includes:

```text
LISTEN-BACKLOG-PASS cases=7
```

Sockets are nonblocking, and readiness waits and completed `listen` calls have
five-second limits. Run the guest or process under an external deadline of at
most 60 seconds: a syscall stuck inside the kernel cannot be interrupted by
the probe's userspace clock check. `LISTEN-BACKLOG-BEGIN` identifies the case
that failed to return.
