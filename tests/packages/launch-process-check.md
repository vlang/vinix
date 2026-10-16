# Synchronous package execution

Both ordinary sandbox launch and the root-to-account session handoff use a
private synchronous POSIX runner. It borrows the complete `Launch` until child
completion, builds only a bounded argument-pointer vector, inherits the caller's
environment and streams, and retires its vector and descriptors on return.
The outer plan and prepared-service owners keep their existing lifetimes.
No public API, package format or serialized state changes.

The child performs only close, chdir, execv, write and `_exit` after fork, with
fixed stack status storage. The close-on-exec pipe uses descriptors above 2,
including when standard streams were deliberately closed. A failed directory
change prevents execution. A small atomic stage/errno record lets the parent
return a diagnostic naming the failed working directory or program. Normal
exit codes 126/127 remain ordinary return values; they cannot be mistaken for
setup failure. Signal exits remain `128 + signal`. Wait and status-channel
operations retry interruption. After reaping its child, the parent reads the
status channel without blocking on copies held by unrelated concurrent forks.

Matched native probes use unchanged production sources from `4a49db923` and
the same borrowed plans, child, environment and compiler options. The previous
`os.Process` wait/close sequence retained **109,870 bytes** over five normal
exits and **110,105 bytes** over five signal exits. The replacement retains
**zero** in both probes. These byte counts depend on the recorded environment
and path lengths. They measure the previous production sequence, including
its unretired Process/environment/spawn storage; they are not an isolated
measurement of the standard library's `Process.free()` method.

The tracked assertion runner exercises 1000 attempts per case:

- Four successful statuses: normal 37/126/127 and signal 143. Every child is
  reaped, no descriptor accumulates, and parent heap retention is zero.
- Ten refusal paths: missing/non-directory working folder, missing/denied/
  invalid-format executable, relative program/folder, NUL program/folder and
  NUL argument. Each returns the expected stage without executing the payload,
  retaining scratch, leaking descriptors or leaving a child to reap.
- Descriptor exhaustion in an isolated process: 1000 pipe-creation refusals
  retain zero; restoring descriptors and the original limit permits retry.

Additional assertions preserve empty, Unicode, shell-looking and newline
arguments, a symlinked executable, a working directory containing spaces,
literal inherited environment, and UID/GID. Separate stdin/stdout/stderr and
closed standard streams are checked in isolated processes. A held parent
generation lease blocks an exclusive contender while the application runs,
its close-on-exec descriptor is absent in the application, and the final parent
close releases the lock. Native ASan/UBSan runs the ownership/error assertions
with allocation tracking disabled; leak tracking is handled separately by the
explicit parent allocator fixture.

The focused regression set includes service preparation, coordination,
state schema, owned planning, literal commands, SDK context, account-session
planning, installed namespace and registration-parent checks. The CLI signed
repository install/update/rollback/remove lifecycle and distribution-driver
compilation also pass. The main distribution driver builds the child fixture
before core tests and runs this tracked fixture. Direct native invocation can
build its own temporary V child when no explicit child path is provided.

The guest controller builds a tracked worker and its V child for each target,
then executes the same assertions as root and UID 1000. Companion coordination,
session and command fixtures run afterward. The worker checks real child
execution under each identity and parent allocations; it does not measure
kernel allocations or claim new runtime/API compatibility. Full graphical
login, advertised foreign applications and successful end-to-end account-session
sandbox admission remain covered by their separate qualification gates.
No kernel source changes are involved. Roadmap 14 remains open for production
publisher enrollment, advertised catalog migration, graphical display/session
integration and broader runtime/filesystem qualification.

## Recorded results, 2026-10-16

All **37 focused native compile/run checks** passed: a child build, ten core
pairs, standalone child-build fallback, tracked and ASan/UBSan pairs, matched
previous/current pairs, four CLI/driver checks and three guest-tool builds.

The first x86_64 guest attempt reached its 600-second deadline after the root
suite passed and the ordinary-account suite began. No assertion failure was
printed; its original report and serial log are retained. The scenario now
allows 1200 seconds for the two credential paths and thousands of real fork/exec
cycles under emulation. Deadlines qualify functionality rather than performance.

Fresh QEMU TCG guests passed with clean shutdowns: AArch64 **390.0 seconds**
and the x86_64 retry **734.6 seconds**. Each passed 15,000 tracked attempts as
root and 15,000 as UID 1000, retaining zero parent bytes in every measured case.
All eight artifact hashes per receipt were verified. The retry's init and five
fixture executables are byte-for-byte identical to the initial x86_64 attempt;
the allowance is the only harness behavior changed for that retry.

The final host/guest results and artifact pins are retained below. Native
commands from the repository root:

```sh
v -nocache -no-skip-unused -gc none -manualfree -o /tmp/launch-child \
  tests/packages/launch-process-child.v
v -nocache -no-skip-unused -gc none -manualfree -d track_heap \
  -path '@vlib|@vmodules|.|tools/accounts' -o /tmp/launch-process \
  tools/packages/pkgcore/launch_process_test.v
VINIX_PACKAGE_LAUNCH_CHILD=/tmp/launch-child /tmp/launch-process
```

The guest controller is `tests/packages/launch-process-runtime-check.v`; its
per-program flags enable tracking without altering companion workers or init.
Use `--arch aarch64|x86_64 --kernel PATH --state-dir NEW_DIRECTORY`. The retained
comparison fixture is copied as `launch_process_comparison_test.v` into isolated
previous/current `pkgcore` copies with the same module lookup. Add
`-d launch_process_baseline` only for previous production sources.

- [host checks](results/2026-10-16/launch-process-host.json), [summary](results/2026-10-16/launch-process-host.txt)
- [core assertions](results/2026-10-16/launch-process-core.txt), [tracked allocations](results/2026-10-16/launch-process-memory.txt)
- [sanitizers](results/2026-10-16/launch-process-asan.txt), [CLI lifecycle](results/2026-10-16/launch-process-cli.txt)
- [matched probes](results/2026-10-16/launch-process-baseline.txt), [V comparison fixture](results/2026-10-16/launch-process-comparison.v)
- [source/toolchain/artifact pins](results/2026-10-16/launch-process-toolchain.json)
- [generated-C lifetime review](results/2026-10-16/launch-process-generated-c.txt)
- [initial x86_64 deadline report](results/2026-10-16/launch-process-x86_64.before.txt), [serial](results/2026-10-16/launch-process-x86_64.before.serial.txt)
- [AArch64 receipt](results/2026-10-16/launch-process-aarch64.json), [report](results/2026-10-16/launch-process-aarch64.txt), [serial](results/2026-10-16/launch-process-aarch64.serial.txt), [QMP](results/2026-10-16/launch-process-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-16/launch-process-x86_64.json), [report](results/2026-10-16/launch-process-x86_64.txt), [serial](results/2026-10-16/launch-process-x86_64.serial.txt), [QMP](results/2026-10-16/launch-process-x86_64.qmp.txt)
