# Package administration metadata ownership

The configuration, consumer replay-history and publisher release-history writers
now serialize into explicitly owned growth buffers and retire both buffer and
returned text on success or failure. Size admission counts the exact persisted
JSON plus its final newline before opening the atomic writer. History keeps its
specific limit diagnostic; configuration and publisher history keep the shared
administration diagnostic. Publication and durable sequence reservation ordering
stay unchanged.

Repository review fingerprints serialize the same identity into owned bytes and
use the owned SHA256 helper. Enrollment/revocation also retire temporary digest
and comparison strings. Review identities combine configuration and history;
they keep their previous hash input without a newline or a new size limit.

The [core assertions](../../tools/packages/pkgcore/administration_metadata_test.v)
cover exact legacy JSON bytes, Unicode/escaping, defaults, empty histories,
maximum u64 counters, both history-reader round trips, review digest compatibility
and sensitivity to every review input. They accept limit-minus-one and exact
8 MiB documents including the newline, refuse overflow/escape expansion, and
preserve existing files and source models on size or publication failure.

With heap tracking, 64 configuration/history/fingerprint passes and eight
oversized refusals must retain zero scratch after retiring returned strings.
The paired control uses 128 history records and the same configuration,
publisher and index digest. It frees all three encoded results and the review
fingerprint in both versions, even though the old writers also retained their
final text. This isolates encoder/hash scratch, rather than fixture creation,
filesystem operations or whole-service memory.

The [runtime controller](administration-metadata-runtime-check.v) runs the core
assertions without heap tracking and the signed [maintenance probe](cache-preflight-check.v)
on both targets. Retained committed kernels isolate these checks from concurrent
kernel changes. Wider release enrollment, catalog migration, graphical sessions,
foreign runtimes and physical storage durability remain separate release gates.

## Recorded results, 2026-10-14

The warmed paired control retained 244,550 bytes / 23 allocations per pass
before and zero after caller cleanup. Four calls in each executable agreed.
The maintained fixture passed 64 accepted encoding/fingerprint passes and eight
oversized refusals with zero retained serializer/hash scratch. This does not
claim zero retention for complete administration operations or metadata readers.

All 37 host compile/run results passed: twelve core runners, tracked-heap
assertions, clang ASan/UBSan for metadata, enrollment/revocation and publishing,
and signed real CLI lifecycle/maintenance. Core coverage includes replay
recovery, history ownership/schema, configuration, service, distribution,
deployment, organization policy and atomic publication. Leak detection was
disabled for sanitizers and undefined behavior was fatal. The integrated
distribution runner and guest controller also compiled.

Fresh QEMU TCG runs passed on AArch64 (28.9 seconds) and
x86_64 (46.1 seconds), running the core assertions and
signed maintenance before shutdown within 300 seconds. Target runs do not
enable heap tracking. Five-artifact receipts bind committed kernel, init, both
programs and serial output; generated C and build logs are pinned. Wider
release, graphical, runtime and device durability gates remain open.

Evidence:

- [paired memory control](results/2026-10-14/administration-metadata-baseline.txt)
- [host results](results/2026-10-14/administration-metadata-host.json)
- [host summary](results/2026-10-14/administration-metadata-host.txt)
- [metadata assertions](results/2026-10-14/administration-metadata-core.txt)
- [sanitizers](results/2026-10-14/administration-metadata-asan.txt)
- [signed CLI checks](results/2026-10-14/administration-metadata-cli.txt)
- [source/artifact ledger](results/2026-10-14/administration-metadata-toolchain.json)
- [aarch64 receipt](results/2026-10-14/administration-metadata-aarch64.json)
- [aarch64 report](results/2026-10-14/administration-metadata-aarch64.txt)
- [aarch64 serial](results/2026-10-14/administration-metadata-aarch64.serial.txt)
- [aarch64 QMP](results/2026-10-14/administration-metadata-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-14/administration-metadata-x86_64.json)
- [x86_64 report](results/2026-10-14/administration-metadata-x86_64.txt)
- [x86_64 serial](results/2026-10-14/administration-metadata-x86_64.serial.txt)
- [x86_64 QMP](results/2026-10-14/administration-metadata-x86_64.qmp.txt)
