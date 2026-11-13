# Software Metal default-environment rounding — 2026-11-13

`967665f2d` admits direct LLVM `rint`/`nearbyint` in bounded AIR buffer kernels
and opt-in software Metal compute. Matching half/float operands/results reuse
scalar integer bit evaluation: nearest integral values with ties to even in
LLVM's default environment, preserved zero signs and preferred quiet NaNs.
Poison propagates and undef rejects; calls cost one step. Host rounding modes
and exception flags do not participate. Dynamic/constrained environments and
exception modeling remain outside the profile, which now admits 41 families.

Normal and ASan/UBSan runs of `tests/ios/air-memory-rounding.v` each pass
917,952 native comparisons across all seven rounding operations. Every half
encoding is tested, alongside 65,536 sampled float encodings per operation
and 448 float class/tie/precision boundaries. The 16,163 NaN-class cases require
native NaN and the exact interpreter preferred quiet choice; the other 901,789
compare exact raw bits, including zero signs. All 2,240 cached/idempotent chains
and 224 host-rounding controls pass.

Another 192 interpreter checks cover rint/nearbyint in both precisions under
four host rounding modes, with clear or pre-seeded divide-by-zero flags. Exact
expected bits cover both signs of 2.5 and 0.5, signaling NaNs and minimum
subnormals. Host modes and exception flags remain unchanged by interpretation;
the incoming rounding mode is restored on exit. Native comparisons use nearest
rounding. This does not qualify dynamic FP semantics or model exception flags.

Four/five-step execution, offsets, sentinels, insufficient primitive budgets,
28 poison/undef guards and 28 freeze/lazy choices pass. Nine initial-call and
126 later cached-call metadata corruptions plus 14 operand-type corruptions
reject before preceding stores. Restored five-step cached baselines compare
against native values. MCJIT uses the detected host target (`apple-m5`),
optimization level 2 and FastISel off. Guard functions never execute natively;
JIT-generated reference code is not sanitizer-instrumented.

Sanitized regressions pass the checker's square-root mode: 327,744 primitives
and 327,744 sqrt/fabs chains, including 18 new cached metadata and two type
guards. Existing FMA/fmuladd checks pass all 678,688 fused-oracle comparisons,
47,680 chains and 11,920 native optional-choice diagnostics with their controls.
Four scalar intrinsic groups and all 16 integer/mixed groups also pass.

All 24 software Metal groups pass with normal and deterministic Swift hashing.
Eight new deferred dispatches mix rint/nearbyint/roundeven in both precisions,
covering both tie signs, signed zero, signaling NaNs, infinities and subnormals.
Forty-eight exact output words pass through bitcasts and checked GEPs. Inputs
change after encoding; sentinels persist until commit. Pipeline/caller buffer
handles are released before commit; eight offset snapshots and two-runtime
object drainage pass.

Canonical complete archive:

`/Users/alex/Library/Caches/vinix-ios/air-memory-default-rounding-validation-20261113-r1.tar.zst`

The 189 MiB bundle contains build receipts, binaries, fixtures/results, compiler
snapshots, LLVM header, selected identity hashes and source.tar pinned to the
feature revision. Decode with
`zstd -dc --long=28 ARCHIVE | tar -xf - -C FRESH_DIRECTORY`.

A fresh complete extraction replaced the original bundle path while retaining
the original under `original-bundle` in the same-prefix directory. The unchanged
maintained `tests/packages/wine-workspace-archive.v` inventory checker matched
every file byte, size, type, permission and link target, including the root.
Selected identities match. All six restored suites pass, including all 24
software Metal groups with normal hashing. The complete inventory matches after
replay and the archive checksum passes. Replay fixtures/logs are retained in
the same-prefix `.replay.tar.zst`; its own inventory matches a fresh extraction.
Both expanded bundles and replay trees remain on disk, with receipts beside
the archives. No earlier completed evidence was removed. These checks do not
replace historical launch auditors.

The standalone compiler snapshot was saved after checks; the harness captured
its compiler before generation. External library symlinks, SDKs, assembler and
dylibs remain unsealed prerequisites. Leak detection is disabled and retained
heap is not measured. The ordinary runner was not rebuilt. Compute remains a
bounded single-thread CPU interpreter requiring valid LLVM IR. Synthetic
fixtures do not establish Apple compiler-produced kernel compatibility. No GPU
rendering, presentation, Vinix guest, Fortnite frame or launch gate is verified.

| Artifact | SHA-256 |
| --- | --- |
| Complete `.tar.zst` | `dcaf34e5e24e7fac0a002a705853289268b35bb2cd86e778838b906274072c9f` |
| `.inventory.json` | `4488540eb419a9481ef9a202cc642a17cd99144475d3aa93af99382cf0d82cab` |
| `.replay.tar.zst` | `ceea1652be237dedd137b86233d53ebaced0b958247586382912243170c97d7f` |
| `.replay-inventory.json` | `4f7446c49b1f997d2732a7f239a62795229a2df1352f69f359163b1f8b7ac2eb` |
| `source.tar`, revision `967665f2d` | `1f7bf84ac52595649fd0feff784ceff20b1a74ac30095e1631a218b3f8d2fc2b` |
