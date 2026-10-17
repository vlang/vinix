# Prepared-root lookup ownership

This records the lookup/recheck increment. Subsequent
[materialization ownership checks](import-materialization-ownership-check.md)
also cover recursion, directory construction and file-opening scratch. Complete
private import workspace/profile construction remains a separate boundary.

Prepared-root source lookup and consistency rechecks now retire their temporary
path storage on success, link/parent restart and refusal. The returned file
descriptor and stat fields remain usable after that storage and the caller's
source string are freed. Source checks still resolve in the captured guest root,
including guest-absolute aliases and parent components after intermediate links.

The retained baseline measures **503 bytes / 10 allocations** left by one ordinary
file lookup and **8,574 bytes / 365 allocations** by one cyclic path lookup.
Those costs accumulated for every selector, descendant and consistency recheck.
The baseline runs four warmed attempts for each of 20 path cases and records
the maximum retained bytes and allocations per attempt.

The resolver now owns its pending path and split strings. Its prefix buffer
borrows split components and is freed separately, avoiding implicit string
clones. Each restart produces one independent path with a preflighted 4096-byte
limit; replaced pending paths and temporary link targets are freed. Synchronous
`fstat` calls use stack records rather than escaped heap copies. Returned
descriptors keep their existing ownership contract.

The measured scope is source resolution and its consistency rechecks. It does
not establish zero retention for whole materialization, packing or publication,
and does not replace the stable-input requirement with an atomic snapshot.

## Assertions

The [core fixture](../../tools/packages/pkgcore/import_lookup_test.v) checks:

- 20 path cases: ordinary file/directory, absolute/relative aliases, parents after
  intermediate links, repeated separators/dot components, exactly 40 links,
  nonblocking FIFO capture, missing/non-directory paths, trailing file separators,
  root resolution, escapes, cycles, 41 links, unsafe targets and oversized input.
- Eight consistency rechecks: unchanged file/directory/alias, executable or length
  changes, an identical replacement inode, missing input and an unavailable root.
- 128 warmed attempts per case under allocation tracking: **3,584 attempts** with
  no retained lookup/recheck bytes or allocations. Descriptor counts stay flat.
  Ordinary functional builds use eight attempts per case.
- Returned descriptors after source-text retirement and host root replacement.
  Both original and rechecked descriptors still read the retained guest bytes.
- Independent absolute/relative restart paths at exactly 4096 bytes, refusal at
  4097 bytes and preserved suffix/parent ordering.

The [host driver](import-lookup-check.v) builds the real package CLI and runs
18 assertion suites, signed CLI maintenance, three ASan/UBSan suites and the
tracked ownership fixture. Existing source-consistency mutation, traversal bounds,
root/recipe admission, direct packing, catalog/plan/composition/release and all five
publisher-profile checks remain included. Sanitizer leak detection is disabled;
the separate warmed tracker measures resolver retention.

The [guest controller](import-lookup-runtime-check.v) builds seven assertion
programs. Lookup ownership uses `-d track_heap -manualfree` on both target
architectures; the other six check source consistency, traversal bounds, ordinary
imports, direct packing, catalog builds and signed releases. Each guest must
complete every process/ownership/mutation marker and initiate poweroff. Receipts
pin ten artifacts: kernel, PID 1, seven runners and raw serial output.

## Reproduction

```sh
v -o /tmp/import-lookup-check tests/packages/import-lookup-check.v
V=/path/to/reviewed/v /tmp/import-lookup-check /build/new-import-lookup-host

v -no-skip-unused -path '@vlib|@vmodules|.|tools/accounts|tests/hardware-platform' \
  -o /tmp/import-lookup-runtime-check tests/packages/import-lookup-runtime-check.v
VINIX_HWTEST_TCG=1 V=/path/to/reviewed/v VFLAGS=-nocache \
  /tmp/import-lookup-runtime-check --arch aarch64 --kernel /build/aarch64-kernel \
  --state-dir /build/new-import-lookup-arm
```

Repeat for `x86_64` with its matching kernel and a new state directory. The
controller requires explicit QEMU TCG opt-in and a fresh state path. `--list`
creates no guest. Cross-toolchain setup follows the
[hardware controller requirements](../hardware-platform/README.md).

## Qualification, 2026-10-16

All **47 host build/run checks passed**, including three ASan/UBSan suites and
the separate ownership tracker. Four controller list/input/existing-directory
guards passed. Fresh **AArch64 (94.6 seconds)** and **x86-64 (49.4 seconds)** guests
completed all seven assertion programs and initiated QMP shutdown within the
180-second deadline. Each target reports zero retained bytes and allocations
for all 3,584 measured lookup/recheck attempts.

- [Baseline observations](results/2026-10-16/import-lookup-baseline.txt) and
  [baseline pins](results/2026-10-16/import-lookup-baseline.json).
- [Host receipt](results/2026-10-16/import-lookup-host.json),
  [all checks](results/2026-10-16/import-lookup-host.txt),
  [functional assertions](results/2026-10-16/import-lookup-core.txt) and
  [tracked ownership](results/2026-10-16/import-lookup-memory.txt).
- [Lookup sanitizer](results/2026-10-16/import-lookup-asan.txt),
  [source-consistency sanitizer](results/2026-10-16/import-lookup-capture-asan.txt),
  [catalog sanitizer](results/2026-10-16/import-lookup-catalog-asan.txt) and
  [signed CLI regression](results/2026-10-16/import-lookup-cli.txt).
- [AArch64 receipt](results/2026-10-16/import-lookup-aarch64.json),
  [serial](results/2026-10-16/import-lookup-aarch64.serial.txt) and
  [QMP](results/2026-10-16/import-lookup-aarch64.qmp.txt).
- [x86-64 receipt](results/2026-10-16/import-lookup-x86_64.json),
  [serial](results/2026-10-16/import-lookup-x86_64.serial.txt) and
  [QMP](results/2026-10-16/import-lookup-x86_64.qmp.txt).
- [Source/toolchain/artifact ledger](results/2026-10-16/import-lookup-toolchain.json)
  and [V evidence verifier](results/2026-10-16/import-lookup-retain.v).

The verifier checks all guest artifact hashes, every tracked case and process
marker, source-consistency regression markers, guest shutdown and unchanged
kernel hashes from installed-root Software qualification. The baseline importer
matches the preceding source ledger. This increment changes no kernel code.
Production publisher/catalog migration, graphical/runtime integration and broader
device/crash acceptance remain open in roadmap section 14.
