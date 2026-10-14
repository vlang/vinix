# Replay-history ownership

History migration previously kept decoded indexes and replaced arrays while
returning replay records that borrowed identity strings from cached snapshots.
That mixed ownership prevented callers from safely retiring either the history
or its source metadata. Updates now clone retained and new identity/key/digest
fields, check the identity limit before building an oversized result, and retire
superseded history and temporary indexes. A failure retires partial results.
Refresh, enrollment, review and publisher release close their owned records;
repository status transfers its history records to the returned status.

The SHA256 helper now releases its digest state and checksum array while
returning the same owned hexadecimal digest. Identity ordering, replay checks,
expired-cache migration, newer-floor preservation, retired-key recovery, JSON
formats and history-before-trust/cache publication ordering remain unchanged.
Synthetic histories may still borrow fields and must not use the owned cleanup.

The [core fixture](../../tools/packages/pkgcore/history_ownership_test.v) checks:

- Results remain usable after retiring source snapshots and earlier histories,
  including serialization/reload and sorted unrelated identities.
- Sixty-four authenticated migrations/retirements remain within 512 bytes and
  five reader allocations per call, preserving source snapshots. This is a
  bounded reader budget rather than a zero-allocation migration claim.
- Later signature/equivocation failure retires partial history without writing
  a history file; a retained newer floor survives an older authenticated cache.
- Replacement at the full 4,096-identity limit and refusal of a new identity
  retire all update scratch after caller cleanup and preserve input records.
- Known SHA256 vectors, block boundaries and binary/Unicode bytes preserve
  digest values with zero retained hashing scratch after caller cleanup.

The paired control uses an absent initial history and the same decoded expired
snapshot. Before cleanup retires the returned array and digest, leaving its
borrowed snapshot identity intact; after cleanup retires the independent owned
result. It measures migration scratch, not fixture setup or whole-service memory.

The [target controller](history-ownership-runtime-check.v) runs these assertions
without heap tracking and the existing signed [maintenance probe](cache-preflight-check.v)
on both architectures with retained committed kernels. Host sanitizers also
exercise enrollment/review/revocation and publishing. Broader catalog memory,
release enrollment, graphical sessions, foreign runtimes and device crash
acceptance remain open.

## Recorded results, 2026-10-14

The paired migration control retained 6,233 bytes / 26 allocations before and
336 bytes / four allocations after retiring the result according to each
ownership contract. The maintained tracked fixture passed 64 migrations within
its 512-byte/five-allocation reader budget. Remaining reader scratch is not
claimed eliminated. Full 4,096-identity replacement/overflow refusal and the
SHA256 helper retained zero scratch after caller cleanup.

Twelve core runners passed: history ownership/schema, retired trust recovery,
administration, repository configuration, publishing release/schema, index and
snapshot schemas, catalog ownership, service and distribution. History,
administration and publishing assertions plus the signed maintenance probe
passed clang ASan/UBSan with leak detection disabled and undefined behavior
fatal. Signed CLI lifecycle, enrollment, revocation, release and maintenance
checks passed. All 41 final host compile/run results are retained. Initial C
compile/link attempts hit host disk exhaustion; their diagnostics are retained
and the final reruns passed.

Fresh QEMU TCG runs passed on AArch64 (20.4 seconds) and
x86_64 (10.8 seconds), running the ownership assertions
and signed maintenance probe before shutdown within 300 seconds. Target runs
do not enable heap tracking. Retained committed kernels exclude concurrent
kernel edits. Five-artifact receipts bind kernel, init, both programs and
serial output; generated C/build logs are pinned. Whole-service memory and
broader release, graphical, runtime and device durability gates remain open.

Evidence:

- [paired baseline](results/2026-10-14/history-ownership-baseline.txt)
- [host results](results/2026-10-14/history-ownership-host.json)
- [host checks](results/2026-10-14/history-ownership-host.txt)
- [history ownership and lifetime assertions](results/2026-10-14/history-ownership-core.txt)
- [signed service probe](results/2026-10-14/history-ownership-probe.txt)
- [sanitizers](results/2026-10-14/history-ownership-asan.txt)
- [signed CLI checks](results/2026-10-14/history-ownership-cli.txt)
- [source/artifact ledger](results/2026-10-14/history-ownership-toolchain.json)
- [aarch64 receipt](results/2026-10-14/history-ownership-aarch64.json)
- [aarch64 report](results/2026-10-14/history-ownership-aarch64.txt)
- [aarch64 serial](results/2026-10-14/history-ownership-aarch64.serial.txt)
- [aarch64 QMP](results/2026-10-14/history-ownership-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-14/history-ownership-x86_64.json)
- [x86_64 report](results/2026-10-14/history-ownership-x86_64.txt)
- [x86_64 serial](results/2026-10-14/history-ownership-x86_64.serial.txt)
- [x86_64 QMP](results/2026-10-14/history-ownership-x86_64.qmp.txt)
