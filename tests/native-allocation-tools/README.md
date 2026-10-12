# Native allocation tools

The allocation tests, VM runners, SSH runner, kext builder and selected saved
campaign commands now compile and invoke V directly. Their implementation is
`allocationhost`; no Python process or object transport is needed. The original
22 Python files, 72,433 bytes / 1,562 lines, are identified by Git blob and
SHA-256 in [the translation receipt](native-translation.json). Immutable C
references and historical measurement captures remain independent inputs.

| Public command | Workflow |
| --- | --- |
| `tests/alloc-bench/test-v-bench` | Six host workloads or complete C/V fault comparison; static guest fixture |
| `tests/alloc-bench/test-v-sampler` | Native or original C ownership fixture; static guest fixture |
| `tests/alloc-bench/run-vinix` | Rootfs staging, ISO identity check and private benchmark VM |
| `tests/alloc-bench/run-kernel-vinix` | GNU compiler admission, untimed V init and validated kernel sampler VM |
| `tests/alloc-bench/run-macos` | Guest GCC through SSH, optional SDK assembly/linking, benchmark supervision |
| `tests/alloc-bench/build-macos-kext` | GNU Darwin probes, static descriptor, Apple assembly/linking and bundle manifest |

The same directories also contain native replacements for three saved Vinix
runners, eight saved campaign drivers and three recorded-console commands.
Saved drivers preserve their origin-derived root, child working directory,
suffix replacement, UTC timestamps, combined runner log and exit record. Their
child executable contains the complete native runner or serial/QMP observer.
The excluded preboot runner retains its obsolete artifact lookup and its
existing failure; it is not silently upgraded to the corrected runner.

Commands retain their existing required inputs, benchmark counts, compiler
flags, source and executable hashes, guest markers and deadlines. Static test
builds add `--build-only` so both target artifacts can be checked without a
kernel boot. Existing state directories are rejected. Rootfs copies preserve
file metadata and symbolic links, including dangling links. ISO extraction
must match the supplied kernel, and recorded libc hashes must match staged
files. The kernel runner validates all three sampler phases before success.

The benchmark comparison retains all 136 original cases, including every
mixed-batch OOM prefix, sample ordering, invalid arguments, syscall and clock
failures, both pipe closes and first-error restoration. It compares complete
status, stdout and stderr against the immutable C implementation. The sampler
keeps its independent success, three-phase OOM/zeroing rollback, clock and kext
callback assertions. Generated objects reject implicit allocator imports.
Host fixtures enable ASan/UBSan; Darwin disables its unsupported leak detector,
while Linux retains leak detection.

The command owner writes child streams directly to an owned log, preserving
write order, partial output, append mode and child cwd. It reserves the leader
PID with WNOWAIT until private process-group retirement and the sole reap.
SIGINT and SIGTERM preserve status 130/143. Failed or interrupted SSH execution
performs bounded cleanup using the unique remote executable and recorded PID.
The serial broker keeps raw bytes and a persistent queue cursor, and publishes
each received packet immediately for live readers. Recorded measurement starts
at the existing console offset and stops the private VM through QMP on success,
failure or either interrupt. Standard QMP greetings are validated, asynchronous
events are skipped, and failed cleanup is reported.

Thirty qualified cold V builds pass across ARM, Rosetta x86 and ARM ASan/UBSan.
Each profile passes the complete 136-case C/V comparison, both independent
sampler fixtures, 30 controlled VM/SSH/kext workflows, CLI and protected-state
checks, twelve compiler/VM/SSH/kext signal cases, real Unix serial/QMP exchanges,
live console visibility and saved-driver success/failure records. Log ownership
checks cover ordered 400 KiB output, append/cwd, failed observers and spawns,
closed stdio, exited-leader descendants and 100 flat descriptor runs. Existing
source-tool and guest-supervisor regressions also pass on all three profiles.

All twenty public fronts pass fresh help builds and shell syntax checks; ten
complete public workflows pass. Eight real static C/V test executables for
AArch64 and x86-64 pass ELF machine and absent-interpreter checks. Controlled
QEMU, SSH and Darwin compiler tools qualify recipes and ownership; this stage
does not claim a fresh kernel build, guest boot, Darwin GCC timing campaign or
kext execution. Private originals, V qualification helpers and logs are retained
at `~/.cache/vinix-allocation-tools-native-20261012`.

To run the controller qualification, compile `test-tools.v`, `test-console.v`
and `test-owner.v` with the selected V compiler. `VINIX_ALLOC_NATIVE_TOOL` names
the separately built `main.v` executable; the controller fixture also needs
`VINIX_ALLOC_REAL_V`, `VINIX_ALLOC_REAL_GCC`, `VINIX_ALLOC_LIMINE` and
`VINIX_ALLOC_KERNEL_LOG`. These identify the compiler, x86 musl cross compiler,
pinned Limine inputs and a complete immutable sampler log. Give socket cases
short state paths, such as `/tmp/vinix-allocation-console`, to respect Unix
socket path limits. `test-tools --drivers NEW_STATE` and
`test-console --drivers NEW_STATE` check the saved drivers separately.
