# Per-index semaphore PID qualification, 2026-10-23

Both native ELF64 architectures pass 261 checks on the corrected Vinix kernel
and Linux 6.12.51 using identical static musl probe ELFs. Both original Vinix
kernels fail exactly 79 checks. Baseline controller status 1 is expected and
does not represent a passing qualification.

| Run | AArch64 | x86-64 |
| --- | --- | --- |
| Original kernel, identical probe | 261 checks, 79 failures | 261 checks, 79 failures |
| Corrected production kernel | 261 checks, 0 failures | 261 checks, 0 failures |
| Linux reference, identical probe | 261 checks, 0 failures | 261 checks, 0 failures |
| Maintained runner, PID case | 261 checks, 0 failures | 261 checks, 0 failures |
| Maintained runner, signed arguments | 276 checks, 0 failures | 276 checks, 0 failures |
| Maintained runner, argument imports | 175 checks, 0 failures | 175 checks, 0 failures |

The probe verifies untouched indices retain their PIDs, SETVAL touches only its
selected index, successful zero and duplicate/net-zero operations record their
caller, queued decrement/zero operations record the original caller rather
than the waker, and refusals/timeouts/signals do not publish tentative results.
It also checks thread-group PID versus TID and all 32 supported indices.

Production builds use isolated candidate
`004aaa782d989515399ccdcd9e94b81094337dcb`, directly based on
`955b4af34bd668722631cef7926be5a0a22cec1e`. Semaphore source SHA-256 is
`c9c74221120bc1dd4c8695eb59a4f151604a4449bef6439e796b89824ecdc186`.
Before/after input maps match. The containing commit integrates this exact
source independently of other sessions' changes to the shared checkout.

`arm` and `x86` retain compiler receipts, probe/generated C/object files, native
and Linux serial logs, production kernel ELFs/generated C, commands, statuses
and maintained-runner results. `review` binds generated-C excerpts to each
production build. The fixed PID array is zero-initialized inside the existing
set allocation (248 added bytes), with no new allocation or lifetime.
Queue ownership and teardown are unchanged.

`attempts` retains failed initial compilations (V reserved identifier `thread`),
their source, and the actual compile/build/boot/controller commands and statuses.
These are separate from the corrected second compilations and completed runs.
The Linux controller passes two positive and nine negative parser controls.
The portable evidence checker exercises nine negative controls, including wrong
check/failure counts, missing/repeated markers, unexpected mismatches/panics,
incorrect baseline mismatch counts and an incorrect ELF architecture.

The first evidence export did not complete: its recorder could not write its
log while free disk space was 116 MiB. `attempts/publish1.recovery.json` records
that observed failure; `tooling/private/partial-export-pins.json` hashes the
discarded incomplete export. The retried collector omits firmware boot media
and links duplicates directly to their canonical retained file.

Compile `tests/linux-compat/sempid-evidence.v` with V without `-prod`, then run
`--self-test` and `check` with this directory. `manifest.json` hashes every
retained artifact and maps original paths to retained files or explicit external
content pins. Duplicate contents use relative symlinks within this bundle.
Large boot media, Linux kernels and external compilers/runtime dependencies are
pinned rather than copied. They are required to reproduce a boot, not to audit
the retained receipts. `completion` records the final checker, manifest and
successful command/status.

This is a native musl semaphore subset. The 32-semaphore/32-operation limits,
SEM_UNDO, IPC permissions/namespaces, remaining semctl commands, GNU libc and
translated/32-bit paths remain separate. This does not qualify desktop package
installation or close the broader libc, sandbox/service and foreign-app gates.
