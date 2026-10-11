# Native process and inspection guest tooling

These entry points compile and invoke V directly:

```sh
tests/process-smp/run --arch aarch64|x86_64 [--kernel-dir DIR] [--build-only]
tests/scheduler-qos/run --arch aarch64|x86_64 [--kernel-dir DIR] [--build-only]
tests/tlb/run --arch aarch64|x86_64 [--kernel-dir DIR] [--build-only]
tests/memory-retention/run --arch aarch64|x86_64 [--kernel-dir DIR] [--build-only]
tests/listen-backlog/run --arch aarch64|x86_64 --state-dir FRESH-DIR --build-only
tests/resource-open/run --arch aarch64|x86_64 --kernel-dir DIR --state-dir FRESH-DIR --guest-state-dir PREFIX [--build-only]
tests/proc-thread-lock/run --arch aarch64|x86_64 --kernel-dir DIR --state-dir FRESH-DIR --guest-state-dir PREFIX [--build-only]
tests/proc-map-lookup/run --arch aarch64|x86_64 --kernel-dir DIR --state-dir FRESH-DIR --guest-state-dir PREFIX [--build-only]
tests/aarch64-sigreturn/run --state-dir FRESH-DIR [--kernel-dir DIR] [--musl FILE] [--build-only]
```

The process runner preserves its static musl/serial recipe, repeated C defines
and failure markers, source/expected-marker overrides, x86 CPU model, four CPUs,
4096 MiB and 600-second defaults, and rejection of fewer than two CPUs. Scheduler
defaults precede user options, including its 8192 MiB setting. Memory retention's
fixed source and markers follow user options, as in its original wrapper. TLB
retains its own source/markers and CPU feature overrides. Existing process
evidence directories remain supported. Default private directories retire on
success or failure; explicitly selected directories remain available.

The independent backlog, inspection and signal commands require fresh build
directories. Their original static C/V compiler recipes and SDK declarations,
allocator guards, immutable control revisions and marker policies remain.
Inspection still compares both original and V variants, exact class/page/UAF
rows, four twelve-child cohorts, minimum progress and exact marker counts.
Captured numbers are compared without narrowing their original unbounded
integer semantics. The map fixture's two `Heap` records now explicitly lend
their stack addresses to synchronous `snapshot` calls. Neither the snapshot
reader nor any C call retains those addresses; all joins precede those records.
Narrow unsafe scopes keep fixed-array access valid without nested unsafe blocks.
The generated object has no allocator imports. Its predicates are unchanged.

Signal return still links the dynamic probe and static init with 64 KiB maximum
page size and packages the genuine selected musl loader, its libc symlink and
the unchanged C sources. It retains both success markers, the 90-second budget,
fresh-directory validation and build/result SHA-256 receipts.

Every actual boot snapshots the matching requested kernel and uses an
uncompressed USTAR initramfs. The already-qualified native ISO builder and
[PTY/QMP supervisor](../../tests/native-guest-tools/README.md) own QEMU, its
firmware variables and socket. Process launch settings are applied directly;
networking is disabled. No kernel is rebuilt or shared guest reused.

`check-process.v CONTROLLER PROFILE [FAMILY]` checks public CLI errors, native
ELF machine IDs, immutable control bytes/hashes, linked-program receipts and
replays the original process, signal and inspection link recipes. All replayed
ELFs match byte for byte. The three host profiles cover seventeen target builds:
eight commands on both architectures and the ARM-only signal command. Use a
fresh profile name to preserve prior evidence. The local qualification helper
uses the private V compiler and prepared kernel snapshots under `/tmp`; the
maintained commands select their normal compiler/environment defaults. `V`,
`VINIX_PROCESS_TEST_ARM_KERNEL`, `VINIX_PROCESS_TEST_X86_KERNEL` and
`VINIX_PROCESS_TEST_BUILD_PREFIX` select durable qualification inputs and output
locations when `/tmp` cannot retain them.

`process_test.v` independently exercises the original report requirements on
both architecture class counts, nonzero/negative/overflowing retention values,
missing/duplicate rows, insufficient progress, exact marker counts, append order
and launch settings. `check-process-cli.v CONTROLLER` checks option rejection,
fresh/reusable evidence directories and twelve failed compiler-owner retirements.
Run owner checks separately because they inspect shared `/tmp` prefixes.

ARM, Rosetta x86 and ARM ASan/UBSan controller builds and report/atomic unit
tests pass. Sanitizer qualification instruments the host controller;
Linux guest fixtures retain their original native recipes. macOS qualification
uses `detect_leaks=0`; it makes no LeakSanitizer claim. Nine cold fronts are
checked outside the checkout. Local evidence is under `/tmp/vinix-process-*`.
No Python is executed and no Linguist classification is changed.

Real ARM guests pass all seven backlog cases, both original/V proc-thread-lock,
resource-open and proc-map-lookup probes, the dynamic-musl signal-return suite
and the small scheduler configuration. Resource/map retention rows match their
independent C controls. These runs use kernel SHA-256
`8866c72f19cba5f95ff22070e193b25cbe0cf57ae89e306067b16a82dba7289f`.
Full SMP, scheduler stress, TLB and memory-pressure guest qualification is not
claimed by this tooling port.

The prepared x86 kernel, SHA-256
`38fb88ad76e81bb26f9d84267678cf98cd0ccc0aae10573b9b83ddd5ca0b3f0a`,
times out in the first unchanged backlog case for both the C control and V
probe. The original proc-thread-lock C control also times out, while a separate
V guest passes with 16,760 snapshots and 4,136 process CPU clocks. The paired
inspection runner retains its original behavior of stopping on a failing C
control. No verdict predicate is relaxed. Temporary build evidence can be
retired by shared-machine cleanup; the checked recipes and limits above remain
documented independently of those local caches.
