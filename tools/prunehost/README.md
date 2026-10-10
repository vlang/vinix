# Native build archive pruning

`tools/prune-build-artifacts` runs V directly. Existing root, age, repeated keep,
dry-run and automatic options are retained. Selection remains shallow: normal
build archives, desktop-perf ISOs and recognized temporary initramfs archives.
VM disks, staging/download trees and the ordinary desktop cache are preserved.

The command holds the existing workspace lock, keeps explicit overrides and
markers, and inspects process arguments/environments and open descriptors before
deleting anything. Process environments are consumed internally and are never
logged. Inspection failures prevent deletion; automatic cleanup reports a skip
and returns success. The cutoff is computed after taking the lock. File state is
checked again just before removal, including native nanosecond timestamps.
Only the ISO's disposable JSON sidecar is removed with it. Freed space uses the
SDK's allocated block count rather than the logical file size.

The header contains SDK type/field aliases only. Selection, ownership, parsing,
inspection, deletion and reporting are implemented in V. No Python command or
import bridge is involved.

Run the pruning suite through `tests/build-cache/run.sh`, or run
`tests/build-cache/test_prune_build_artifacts.v` using the repository's V tool
runner. `VINIX_PRUNE_TOOL` optionally selects a prebuilt production executable.
`tests/desktop-bootstrap/run-runner.sh` checks help, cold dependencies, warm
dependencies, no-build ordering and an explicit compiler override. Its fake
commands are V executables.

Qualification on 2026-10-11 covers ARM, actual Rosetta x86 binaries and ARM
ASan/UBSan, using an isolated rebuilt V 0.5.2 `c6bb06f` compiler. Native tests
cover retention ages, Unicode names, sidecars, dry runs, repeated keeps, markers,
symlink boundaries, concurrent replacement, inspection failures, open files,
another process's selected input, automatic opt-out, lock contention and repeated
descriptor retirement. Real ps/lsof inspection is exercised; V process fixtures
also check lsof statuses and redacted failures. Logs are
`/tmp/vinix-prune-{test,front}-{arm,x86,san}.log` and
`/tmp/vinix-bootstrap-{arm,x86,san}.log`.

No Python was executed, no real workspace archives were deleted, and these
host checks do not establish a new guest boot. The other desktop bootstrap
Python suites remain counted until their own workflow ports are complete.
