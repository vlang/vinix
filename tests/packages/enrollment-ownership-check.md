# Repository enrollment and review ownership

Enrollment now retires loaded index text if the subsequent signature read fails,
and retires both strings if publisher/signature/metadata admission fails. Success
transfers both owned strings and an independently decoded index; the publisher
identity remains borrowed. Authentication time is still sampled after both reads.
Acquisition retires its temporary URLs and paths on success or refusal.

Proposed configurations explicitly own their array and cloned new publisher
identity. Retained publisher fields and policy borrow the current configuration.
Refusal releases the new identity and array; temporary read-only reviews retire
the same owned pieces after use. Reviews clone their returned fields before
retiring private configuration/snapshot/history data. A rejected review releases
its partial fields, digest and fingerprint. Public apply results keep their
existing ownership and trust publication order.

The metadata reader's `stat` pointer is consumed only by synchronous `fstat`
calls. An explicit stack address prevents V from moving that scratch to an
unreleased heap object. Descriptor admission, size/sentinel bounds, no-follow
flags, callbacks and captured-file rechecks remain in place.

The [core assertions](../../tools/packages/pkgcore/enrollment_ownership_test.v)
cover independent snapshot/index lifetimes, sixteen repetitions of six large
authentication/read refusals, authenticated expiry/identity/sequence refusal
and restored offline retry. Warmed proposal and review construction tests check
success and failure cleanup, retained borrowed fields, and independent new
publisher/review fields after source retirement. Public review/enroll/revoke
checks preserve read-only trust state and retained replay history.

The paired read/admission control uses the same 2 MiB index input and bad or
missing signature. The baseline reproduces the original two metadata reads and
verification; the revised control calls the extracted production reader. Both
retire returned indexes or errors. Fixture setup, type-cache warm-up, transport
and whole-service memory are outside this measurement. Zero retention is claimed
for these refusal paths and the measured warmed proposal/review components,
not for all typed JSON readers or complete administration operations.

The [target controller](enrollment-ownership-runtime-check.v) runs functional
assertions without heap tracking and the signed [maintenance probe](cache-preflight-check.v)
on retained committed kernels for both architectures. Broader publisher rollout,
catalog migration, graphical sessions, foreign runtimes and device crash
qualification remain release requirements.

## Recorded results, 2026-10-15

Four warmed calls per case agreed. Rejecting a bad signature retained
2,097,570 bytes / four allocations before and zero after caller cleanup.
A missing signature retained 2,097,297 bytes / two allocations before and
zero after. The maintained fixture passed sixteen repetitions of six large
refusal paths and warmed proposal/review construction with zero retained
component scratch. Accepted typed JSON and whole-service memory are outside
this claim.

All 35 final host compile/run results passed: eleven core runners, tracked
allocation checks, clang ASan/UBSan for enrollment ownership, metadata and
administration, plus signed real CLI lifecycle/maintenance. Core checks cover
configuration, replay recovery/history, signature admission, catalog ownership,
service and distribution. Sanitizer leak detection was disabled and undefined
behavior was fatal. The integrated distribution runner and controller compiled.
Initial runner log creation and guest launch hit host ENOSPC; setup diagnostics
are retained and final reruns passed after reclaiming completed unpinned media.

Fresh QEMU TCG runs passed on AArch64 (18.4 seconds) and
x86_64 (40.6 seconds), running the functional assertions
and signed maintenance before shutdown within 300 seconds. Target runs do not
enable heap tracking. Five-artifact receipts bind committed kernel, init, both
programs and serial output. Source, generated C, logs, compiler and artifacts
are pinned. Wider release, graphical, runtime and device gates remain open.

Evidence:

- [paired memory control](results/2026-10-15/enrollment-ownership-baseline.txt)
- [host results](results/2026-10-15/enrollment-ownership-host.json)
- [host summary](results/2026-10-15/enrollment-ownership-host.txt)
- [ownership assertions](results/2026-10-15/enrollment-ownership-core.txt)
- [sanitizers](results/2026-10-15/enrollment-ownership-asan.txt)
- [signed CLI checks](results/2026-10-15/enrollment-ownership-cli.txt)
- [source/artifact ledger](results/2026-10-15/enrollment-ownership-toolchain.json)
- [aarch64 receipt](results/2026-10-15/enrollment-ownership-aarch64.json)
- [aarch64 report](results/2026-10-15/enrollment-ownership-aarch64.txt)
- [aarch64 serial](results/2026-10-15/enrollment-ownership-aarch64.serial.txt)
- [aarch64 QMP](results/2026-10-15/enrollment-ownership-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-15/enrollment-ownership-x86_64.json)
- [x86_64 report](results/2026-10-15/enrollment-ownership-x86_64.txt)
- [x86_64 serial](results/2026-10-15/enrollment-ownership-x86_64.serial.txt)
- [x86_64 QMP](results/2026-10-15/enrollment-ownership-x86_64.qmp.txt)
