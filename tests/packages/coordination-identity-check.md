# Unique named package coordination files

Package state locks and application generation leases now require an ordinary
file with exactly one hard link, and a no-follow named lookup must match the
captured descriptor's device/inode. Readers, writers and launches repeat this
check after acquiring their nonblocking lock. Writers acquire exclusion before
changing lock permissions and recheck the named file before handing it off.
All new synchronous `stat` scratch stays on the stack.

Collection and personal-data purge use the same admission through the captured
generation directory, then recheck the lease after exclusive locking. Collection
still admits every eligible generation before any removal. A malformed obsolete
lease leaves other generations, cached objects and recovery data untouched.
Directory/lease identities, held-process protection and descriptor bounds remain
part of collection's existing contract.

Previously a hard-linked state lock was accepted. Writer admission could change
an external file's permissions through that alias, and a shared lease could make
independent generations use one advisory-lock inode. The baseline runs the new
assertion against the previous implementation and records unsafe acceptance plus
the external mode change from `0600` to `0644`.

The [core assertions](../../tools/packages/pkgcore/coordination_test.v) cover six
hard-link entry points (writer, reader, status, launch lease, collection and data
purge), preserved contents/modes and retry after restoring ordinary files. They
keep captured inodes alive while replacing names with ordinary files, symbolic
links, FIFOs, directories or missing entries, and check an unlinked descriptor
and a replaced captured-parent lease. Collection preflight preserves its complete
generation/cache set on refusal and succeeds after repair. With a 32-descriptor
limit, 128 repetitions of six hard-link failures retire descriptors; a busy
writer preserves the existing lock mode and restored admission retains normal
exclusion. Existing FIFO deadlines, fresh reads, live holders and 128 valid and
malformed coordination cycles still run.

The [CLI lifecycle](distribution-cli.v) adds hard links to its bounded malformed
lock probes. Read-only and mutating commands refuse before permission changes,
preserving activation, metadata hashes, cached objects, abandoned stages and
external data. Restoring the original lock permits verified maintenance.

The [target controller](coordination-identity-runtime-check.v) runs the same core
assertions and signed service/CLI maintenance probe on both architectures. Its
five-artifact receipts bind committed kernel, init, both programs and serial log.
This qualifies coordination admission and exercised descriptor lifetimes, not
whole-service heap retention or power-cut/device durability. Controlled state
directories and cooperating workers remain required: no admission check freezes
later administrator namespace changes. Stop package workers and applications
before restoring coordination files, then retry verification. Broader release,
catalog, graphical and runtime gates remain open.

## Recorded results, 2026-10-15

The pre-fix writer accepted a hard-linked lock and changed the external file
from 0600 to 0644. The final core runner refused all six hard-link entry points
while preserving contents and permissions, detected replaced/unlinked names,
preserved the complete collection set on preflight refusal and retried restored
entries. All 128 repetitions of six failures passed under a 32-descriptor limit,
alongside existing valid/malformed coordination and held-process checks.

All 27 final host compile/run results passed: eight core runners, clang ASan/UBSan
for coordination, collection and purge, and signed real CLI lifecycle/maintenance.
The CLI hard-link cases preserved trust/state/cache/recovery data and external
permissions. Leak detection was disabled and undefined behavior was fatal. These
checks qualify exercised safety and descriptor lifetimes, not whole-service heap
retention.

Fresh QEMU TCG runs passed on AArch64 (21.3 seconds) and
x86_64 (34.5 seconds), requiring all four identity markers, signed
maintenance and clean guest shutdown within 300 seconds. Five-artifact receipts
bind committed kernel, init, both programs and serial output. Compiler, sources,
generated C and logs are pinned. Wider runtime, device, catalog and graphical
release gates remain open.

Evidence:

- [before regression](results/2026-10-15/coordination-identity-baseline.txt)
- [host results](results/2026-10-15/coordination-identity-host.json)
- [host summary](results/2026-10-15/coordination-identity-host.txt)
- [coordination assertions](results/2026-10-15/coordination-identity-core.txt)
- [sanitizers](results/2026-10-15/coordination-identity-asan.txt)
- [signed CLI](results/2026-10-15/coordination-identity-cli.txt)
- [source/artifact ledger](results/2026-10-15/coordination-identity-toolchain.json)
- [aarch64 receipt](results/2026-10-15/coordination-identity-aarch64.json)
- [aarch64 report](results/2026-10-15/coordination-identity-aarch64.txt)
- [aarch64 serial](results/2026-10-15/coordination-identity-aarch64.serial.txt)
- [aarch64 QMP](results/2026-10-15/coordination-identity-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-15/coordination-identity-x86_64.json)
- [x86_64 report](results/2026-10-15/coordination-identity-x86_64.txt)
- [x86_64 serial](results/2026-10-15/coordination-identity-x86_64.serial.txt)
- [x86_64 QMP](results/2026-10-15/coordination-identity-x86_64.qmp.txt)
