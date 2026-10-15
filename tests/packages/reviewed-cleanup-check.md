# Reviewed obsolete generation cleanup

Software’s **Clean up versions** shows architecture, current/rollback generation
IDs and every obsolete generation selected for permanent deletion. The list is
paged; compact windows require enlargement before confirmation and provide Back.
Search/filter/selection in the catalog survive this view. Package launch and
unrelated actions are blocked while it is open. Inspection uses a closeable
read-only worker; applying cleanup cannot be interrupted by closing Software.

`cleanup-review` returns a strict format-1 JSON `CleanupReview`. All fields are
required; unknown/duplicate keys, null/coerced/overflowing counters, invalid
architecture, unordered/duplicate/zero IDs and either retained ID are refused.
The list is bounded to 4096 IDs and the response to 128 KiB. Owned decoding frees
partial results. `cleanup-apply FINGERPRINT` is the only cleanup operation allowed
through `packages-change`; raw `gc` and review commands are excluded.

The fingerprint binds the operation domain, configuration, complete current and
previous states and every eligible generation’s parent, root and lease identity.
Changes to activation, configuration, the set or those identities refuse before
removal. Busy leases are omitted; a released lease changes the eligible set and
requires review again. All complete directory inventories pass admission before
the first removal. Each target is reopened and rechecked during retirement, and
late busy leases stay protected. A normal I/O failure during removal can still
leave partial cleanup; failure diagnostics require inspection and a fresh review.

This operation deletes only obsolete generation directories. Active/rollback
generations, running versions, cached complete and partial objects, interrupted
stages and personal application data are retained. No catalog authentication or
network/policy admission is needed. Raw administrator `gc` remains available for
broader cache/stage collection. The review makes no reclaimed-byte promise: disk
allocation, hard links and filesystem accounting can differ from payload lengths.

The [core assertions](../../tools/packages/pkgcore/cleanup_test.v) cover both
metadata architectures, stale configuration/activation/set/root/parent/lease
approvals, busy/released leases, damaged retained state, unsafe roots, fresh
read-only observation and reader/writer exclusion. In a root guest, UID 1000
reviews root-owned storage with an identical fingerprint and no write access;
a foreign nested directory in the final target refuses before any deletion.

The [real CLI probe](cleanup-check.v) installs a signed application and upgrades
it three times, leases an obsolete generation, checks stale approval refusal,
then cleans up with catalog/trust files unavailable. It verifies current and
rollback payloads, unchanged activation, cached objects, stages and personal data.
The [Software fixture](software_cleanup_fixture.v) covers paging, compact/modal
controls, frozen administrator confirmation, stale failure diagnostics, invalid
replies and reload after success. The maintained [V driver](distribution-check.v)
runs it and the `cleanup-memory` mode alongside existing Software allocation modes.

The [guest controller](reviewed-cleanup-runtime-check.v) exercises the real CLI,
core and protocol on both committed-kernel architectures. These are package CLI
and headless Software checks; ordinary graphical login, production publisher
enrollment, advertised catalog migration and broader foreign-runtime release
qualification remain open roadmap 14 gates.


## Recorded results, 2026-10-15

All 29 host compile/run checks passed, with the maintained Software-only driver
and all twelve allocation modes, both complete desktop architecture typechecks
and core/protocol/administrator/Software ASan/UBSan checks (leak detection disabled).
The owned decoder and cleanup view each retained zero tracked bytes over 1,000
cycles. Final committed-kernel QEMU TCG runs passed on AArch64 (14.0 seconds)
and x86_64 (19.0 seconds), including UID 1000 reading root-owned state,
all-inventory admission, 1,000 owned decoder cycles and the signed real CLI lifecycle,
followed by orderly shutdown. Allocation measurements are host-only; the guest
executes the cycles without the allocation tracker. These are CLI/headless UI
checks; the broader graphical/publisher/catalog/runtime release gates remain open.

- [host checks](results/2026-10-15/reviewed-cleanup-host.json)
- [host summary](results/2026-10-15/reviewed-cleanup-host.txt)
- [core assertions](results/2026-10-15/reviewed-cleanup-core.txt)
- [signed CLI](results/2026-10-15/reviewed-cleanup-cli.txt)
- [Software and maintained driver](results/2026-10-15/reviewed-cleanup-ui.txt)
- [allocation measurements](results/2026-10-15/reviewed-cleanup-memory.txt)
- [sanitizers](results/2026-10-15/reviewed-cleanup-asan.txt)
- [compiler/source/artifact ledger](results/2026-10-15/reviewed-cleanup-toolchain.json)
- [aarch64 receipt](results/2026-10-15/reviewed-cleanup-aarch64.json)
- [aarch64 report](results/2026-10-15/reviewed-cleanup-aarch64.txt)
- [aarch64 serial](results/2026-10-15/reviewed-cleanup-aarch64.serial.txt)
- [aarch64 QMP](results/2026-10-15/reviewed-cleanup-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-15/reviewed-cleanup-x86_64.json)
- [x86_64 report](results/2026-10-15/reviewed-cleanup-x86_64.txt)
- [x86_64 serial](results/2026-10-15/reviewed-cleanup-x86_64.serial.txt)
- [x86_64 QMP](results/2026-10-15/reviewed-cleanup-x86_64.qmp.txt)
