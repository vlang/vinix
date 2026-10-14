# HTTPS destination changes during callbacks

HTTPS download admission now rechecks the captured destination after the
`opened` checkpoint, before starting a producer, after initial/periodic/final
progress, before writing each body chunk, after the `written` checkpoint and
around completion. Each check requires the same named regular inode, captured length
and exactly one hard link. Synchronous `stat` scratch stays on the stack.

A link, size or pathname change refuses before another body write or successful
transport result. Initially retained bytes survive mutations at admission and
initial progress. Later changes retain exactly the bytes present at the mutation;
the service never removes or follows a replacement pathname. Restoring ordinary
output permits retry. Fresh truncation still waits for the first body bytes or
successful empty EOF, and range refusal still permits one fresh attempt.

Captured descriptor flushing retries `EINTR`. Other storage failures report that
partial data may need retry after checking storage. The in-process flush hook is
private qualification machinery; production still calls `fsync`, uses the fixed
curl executable and retains the existing certificate, protocol, size and timeout
bounds. No CLI/environment switch selects these hooks.

The [core assertions](../../tools/packages/pkgcore/https_output_test.v) add 72
fresh/resumed combinations: six callback/checkpoint positions and six mutations
(hard link, growth, symlink, FIFO, ordinary replacement and removal). They record
the exact bytes at mutation, require refusal without subsequent writes, preserve
outside contents/modes and replacement names, check no request after an admission
mutation, reap every producer and retry restored output. A further 96 cycles
exercise interrupted flushes, storage failures and link changes during flushing
with a 32-descriptor limit. Existing bounded output, Range fallback, interruption,
empty output, closed descriptors and repeated process retirement also run.

The [target controller](https-output-guard-runtime-check.v) builds this same runner
and the deterministic [V producer](output-fixture.v) for both supported targets.
Its five-artifact receipt binds kernel, init, runner, producer and serial log.
These guests qualify the captured-output contract; real TLS/Range behavior is
checked separately on the host. Controlled directories and package locks remain
required: the checks cannot freeze changes between syscalls or detect arbitrary
same-size in-place edits. Broader release, graphical and runtime gates remain open.

## Recorded results, 2026-10-15

The pre-fix implementation reproduced an overwritten retained prefix after an
admission callback added a hard link. The final runner preserved exact bytes
and refused all 72 checkpoint/progress mutations, then retried restored output.
All 96 flush cycles and the existing descriptor/producer checks passed.

All 30 final host compile/run checks passed: eight core runners, HTTPS output
and recovery under clang ASan/UBSan, signed CLI lifecycle/maintenance, and real
TLS/Range plus seven destination cases. Leak detection was disabled and undefined
behavior was fatal. Initial recovery assertions also counted verification progress;
the fixture now performs health verification without its transfer observer. Initial
logs remain pinned, and the final core/sanitizer reruns passed.

Fresh QEMU TCG runs passed on AArch64 (111.2 seconds) and
x86_64 (195.5 seconds), requiring both mutation/flush markers and guest
shutdown within 300 seconds. Target checks use a deterministic producer; real TLS
is host-qualified. Five-artifact receipts bind committed kernel, init, runner,
producer and serial output. Compiler, sources, generated C and logs are pinned.
Wider runtime, device, catalog and graphical release gates remain open.

Evidence:

- [before regression](results/2026-10-15/https-output-guard-baseline.txt)
- [host results](results/2026-10-15/https-output-guard-host.json)
- [host summary](results/2026-10-15/https-output-guard-host.txt)
- [mutation/flush assertions](results/2026-10-15/https-output-guard-core.txt)
- [sanitizers](results/2026-10-15/https-output-guard-asan.txt)
- [signed CLI](results/2026-10-15/https-output-guard-cli.txt)
- [real TLS](results/2026-10-15/https-output-guard-tls.txt)
- [source/artifact ledger](results/2026-10-15/https-output-guard-toolchain.json)
- [aarch64 receipt](results/2026-10-15/https-output-guard-aarch64.json)
- [aarch64 report](results/2026-10-15/https-output-guard-aarch64.txt)
- [aarch64 serial](results/2026-10-15/https-output-guard-aarch64.serial.txt)
- [aarch64 QMP](results/2026-10-15/https-output-guard-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-15/https-output-guard-x86_64.json)
- [x86_64 report](results/2026-10-15/https-output-guard-x86_64.txt)
- [x86_64 serial](results/2026-10-15/https-output-guard-x86_64.serial.txt)
- [x86_64 QMP](results/2026-10-15/https-output-guard-x86_64.qmp.txt)
