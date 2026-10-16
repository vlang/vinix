# Bounded prepared-root materialization

Prepared-root import now checks traversal work before materializing excessive
output. Previously, regular-file/byte limits applied during import but empty
directories and repeated directory aliases could multiply work until the final
`pack` walk checked the resulting tree. The retained baseline demonstrates the
old importer creating a 129-level directory tree and copying its payload before
that later check could run.

`RootImport` now shares a **32,768-entry** budget across all selectors in a
package. Selected roots, ordinary files, empty directories and each alias visit
consume it. A new import gets a fresh budget. Enumeration collects at most the
smaller of 16,384 names and the remaining aggregate budget, closes its directory
descriptor and retires partially collected names on refusal.

The output permits **128 directory levels**, counting parents named in selector
destinations. A file can sit under exactly 128 parents; a 129th directory or
129-parent file refuses before that output is created. Import and the final pack
walk therefore apply the same depth rule. The final packer still checks all
materialized entries, including implicit selector parents, against its own bound.
Existing source-root capture, guest-only symlink resolution, cycle detection,
file/byte limits, pinned inventory checks, canonical metadata and license policy
remain in force.

Handled failures remove the private workspace. Randomized workspace names include
the process ID for diagnostics; this lets tests check only their own temporary
directories. `pack-root` retires decoded recipe owners, and materialization
retires its name lists, child paths, ancestor buffer, pin map and scratch paths.
This qualification measures traversal and descriptor behavior, not complete
import/packer heap retention.

## Assertions and reproduction

The maintained core fixture exercises:

- A real 129-level tree: refusal before the last directory/payload appears,
  untouched sources and empty ancestor state. Public failure removes scratch
  and leaves no repository; selecting the bounded subtree then succeeds.
- A real exactly-128-level import through `pack-root` and the final packer.
  Nested selector parents cannot bypass the directory/file boundary.
- Shared counters seeded near the production 32,768 limit, using actual ordinary
  directories, empty directories, files and a guest-absolute directory alias.
  Multiple selectors consume the same counter; a new walker can retry.
- 32 repetitions of exact/over-budget enumeration with sorted names and unchanged
  descriptor counts, including failure after collecting only part of a list.
- 32 failed/successful public imports under a 32-descriptor limit, with source
  bytes preserved, no leaked descriptors or process-owned scratch directories,
  and an exact retry after removing a FIFO.

The aggregate-limit tests seed counters to avoid constructing 32,768 directories.
The depth tests construct and import real boundary trees. Existing import tests
exercise absolute/relative aliases, intermediate links before `..`, cycles,
special files, selector ordering and identical canonical manifests.

```sh
v -no-skip-unused -o /tmp/import-limits-check tests/packages/import-limits-check.v
V=/path/to/reviewed/v /tmp/import-limits-check /build/new-import-limits-check

v -no-skip-unused -path '@vlib|@vmodules|.|tools/accounts|tests/hardware-platform' \
  -o /tmp/import-limits-runtime-check tests/packages/catalog-normalize-runtime-check.v
VINIX_HWTEST_TCG=1 V=/path/to/reviewed/v VFLAGS=-nocache \
  /tmp/import-limits-runtime-check --arch aarch64 --kernel /build/aarch64-kernel \
  --state-dir /build/new-import-limits-arm
```

Repeat for `x86_64` with its matching kernel and a fresh directory. The expanded
controller builds eight assertion runners and the package CLI. Every import
boundary marker, the ordinary import process, existing catalog/composition/
release markers and guest-initiated poweroff are required. Baseline-mode output
is forbidden in final runs. Each receipt pins twelve artifacts: kernel, PID1,
eight runners, CLI and serial log. These are publisher/maintenance checks;
they do not execute or qualify additional application runtimes.

## Qualification, 2026-10-16

All **41 host build/run checks passed**, including three ASan/UBSan suites.
Four controller list/input/existing-directory checks also passed. Both fresh
target guests completed every required marker and guest-initiated QMP shutdown:
**AArch64 110.0 seconds**, **x86-64 74.4 seconds**, within the 300-second deadline.

- [Host receipt](results/2026-10-16/import-limits-host.json),
  [boundary assertions](results/2026-10-16/import-limits-core.txt),
  [baseline observation](results/2026-10-16/import-limits-baseline.txt) and
  [baseline pins](results/2026-10-16/import-limits-baseline.json).
- [Boundary sanitizer](results/2026-10-16/import-limits-asan.txt),
  [ordinary import sanitizer](results/2026-10-16/import-limits-import-asan.txt),
  [catalog sanitizer](results/2026-10-16/import-limits-catalog-asan.txt) and
  [signed CLI regression](results/2026-10-16/import-limits-cli.txt).
- [AArch64 receipt](results/2026-10-16/import-limits-aarch64.json),
  [serial](results/2026-10-16/import-limits-aarch64.serial.txt) and
  [QMP](results/2026-10-16/import-limits-aarch64.qmp.txt).
- [x86-64 receipt](results/2026-10-16/import-limits-x86_64.json),
  [serial](results/2026-10-16/import-limits-x86_64.serial.txt) and
  [QMP](results/2026-10-16/import-limits-x86_64.qmp.txt).
- [Source/toolchain/artifact ledger](results/2026-10-16/import-limits-toolchain.json)
  and [V evidence verifier](results/2026-10-16/import-limits-retain.v).

Host coverage includes direct packing, root admission, recipe decoding, all five
publisher profiles, catalog/composition/release and signed CLI maintenance.
Sanitizers use ASan/UBSan with leak detection disabled; no zero-retention claim
is made. Target kernels match earlier installed-root qualification. Broader
publisher lifetime, production catalog, graphical runtime and device/crash
acceptance remain open in roadmap section 14.
