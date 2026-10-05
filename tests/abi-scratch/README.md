# Stat and poll syscall scratch allocations

`fstat`, `fstatat`, and `statx` fill caller-owned kernel records before checked
userspace copying. `ppoll` copies its optional timeout and signal mask into
caller-owned slots that stay alive across the wait. The timer copies its time
value, and the signal path applies a scalar mask; neither retains these slots.
Explicit `vinix_stack_alloc` storage prevents V escape analysis from promoting
these synchronous locals to unfreed heap objects.

Run `python3 tests/abi-scratch/run.py` or add `--arch=amd64`, using the prebuilt
isolated-kernel overrides documented in `tests/terminal-jobs/README.md`.
Set `VINIX_QEMU_RT_NO_BUILD=1` when measuring a prebuilt ARM kernel so the
real-time runner does not rebuild it with its default compiler/configuration.
The guest checks native stat layouts, symlink and AT_EMPTY_PATH/statx results,
invalid pointers and lookup failures. Poll tests cover immediate readiness,
invalid timeout/mask pointers, temporary-mask restoration, and a blocking
wait interrupted by a caught signal. One thousand iterations combine
four stat calls and a ppoll with both optional inputs, measuring retained slab
memory and printing live allocation chains if it grows.
On x86 the loop also calls the separate `SYS_poll` entry. Its checks cover
zero/finite empty waits, immediate readiness with an infinite timeout,
sign extension of the low C-int timeout, bad arrays/counts, and a caught
signal interrupting an infinite wait. Retention must stay within 8 KiB,
which detects a 16-byte timeout retained by each of 1,000 `poll` calls.

The tracked ARM reproducer before this fix retains 784 KiB for 1,000 iterations
(1,552→2,336 KiB). Generated C and allocation chains identify 192-byte stat
records and two 16-byte poll slots. With explicit caller-stack slots, the same
ARM guest passes every semantic check and stays exactly flat at 1,536 KiB.
The x86 guest also passes every check and stays flat at 1,000 KiB. Both
architecture generated-C functions have explicit caller-stack slots with no
`memdup`. The repository allocation allowlist has existing failures; no allowances are
changed. Other paths' allocation ownership remains their own repair work.

The separate x86 `poll` entry originally retained 16 bytes per call despite
its fixed-array source declaration. The IPv6 guest exposed 3,000 retained
objects (908→956 KiB). With a conditional caller-stack scalar timeout,
the expanded ABI guest passes all `SYS_poll` cases and stays exactly flat
at 1,020 KiB; the ARM stat/`ppoll` loop stays flat at 1,536 KiB. Both production
architecture builds pass, and the x86 generated `syscall_poll` has one
conditional `vinix_stack_alloc` with no `memdup`.
