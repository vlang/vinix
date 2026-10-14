# Incremental repository cache preflight

Refresh previously fetched every configured repository and constructed a second
decoded catalog before checking the complete cache encoding against 8 MiB.
Individually valid signed indexes could accumulate beyond that limit and cause
later repository fetches even though the cache could no longer be published.

Refresh now encodes each authenticated snapshot into an owned byte buffer and
checks the exact prefix plus its eventual closing bracket before proceeding to
another repository. Signatures, schema, expiry and retained replay floors still
run first for the current repository. Wrapper fields, array order and signed
text bytes keep their existing encoding. The encoder retains only an accepted
prefix and the current individually bounded record, rather than accumulating
every oversized repository. This is an incremental cache-size check, not a new
transport limit or a zero peak-memory claim.

Fetched text/signatures, their decoded indexes and encoder buffers retire
on all paths. The returned catalog owns independently decoded manifests and
continues borrowing configured publisher identities. Publication still writes
history before replacing the cache; this change does not claim atomic pairing
of those two files or device power-cut durability.

The [core fixture](../../tools/packages/pkgcore/catalog_metadata_test.v) checks
exact legacy JSON equality and reader round trips, empty caches, multiple
repositories, ordering, quote/backslash/Unicode escaping, limit-minus-one and
exact-limit acceptance, one-byte overflow, cumulative overflow and expansion
from JSON escaping. With warmed JSON metadata and `-gc none -manualfree`, heap
tracking checks 16 accepted and 16 oversized encodings after callers retire
returned text/errors. Other reader/service lifetimes are outside that measure.

The signed [public probe](cache-preflight-check.v) maintains an installed seed
generation, then publishes two individually valid large indexes and configures
an unreachable later repository. Service and real CLI refreshes must report the
cache-size diagnostic without contacting that later repository, without a
completion frame and without replacing the active cache, history, generation,
interrupted transaction or partial payload. An invalid current signature must
still report authentication failure first. A smaller authenticated refresh then
publishes successfully and the installed generation remains verifiable.

The [target controller](cache-preflight-runtime-check.v) runs the core assertions
without heap tracking and the signed service probe on both architectures using
retained committed kernels. Broader catalog memory, release publisher enrollment,
graphical sessions, foreign runtimes and device durability acceptance remain open.

## Recorded results, 2026-10-14

The paired two-snapshot host control retained 6,206 bytes / two allocations
with the previous generic array encoding and zero bytes / zero allocations
with the incremental encoder, after retiring the returned text. The final
tracked fixture passed 16 accepted and 16 oversized encodings, exact 8 MiB
acceptance, cumulative/one-byte/escape expansion refusal and reader round trips.
This does not measure whole-service memory.

Eleven core runners passed: cache metadata, catalog ownership, model validation,
index and snapshot schemas, trust recovery, administration, review, service,
distribution and history schema. Core boundary checks and the signed public
probe passed clang ASan/UBSan with leak detection disabled and undefined
behavior fatal. The signed CLI lifecycle and real CLI overflow/retry checks
passed. All 35 host compile/run results are retained.

Fresh QEMU TCG runs passed on AArch64 (10.2 seconds) and
x86_64 (11.1 seconds), each running core assertions and
the signed service probe before shutdown within 300 seconds. Target runs do
not enable heap tracking. Retained committed kernels exclude concurrent edits.
Five-artifact receipts bind kernel, init, both programs and serial output;
generated C/build logs are pinned in the ledger. Broader catalog memory,
publisher enrollment, graphical sessions, foreign runtimes and device crash
acceptance remain open.

Evidence:

- [paired baseline](results/2026-10-14/cache-preflight-baseline.txt)
- [host results](results/2026-10-14/cache-preflight-host.json)
- [host checks](results/2026-10-14/cache-preflight-host.txt)
- [cache encoding and boundary assertions](results/2026-10-14/cache-preflight-core.txt)
- [signed service probe](results/2026-10-14/cache-preflight-probe.txt)
- [sanitizers](results/2026-10-14/cache-preflight-asan.txt)
- [signed CLI checks](results/2026-10-14/cache-preflight-cli.txt)
- [source/artifact ledger](results/2026-10-14/cache-preflight-toolchain.json)
- [aarch64 receipt](results/2026-10-14/cache-preflight-aarch64.json)
- [aarch64 report](results/2026-10-14/cache-preflight-aarch64.txt)
- [aarch64 serial](results/2026-10-14/cache-preflight-aarch64.serial.txt)
- [aarch64 QMP](results/2026-10-14/cache-preflight-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-14/cache-preflight-x86_64.json)
- [x86_64 report](results/2026-10-14/cache-preflight-x86_64.txt)
- [x86_64 serial](results/2026-10-14/cache-preflight-x86_64.serial.txt)
- [x86_64 QMP](results/2026-10-14/cache-preflight-x86_64.qmp.txt)
