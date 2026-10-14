# Complete offline mirror admission

Catalog and locked deployment mirrors now recheck the complete staged export
before directory flushing and after the final staging checkpoint, immediately
before exclusive publication. The exact signed index/signature bytes and captured
deployment document must survive unchanged. Only the reviewed repository folders,
metadata files and unique selected object names are allowed. Payload lengths and
hashes are checked again, and conflicting lengths for one hash refuse.

Directory admission opens a no-follow directory descriptor, streams only expected
names, stops at the first extra entry and checks its named device/inode. It never
descends into an unreviewed directory. The private root remains mode 0700 before
flushing; final directories require 0755. Exported files must be ordinary, have
exactly one link and mode 0644. Bounded metadata reads and captured payload hashing
preserve their existing size, alias and identity checks. Synchronous stat records
and borrowed directory-entry views stay on the stack/stream respectively.

Previously a final checkpoint could change the staged index after per-copy
verification; the export still reported ready and published changed metadata.
The baseline runs the new assertion against that implementation and records
`refused=false unpublished=false` before its expected assertion failure.

The [mirror assertions](../../tools/packages/pkgcore/mirror_test.v) add 34 late
mutations before flushing and at readiness: changed/missing/aliased metadata,
changed/missing/aliased/FIFO/hard-linked/permission-changed payload or metadata files,
extra root/repository/object entries and changed directory names/modes. Every
case refuses without completion, cleans staging, preserves source metadata,
installed state, outside data/modes and verified cache, then supports offline
retry. With a 32-descriptor limit, 128 valid and 128 refused scans retain ordinary
descriptor availability; restoring the exact namespace permits retry.

The [deployment assertions](../../tools/packages/pkgcore/deployment_test.v) also
change only whitespace in the staged lock after copying. This still refuses:
publication binds exact captured bytes, independently of whether altered JSON
would parse. The original lock and installed state remain unchanged, and a retry
without upstream objects exports the original approved pins.

The [target controller](mirror-admission-runtime-check.v) runs both assertion
programs on AArch64 and x86_64. Five-artifact receipts bind committed kernel,
init, both programs and serial output. Source, generated C and logs accompany
host sanitizer, signed CLI and target results. The extra full-object scans trade
additional reads for complete-export admission. They do not freeze arbitrary
concurrent administrator edits or qualify physical-media power loss, graphical
sessions or wider runtime compatibility. Normal publication still requires a new
destination and the package writer lock; failures after rename retain the existing
saved-export diagnostic. Broader roadmap release gates remain open.

## Recorded results, 2026-10-15

The pre-fix runner published the changed staged index and reported the mirror
ready. Final checks refused changed metadata, 34 file/namespace/mode mutations
and changed staged deployment bytes, preserving source state, outside contents
and verified cache. No refused export emitted completion or retained its normal
staging tree. Removing upstream objects still permitted a verified retry.
All 128 valid and 128 refused whole-stage scans passed with 32 descriptors.

All 25 final host compile/run results passed: eight core runners, mirror and
deployment under clang ASan/UBSan, and signed real CLI lifecycle/maintenance.
Leak detection was disabled and undefined behavior was fatal. These checks
qualify exercised safety and descriptor lifetimes, not whole-service heap
retention or large-media throughput.

Fresh QEMU TCG runs passed on AArch64 (177.1 seconds) and x86_64 (153.1 seconds),
running both catalog-mirror and locked-deployment assertions and shutting down
cleanly. The first final x86_64 run reached the default 300-second timer after
all mirror assertions passed; the repeat used an explicit `--timeout 600`.
The x86_64 report also retains that timeout, and its full serial/QMP logs are
pinned in the ledger. Five-artifact receipts bind committed kernel, init, both
programs and serial output. Compiler, sources, generated C and logs are pinned.
Wider device, publisher/catalog rollout, graphical and runtime gates remain open.

Evidence:

- [before regression](results/2026-10-15/mirror-admission-baseline.txt)
- [host results](results/2026-10-15/mirror-admission-host.json)
- [host summary](results/2026-10-15/mirror-admission-host.txt)
- [mirror assertions](results/2026-10-15/mirror-admission-core.txt)
- [sanitizers](results/2026-10-15/mirror-admission-asan.txt)
- [signed CLI](results/2026-10-15/mirror-admission-cli.txt)
- [source/artifact ledger](results/2026-10-15/mirror-admission-toolchain.json)
- [aarch64 receipt](results/2026-10-15/mirror-admission-aarch64.json)
- [aarch64 report](results/2026-10-15/mirror-admission-aarch64.txt)
- [aarch64 serial](results/2026-10-15/mirror-admission-aarch64.serial.txt)
- [aarch64 QMP](results/2026-10-15/mirror-admission-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-15/mirror-admission-x86_64.json)
- [x86_64 report](results/2026-10-15/mirror-admission-x86_64.txt)
- [x86_64 serial](results/2026-10-15/mirror-admission-x86_64.serial.txt)
- [x86_64 QMP](results/2026-10-15/mirror-admission-x86_64.qmp.txt)
