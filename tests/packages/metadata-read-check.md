# Captured, bounded package metadata reads

The shared `read_metadata` API now opens once with `O_RDONLY`, `O_NOFOLLOW`,
`O_NONBLOCK` and `O_CLOEXEC`. It validates the captured descriptor with `fstat`
before reading: only regular files with a nonnegative size of at most 8 MiB are
admitted. Empty files remain valid input to the reader; each schema still decides
whether their contents are valid metadata. Embedded NULs in filenames are refused.

The reader allocates the admitted size plus one sentinel byte and caps every
read to that buffer. It retries `EINTR`, detects extra or missing bytes and checks
the descriptor's size again after EOF. Growth or shrinkage fails with a diagnostic
before parsing. The returned string owns its bytes; the temporary buffer and
descriptor are released on every success/error path. No unchecked file size is
used to allocate or extend a buffer.

Previously type and size checks used path lookups, followed by `os.read_file`
opening the path again and allocating from its new size. A concurrent replacement
could therefore follow a symlink, block on a FIFO or read a larger replacement
before checking its size. The [race qualification](metadata-race-check.v) atomically
exchanges ordinary metadata with a FIFO or symlink while another process makes
10,000 reads. A two-second alarm bounds each reader; the swapping process is
terminated and reaped afterward. The old reader stalls on the FIFO and admits
the symlink target's bytes. The corrected reader returns only captured ordinary
file bytes or a refusal. External contents and permissions remain intact.

An atomic pathname replacement may yield the already captured file, which is
consistent with immutable generation and atomic metadata publication. This is
not a snapshot guarantee against arbitrary same-size in-place writes. Existing
package locks, metadata ownership, signatures, replay checks and schema validation
retain their roles. The helper does not alter payload hashing/copying, parent-path
admission or filesystem crash guarantees.

The [core assertions](../../tools/packages/pkgcore/metadata_test.v) cover empty,
binary, Unicode-path and maximum-length contents; oversized, missing, special,
linked and NUL-containing paths; pathname replacement before/after sizing;
growth, shrinkage and late changes after EOF; restored retry; and owned return
bytes. A sparse file grows to 256 MiB after admission of a two-byte file, exercising
the fixed read bound. Under a 32-descriptor limit, 128 cycles of successful,
special-file and injected interrupted reads exercise descriptor cleanup at each
checkpoint. These checks make no whole-service heap-retention claim.

The [signed CLI lifecycle](distribution-cli.v) replaces configuration, cached
catalog, trust history and active state with FIFOs, directories, live/dangling
symlinks and oversized regular files. Dependent commands must refuse promptly
with exit 1 and no panic, preserving activation, unaffected metadata hashes,
cached objects, abandoned recovery stages and external files. Restoring each
file permits verification of the original generation. The maintained distribution
driver discovers the core assertions and runs both the CLI and race checks.

```sh
v -nocache -no-skip-unused -gc none -manualfree \
  -path '@vlib|@vmodules|.|tools/accounts' \
  -o /tmp/metadata-core tools/packages/pkgcore/metadata_test.v
/tmp/metadata-core
v -nocache -no-skip-unused -gc none -manualfree \
  -path '@vlib|@vmodules|.|tools/accounts' \
  -o /tmp/metadata-races tests/packages/metadata-race-check.v
/tmp/metadata-races /tmp/new-metadata-races
```

`--before` requires the earlier implementation and checks its FIFO/alias failure
statuses. Sanitizers use clang ASan/UBSan with leak detection disabled and
undefined behavior fatal. Guest checks use the maintained composed-catalog
controller with recorded kernels and production sandboxes, rebuilding the
package service and account/session programs from the current sources.

## Recorded results, 2026-10-14

All 40 package-core assertion runners passed. Metadata, service, cached-snapshot
and stored-state runners passed clang ASan/UBSan with leak detection disabled
and undefined behavior fatal. The full signed CLI lifecycle, ELF admission
regression, maintained metadata race check and updated distribution driver
compilation passed. The CLI checked 60 refusals across 20 damaged metadata cases,
with state/cache/recovery preservation and restored verification after each case.

The retained old-source race build reproduces FIFO wait status 14 (alarm)
and symlink wait status 10752 (exit 42: substituted target bytes admitted).
The current reader completes both 10,000-call probes with wait status zero.
The baseline overlay retains the prior package-core sources, with its metadata
reader identical to commit `4f90026e0`; the ledger records those inputs and
compiled witnesses.

Both fresh composed-catalog TCG guests passed every required marker and clean
poweroff: AArch64 in 112.609 seconds, x86_64 in 162.812 seconds. They rebuilt
init, the package service and account/session programs from the final sources,
using retained kernels and production sandboxes. Each receipt admits 79 artifact
hashes, including 70 prepared profile inputs and both build records. Real SQLite
WAL/database and FFmpeg/FFprobe audio workflows passed as the isolated ordinary
account, followed by a SQLite-runtime-only upgrade, rollback, clean uninstall
and offline cache reinstall with database/media retained. QMP logs record guest
shutdown. These checks qualify metadata I/O through package maintenance; public
publisher enrollment, broader catalog migration and graphical/runtime acceptance
remain open.

Evidence: [old-source races](results/2026-10-14/metadata-read-before.txt),
[current races](results/2026-10-14/metadata-read-after.txt),
[host checks](results/2026-10-14/metadata-read-host.txt),
[individual results](results/2026-10-14/metadata-read-host.json),
[signed CLI lifecycle](results/2026-10-14/metadata-read-cli.txt),
[sanitizers](results/2026-10-14/metadata-read-asan.txt),
[AArch64 receipt](results/2026-10-14/metadata-read-aarch64.json),
[serial](results/2026-10-14/metadata-read-aarch64.serial.txt),
[QMP](results/2026-10-14/metadata-read-aarch64.qmp.txt),
[x86_64 receipt](results/2026-10-14/metadata-read-x86_64.json),
[serial](results/2026-10-14/metadata-read-x86_64.serial.txt),
[QMP](results/2026-10-14/metadata-read-x86_64.qmp.txt) and
[source/compiler/artifact ledger](results/2026-10-14/metadata-read-toolchain.json).
