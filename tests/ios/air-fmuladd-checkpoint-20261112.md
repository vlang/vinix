# Optional-fusion multiply-add checkpoint — 2026-11-12

`b5afcc7d2` adds `llvm.fmuladd.f16/f32`. LLVM permits either fused or separate
rounding; the interpreter consistently chooses its existing fused implementation.
It retains exact multiplication/addition before one nearest/ties-to-even round,
without host FP, LLVM, libm or new allocation. Strict declaration/signature/
header/attribute checks remain; other widths/vectors, flags, constrained calls
and AIR aliases reject. Poison in any operand propagates; selected undef errors.
See [the contract and oracle distinction](../../compat/ios/airbitcode/SCALAR-FMA.md).

Final normal and ASan/UBSan runs each pass **1,980,544 fused-oracle comparisons**
over ten functions: **1,842,062 exact** and **138,482 NaN-class cases**, checking
Vinix's exact preferred NaN. For optional calls the oracle deliberately uses
native LLVM FMA, qualifying the chosen refinement. Separately,
`native-optional.tsv` records **474,752 actual native fmuladd outcomes**; all
match a native fused or separate result (NaNs compare by class). The latter
check does not relax the production comparison against the fused oracle.

Coverage includes every half encoding in all three operand positions with
mixed-bit peers, float mixed-bit inputs, and 20-by-20-by-20 boundary triples per
function. Cancellation sweeps contain 262,144 cases; **261,568 distinguish
fusion** from separate multiply/add. Twelve poison, twelve undef, six metadata,
five result-corruption and eight distinguishing rounding controls pass, with
budget/integer isolation for both names. FMA units pass 58 exact values, six
unfused controls and optional-name/arity/binary-evaluator guards. Sanitized
intrinsic units pass their existing patterns, 176 extrema values and 327,680
root inequalities; mixed scalar units pass thirteen groups, 1,397,052 narrow
flag cases and 28 i64 limits. Full legacy intrinsic/arithmetic/conversion LLVM
suites were not rerun; their numerical implementations did not change.

Native reference calls use only the default environment. LLVM/JIT/native code
is not sanitizer-instrumented, leak detection is disabled, and retained
allocation was not measured. The thirty-four-entry declaration cache and two
FMA limb arrays are fixed stack storage in generated AArch64 C; existing three
owned execution arrays and cleanup remain unchanged. Mixed scalar units link
as a static little-endian AArch64 Linux ELF and pass header inspection; no guest
execution ran. No AIR shader, application, GPU work or new Fortnite probe ran.
Metal still returns nil; no new frame or launch gate is verified.

Complete evidence is retained outside Git:

`/Users/alex/Library/Caches/vinix-ios/air-fmuladd-validation-20261112-r1/`

It contains source, fixtures/IR/bitcode, every production comparison and native
choice diagnostic, binaries, generated C, logs, identities and reproduction
notes. Qualification uses `reference-normal-final` and `reference-asan-final`;
initial passing corpora precede only operation-family cancellation row labels.
Selected V/LLVM hashes match the pre-build receipt. Full compiler/SDK/LLVM/JIT/
fenv/sanitizer dependency closures are not sealed; existing usize warnings remain.
The unchanged complete typed inventory checker passes for the original and
fresh restore under `air-fmuladd-restoration-20261112-r1/`, matching every path,
byte, size, type and permission. Full file decoding/extraction exit zero.
Restored sanitized FMA/mixed-scalar units and all 1,980,544 comparisons and
474,752 native-choice checks pass again with their controls. Receipts remain
beside the bundles. This qualifies scalar execution and evidence integrity only.

| Artifact | SHA-256 |
| --- | --- |
| Inventory JSON beside bundle | `28945401e3ec5cea2918277950f9c2ff924c1de37168739699f0a4d5d7a631ab` |
| Complete `.tar.zst` beside bundle | `16893686cbd26d8c6c116a27b7f77c95134da6a580f3369177c14fef6f5082ee` |
| `source.tar`, revision `b5afcc7d2` | `17b080c1bbd0bc5fd755e3d0c707c522e675778b8c78803ad4926a59212ef9d2` |
