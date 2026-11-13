# Software Metal floating sign operations — 2026-11-13

`abb96ba1c` admits direct LLVM `fabs` and `copysign` in bounded AIR buffer
kernels and opt-in software Metal compute, using the existing scalar validator
and evaluator. Half/float operands and results must match. Absolute value
clears the sign bit; copy-sign replaces it from the second operand. Every
magnitude bit, including NaN payload and quiet/signaling bits, is preserved.
Poison propagates and undef rejects, including in the sign donor. Calls cost
one step. Other floating intrinsics, general/indirect/tail calls, call-site
attributes and fast-math calls remain unsupported by this buffer profile.

Normal and ASan/UBSan checks each pass 394,272 exact native LLVM and independent
bit-mask comparisons across four functions. All 65,536 half encodings are
checked for fabs and with both donor signs for copysign. The same sample
counts cover float patterns, supplemented by 32 class/payload boundaries for
fabs and a 32-by-32 operand matrix for copysign: 1,056 float boundary cases.
Another 1,536 native/identity comparisons check that copying a sign and then
restoring it from the original input preserves every input bit, including
through repeated calls to a cached declaration.

The checker verifies four/five/six-step execution, unaligned byte-buffer
offsets, sentinels and insufficient primitive budgets without writes. Twelve
poison/undef guards cover all operand positions. Eight freeze/lazy-select
checks consume/discard computed poison, and nine call-metadata mutations
after a store reject before writes. Guard functions never execute natively.

The initial generic ARM64 reference failed on half copysign of a signaling
NaN. Saved assembly shows half-to-float conversions that quiet it. The checker
now configures only its native LLVM module with the detected host CPU/features
(`apple-m5` here), retaining exact-bit assertions and recording the target.
MCJIT uses optimization level 2 with FastISel disabled. This follows LLVM's
[bit-preserving sign-operation semantics](https://llvm.org/docs/LangRef.html#behavior-of-floating-point-nan-values).
The original failure log and generic/FP16 assembly remain in the bundle.

Sanitized regressions pass all four scalar-intrinsic unit groups, all 16
integer/mixed unit groups, and the previous 32,768 primitive plus 32,768
round-trip buffer bit-permutation comparisons and their controls. Native
JIT-generated code is not sanitizer-instrumented; the interpreter/checkers are.

All 24 software Metal groups pass with normal and deterministic Swift hashing.
Two deferred dispatches check half/float signaling and quiet NaNs and signed
zero. Inputs change after encoding; output sentinels persist until commit;
the pipeline is released before commit. Exact bits are stored via bitcasts,
half-to-i32 zero extension and checked GEPs at two output offsets. Existing
completion/failure and two-runtime resource-drainage checks pass.

Canonical retained evidence:

`/Users/alex/Library/Caches/vinix-ios/air-memory-float-sign-validation-20261113-r1/`

Disk pressure prevented an uncompressed source archive and the first inventory
tool build. Only the owned incomplete source tar was removed. A streamed
`source.tar.zst` succeeded and passes decompression/tar listing and checksum
checks. The compiler snapshot and selected source/header/executable/result
identities match their manifest. Four standalone sanitizer suites replay
successfully from the retained bundle. The relocated software host initially
failed opening its compute fixture after 21 groups during disk pressure;
fresh `replay-software-r2` passes all 24. Failed logs and retry receipts remain
beside the bundle.

The complete tree remains in place. The maintained
`tests/packages/wine-workspace-archive.v` inventory tool, compiled with `-prod`,
recorded and rechecked all file bytes, sizes, types, permissions and link
targets, including the root. Its separate `.inventory.json` receipt is pinned
below. No complete compressed bundle or fresh restore was produced because
of disk space. This inventory does not authorize deleting original evidence
or replace historical launch auditors. No completed evidence or other
sessions' files were removed.

The compiler snapshot was saved after checks. The software harness retains
its documented compiler-preamble corrections. External library symlinks,
SDKs, assembler and dylibs are not a sealed dependency closure. Leak detection
is disabled; runtime object drainage is checked, retained heap is not measured.
The ordinary runner was not rebuilt. Execution remains a bounded single-thread
CPU interpreter with valid LLVM IR as a precondition. Synthetic fixtures do
not establish Apple compiler-produced kernel compatibility. No GPU rendering,
presentation, Vinix guest, Fortnite frame or launch gate is verified.

| Artifact | SHA-256 |
| --- | --- |
| `.inventory.json` beside bundle | `efbbfc632cf402d46a6d1f7eaec537b437fdb99737582c4fc195871bc85e9a11` |
| `identities.sha256` in bundle | `de2b20d8dc135e2ce533c9ae9b62272f2079910aa4b693e1c7aedf91e8f0bbfb` |
| `source.tar.zst`, revision `abb96ba1c` | `f9bf6da7bbf566531e44788fb913a6ffe6b516bcffd71abd1ed0b7a5f5becca4` |
