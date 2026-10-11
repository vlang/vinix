# Native opt-in kernel runners

Four Python runners are replaced with direct V commands:

```sh
tests/kernel-stack-guards/run --arch aarch64|amd64 --kernel DIR|ELF [--repo DIR] [--runtime-only] [--expect-overflow]
tests/cpu-mitigations/run [--arch amd64] [--segments] [--cpu MODEL] [--smp N]
tests/smt-policy/run
tests/acpi-sync/run --kernel-dir ISOLATED-WORKTREE/kernel --arch aarch64|x86_64 --v V --state-dir DIR
```

The first three also accept `--state-dir FRESH-DIR` and `--build-only` to retain
cross-build inputs, genuine ELF programs, kernel snapshots and marker policies.
Their default private directories retire on every exit. ACPI retains the
original reusable evidence directory and refuses the primary Git checkout
before writing any output. All four accept native help and reject unknown
options; invalid CPU counts and environment timeouts fail before launch.

Stack guards keep the exact unchanged C compiler/linker recipes, normal opt-in
feature markers, runtime-only behavior, and fatal-overflow precedence. Fatal
checks require the architecture's exact fatal marker and SP diagnostics while
rejecting normal guest pass/fail output. ARM keeps 2048 MiB, the physical private
64 MiB ext2 `/root`, command line, CPU/firmware overrides and fractional native
supervision checkpoints. x86 retains 1024 MiB, two CPUs, the original E1000
network and capture, serial framing, acceleration override and architecture-
specific firmware variable. Kernel inputs may be directories or ELF files.
`VINIX_QEMU_TIMEOUT` retains the default 300-second budget.

CPU mitigation remains x86 only and retains the selected CPU, SMP count,
unchanged instruction probe and either unchanged C guest. Its default kernel
path and runner-root environment overrides remain. The segments C guest includes
the maintained core suite, which now depends on eight V fixture APIs. The old
Python recipe fails with missing `signalfixture-api.h`; the native command
invokes the same maintained fixture generator and strict compile recipes as
`tests/qemu-core/run.sh`, then links those eight objects. No instruction probe,
TLS/LDT assertion or feature marker changes.

SMT keeps one socket, two cores and two threads per core, testing restriction
before enablement. Each retained archive contains the exact one-byte request
and the same V affinity probe. The corresponding ISO receives `vinix.smt=0`
or `vinix.smt=1`; the command-line environment is restored after construction.
The duplicate feature/pass entries remain in the marker list. Its default
budget is 180 seconds and its original kernel/runner/firmware overrides remain.

These three commands reuse the qualified native ABI supervisor: every expected
marker must appear exactly once; any declared failure fails. ARM requests an
immediate monitor exit and allows ten seconds for natural termination, rejecting
forced cleanup and nonzero exit status. x86 captures two further seconds after
completion and retains the original status-independent verdict. Private PTYs,
PIDs, monitors and volumes remain owned until retirement. A final cleanup cannot
turn incomplete output into a pass. Native QMP is an added retirement path.

ACPI retains `make -j4`, selected V/VEXE, architecture and AR, `CC=clang`,
`ACPI_SYNC_TEST=1`, `STACK_GUARD_TEST=0`, ARM `LIMINE_MP=1` and the appropriate
`ld.lld` variable. Merged build output stays in `build.log`; failed builds cannot
launch a guest. Successful builds invoke the native smoke guest with all three
original ACPI/userspace markers. No Python wrapper runs.

`check-optin.v CONTROLLER PROFILE CACHE` checks five actual target builds,
original recipes and byte-identical replays, kernel snapshots, both SMT
archives, CLI errors, and build failure/log ownership in a real Git worktree.
Its native executable stands in for `make` only in the deliberately failed
build tests. `--fronts` cold-builds all four public fronts outside the checkout.
`optin_test.v` checks independent marker counts, fatal policy precedence,
architecture-specific exit semantics, topology and ACPI build arguments.

ARM, Rosetta x86 and ARM ASan/UBSan hosts pass these build, CLI and native unit
checks. macOS ASan uses `detect_leaks=0`; no LeakSanitizer claim is made. The
final controller includes the qualified physical ARM home-volume setup.
Evidence is retained under
`/Users/alex/.cache/vinix-python-zero-process-20261011`.

The real ARM runtime stack guest passes on the unchanged prepared kernel; its
second cohort retains zero physical and slab KiB. The real x86 CPU mitigation
guest also passes every original feature marker, including timer/signal and
thread/migration/process checks. The prepared x86 kernel's
restricted SMT guest fails with `online=4 expected=2`. Extracting the actual
boot ISO confirms `vinix.disk=auto vinix.smt=0`; the original topology and
affinity assertion remain. Its controller stops before the enabled run, as
before. New ACPI kernel builds, opt-in fault/overflow kernels, both-policy SMT
guest success and hardware mitigation effectiveness are not claimed.

Prepared kernel SHA-256 values remain ARM
`8866c72f19cba5f95ff22070e193b25cbe0cf57ae89e306067b16a82dba7289f`
and x86 `38fb88ad76e81bb26f9d84267678cf98cd0ccc0aae10573b9b83ddd5ca0b3f0a`.
The four originals total 14,815 bytes / 284 lines. No source is hidden, no
language attributes change and no Python executes.
