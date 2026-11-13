# Software Metal masked bit permutations — 2026-11-13

`bfaa4c93b` admits direct LLVM `pext` and `pdep` calls in bounded AIR buffer
kernels and opt-in software Metal compute. Both operands and the result must
have matching scalar i1..i64 types. In low-to-high order, extraction packs
mask-selected input bits into low positions; deposition scatters low input
bits to selected mask positions. Empty masks yield zero and full masks
preserve input. Calls cost one step and reuse scalar validation/evaluation.
The declaration cache covers twenty admitted integer intrinsic families.
See [MEMORY-EXECUTION.md](../../compat/ios/airbitcode/MEMORY-EXECUTION.md).

Poison propagates even with zero input or mask; undef rejects. A poison store
rejects, while freeze or an unchosen select can consume/discard a computed
poison result. General calls, indirect/tail calls, call-site attributes,
fast-math calls and other intrinsic families remain unsupported. Execution
never invokes a host declaration. No shadow tracking or rollback is added.

Normal and ASan/UBSan checks each pass 32,768 exact defined native LLVM
comparisons across 128 primitive buffer functions, including 18,432 boundary
pairs. Another 32,768 native comparisons check both round-trip chains and
independent identities: `pdep(pext(x,m),m) == x & m` and
`pext(pdep(x,m),m) == x & low_popcount_prefix(m)`. Every width i1..i64 has
256 samples per primitive/chain, including empty/full masks, signed limits,
alternating and mixed patterns. The 64-bit full-prefix case avoids shift-by-64.
Native input padding is zero; only unused native destination padding is
masked. Interpreter padding must be zero. Sentinels, exact five/six-step
execution and insufficient-budget rejection without writes are checked.
MCJIT uses optimization level 2 with FastISel disabled.

Another 512 interpreter guards cover poison/undef in either operand with the
other operand zero. There are 256 successful freeze/lazy selections and nine
call-metadata rejections after a store. Guard functions never execute natively.

Sanitized regressions pass 651,944 scalar native comparisons, with 256 poison,
256 undef, 256 budget/isolation, 1,024 mixed-family-chain, 14 metadata, four
type, six name/width and ten result-corruption controls. The independent
position/rank checker passes 651,944 comparisons, exhaustive i1..i8 value/mask
pairs, all widths, 18,432 boundary pairs and both round-trip identities.
All 16 integer/mixed unit groups and 32,768 buffer saturating-shift native
comparisons also pass, including their existing controls. LLVM JIT-generated
reference code is not sanitizer-instrumented; the interpreter and checkers are.

All 24 software Metal groups pass with normal and deterministic Swift hashing.
A deferred dispatch checks extraction, deposition and both chains for
`x=0xd6, m=0x55`, yielding `0x0e, 0x14, 0x54, 0x06`. Inputs change after
encoding, the pipeline is released before commit, and four results are stored
at a nonzero output-buffer offset through checked GEPs. Existing completion,
failure, snapshots and two-runtime resource-drainage checks pass. The ordinary
runner was not rebuilt.

Evidence bundle:

`/Users/alex/Library/Caches/vinix-ios/air-memory-bit-permutation-validation-20261113-r1/`

The complete archive was streamed directly from zstd into fresh `-restored`.
Saved source/compiler/header/executable identities match. All six restored
sanitizer suites pass again, including all 24 software Metal groups with
normal hashing. Fresh replay directories and receipts are retained beside
the bundle. The archive checksum passes afterward. Original evidence remains.

The compiler snapshot was saved after checks. The software harness retains
its documented compiler-preamble corrections. Toolchain library symlinks,
SDKs, assembler and dylibs remain external prerequisites; dependency closures
are not sealed. This is not a full typed-inventory audit. Leak detection is
disabled; runtime object drainage is checked, retained heap is not measured.

Compute remains a bounded single-thread CPU interpreter with valid LLVM IR as
a precondition. Synthetic LLVM/AIR fixtures do not establish compatibility
with Apple compiler-produced kernels. No GPU execution, presentation, Vinix
guest, Fortnite frame or launch gate is verified by this checkpoint.

| Artifact | SHA-256 |
| --- | --- |
| `.tar.zst` beside bundle | `9b4db6b8d266824641141b03eb889ba6a77ed427d21aa56db32b2d11c122bc45` |
| `source.tar`, revision `bfaa4c93b` | `f3c0797770e18cfd3a850cdffa141f5a42c81b27a8c555ea2f1daca80b1a1b73` |
