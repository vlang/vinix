# Organization policy decoding

The core policy-file and public review decoders now use `StoredReader` instead
of generic JSON object decoding. A schema pass checks declarations and types;
the owning reader bounds strings/collections as they are admitted and retires
partially decoded values on all errors. Complete settings use the same reader
as stored configuration with explicit strict/default modes. This preserves
legacy defaults, empty permissions and optional version-pin endpoints.

Returned document/review fields remain independent of source buffers and each
other. Existing `.close()` contracts are unchanged and repeatable. Review
validation borrows its fields and uses fixed-size version validation instead of
discarding an owned array. Canonical policy sorting, public JSON bytes, stale
review identity and atomic policy-only apply behavior remain unchanged.

Matched warmed ten-cycle probes measured original retained storage after the
caller retired results/errors: 10 bytes for a one-pin policy file, 10 for an empty
review, 560 for a one-row review, 180,600 for 64 rows, 7,030 for a truncated review,
550 for borrowed one-row validation and 79,060 for a 64-pin policy file. The same
seven probes now retain zero bytes. Frozen compiler, original sources, generated
C, executables and before/after output are pinned in the result ledger.

`policy_decode_test.v` covers both architectures with one/64-entry repeated
reads, independent owners after source retirement, repeated close and exact
writer bytes. Full 4096-row/pin/allowlist/license fixtures run with a single live
owner outside the tracker's 16,384-allocation table. Separate cases cover legacy
defaults, strict declarations, canonical order, optional pin ranges, empty
permissions, full u64 generations, borrowed validation, every truncated prefix,
required/type/unknown/escaped-duplicate fields, malformed UTF-8/surrogates,
canonical integers, semantic failures, collection limits, exact 8 MiB envelopes
and exact 4096-byte diagnostics. Tracked loops use 1000 cycles; functional
sanitizer loops use 64. Allocation claims concern decoding and validation after
returned values/errors are closed, not the full service operation lifecycle.

The standalone guest controller runs fresh workers for large cases, policy
review/apply fixtures and configuration observation fixtures under frozen
AArch64/x86_64 kernels. It requires a clean poweroff and pins six artifacts per
architecture, including the kernel, init, three fixture executables and serial
log. No kernel is built from the shared checkout. Host checks also cover stored
configuration, schema validation, administrative state, service/deployment
review and the signed CLI flow.

This qualifies the policy decoding increment. Roadmap 14 remains open for
production publisher enrollment, catalog migration, graphical login/display
integration and broader foreign-runtime acceptance.

## Recorded results, 2026-10-16

All **40 focused compile/run checks** passed: fourteen core pairs, two tracked-allocation pairs, one ASan/UBSan pair, four signed CLI/driver checks and two guest-tool builds.

Fresh QEMU TCG guests passed with clean shutdown and six verified artifact hashes each: AArch64 **89.2 seconds**, x86_64 **111.0 seconds**. Deadlines qualify functionality, not performance.

- [before/after policy probes](results/2026-10-16/policy-decode-baseline.txt)
- [host results](results/2026-10-16/policy-decode-host.json)
- [host summary](results/2026-10-16/policy-decode-host.txt)
- [core assertions](results/2026-10-16/policy-decode-core.txt)
- [tracked policies/configuration](results/2026-10-16/policy-decode-memory.txt)
- [sanitizers](results/2026-10-16/policy-decode-asan.txt)
- [signed CLI](results/2026-10-16/policy-decode-cli.txt)
- [source/toolchain/artifact ledger](results/2026-10-16/policy-decode-toolchain.json)
- [aarch64 receipt](results/2026-10-16/policy-decode-aarch64.json)
- [aarch64 report](results/2026-10-16/policy-decode-aarch64.txt)
- [aarch64 serial](results/2026-10-16/policy-decode-aarch64.serial.txt)
- [aarch64 QMP](results/2026-10-16/policy-decode-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-16/policy-decode-x86_64.json)
- [x86_64 report](results/2026-10-16/policy-decode-x86_64.txt)
- [x86_64 serial](results/2026-10-16/policy-decode-x86_64.serial.txt)
- [x86_64 QMP](results/2026-10-16/policy-decode-x86_64.qmp.txt)
