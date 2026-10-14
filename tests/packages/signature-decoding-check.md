# Repository signature decoding

The public index verifier previously copied trimmed signature text and used the
general hex decoder, which allocated in proportion to input length before the
64-byte check and retained private scratch under manual memory management.
It now scans borrowed bytes with a fixed 64-byte buffer and allocates an owned
output only after all digits and the decoded length pass. Invalid input cannot
cause an input-sized decoder allocation. The scan remains linear in input size.
Existing transport/cache signature bounds remain in effect.

Compatibility includes mixed hex case, optional `0x`/`0X`, the six ASCII outer
whitespace bytes and an odd 127-digit representation with an implicit leading
zero. Invalid hex still reports its first offending byte and position relative
to the trimmed string, including the prefix. This diagnostic precedes a
wrong-length failure. Index-size and publisher-key checks still precede signature
decoding; signature authentication still precedes metadata schema/identity,
expiry and caller replay-floor checks.

The [core assertions](../../tools/packages/pkgcore/repository_signature_test.v)
compare against the old trim/hex operations across accepted forms, lengths,
prefixes, error positions, all 256 interior byte values and megabyte inputs.
Deterministically signed indexes prove that alternate spellings authenticate
the same bytes and still refuse tampering, expiry, identity and admission-order
faults. Heap tracking requires zero retained decoder scratch after caller
cleanup for 16 repetitions of accepted, malformed and oversized inputs.

The paired control calls the public verifier with the same signed empty index
and canonical, uppercase/prefixed, or 1 MiB wrong-length signatures. It retires
returned decoded indexes or errors in both implementations. It measures retained
verification scratch after a warm-up, rather than fixture setup or allocation
peaks. A remaining one-byte metadata-reader allocation on accepted indexes is
outside the decoder fix; a reader-only control reproduces it without signature
verification. Generated C confirms the fixed buffer and that output
allocation follows digit/length validation.

The [target controller](signature-decoding-runtime-check.v) runs the core
assertions without heap tracking and the signed [maintenance probe](cache-preflight-check.v)
on retained committed kernels for both architectures. Broader publisher rollout,
catalog migration, graphical sessions, foreign runtimes and device crash
qualification remain release requirements.

## Recorded results, 2026-10-14

Four warmed calls per case agreed. Canonical public verification retained
160 bytes / two allocations before and one byte / one allocation after;
prefixed verification retained 289 bytes / three allocations before and one
byte / one allocation after. Rejecting 1 MiB of wrong-length hex retained
1,048,607 bytes / one allocation before and zero after caller cleanup. The
remaining accepted-index byte belongs to metadata decoding. Sixteen repetitions
per accepted/malformed/oversized decoder case retained zero scratch.

All 29 host compile/run results passed: nine core runners, tracked-heap
assertions, clang ASan/UBSan for signature decoding and distribution, and signed
real CLI lifecycle/maintenance. Core checks also cover index schema, retired-key
recovery, replay history, catalog ownership, enrollment/revocation, service and
publishing. Sanitizer leak detection was disabled and undefined behavior fatal.
The integrated distribution runner and target controller also compiled.

Fresh QEMU TCG runs passed on AArch64 (13.4 seconds) and
x86_64 (16.4 seconds), running the functional assertions
and signed maintenance before shutdown within 300 seconds. Target runs do not
enable heap tracking. Five-artifact receipts bind committed kernel, init, both
programs and serial output. Source, generated C, logs, compiler and artifacts
are pinned. Wider release, graphical, runtime and device gates remain open.

Evidence:

- [paired memory control](results/2026-10-14/signature-decoding-baseline.txt)
- [host results](results/2026-10-14/signature-decoding-host.json)
- [host summary](results/2026-10-14/signature-decoding-host.txt)
- [decoding assertions](results/2026-10-14/signature-decoding-core.txt)
- [sanitizers](results/2026-10-14/signature-decoding-asan.txt)
- [signed CLI checks](results/2026-10-14/signature-decoding-cli.txt)
- [source/artifact ledger](results/2026-10-14/signature-decoding-toolchain.json)
- [aarch64 receipt](results/2026-10-14/signature-decoding-aarch64.json)
- [aarch64 report](results/2026-10-14/signature-decoding-aarch64.txt)
- [aarch64 serial](results/2026-10-14/signature-decoding-aarch64.serial.txt)
- [aarch64 QMP](results/2026-10-14/signature-decoding-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-14/signature-decoding-x86_64.json)
- [x86_64 report](results/2026-10-14/signature-decoding-x86_64.txt)
- [x86_64 serial](results/2026-10-14/signature-decoding-x86_64.serial.txt)
- [x86_64 QMP](results/2026-10-14/signature-decoding-x86_64.qmp.txt)
