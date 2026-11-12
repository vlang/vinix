# Scalar freeze checkpoint — 2026-11-12

`838dd24e1` executes scalar `freeze` for every i1..i64 width in both APIs,
and half/float in the mixed API. Defined inputs retain every bit, including
signed zero and signaling NaN payloads. Poison and direct undef constants
become a fixed zero choice stored in the existing SSA result slot. Separate
freezes and dynamic loop evaluations may choose the same value under the
[LLVM contract](https://llvm.org/docs/LangRef.html#freeze-instruction).
See [the bounded profile and maintained checkers](../../compat/ios/airbitcode/SCALAR-FREEZE.md).

Preflight checks arity, result, exact operand/result type, zero opcode and
unflagged form, including unvisited blocks. The integer API still rejects
floating types and all calls. Vectors, pointers, aggregates, double and wide
integers remain unsupported. Only freeze's reader admits direct undef;
ordinary undef reads, unsupported expressions, unavailable SSA values and
preceding undefined behavior still error. Production adds no valid-path
allocation, host FP operation or LLVM dependency. Generated C confirms scalar
pool/slot reads and ordinary value copies; the existing three owned temporary
arrays and cleanup remain. Retained allocation was not measured.

Normal and ASan/UBSan focus runs each pass **459,806 exact native LLVM
comparisons** across 66 scalar types, including **1,056 boundary inputs**.
All i1..i16 values and every half encoding are exhausted. Wider integers each
receive 4,096 mixed values; float receives 65,536. Sixteen edges per type
and incoming high-bit noise cover masking, zeros, infinities and NaNs.
Another 1,024 cases pass through the integer API. Frozen input/return takes
two instruction steps.

Arbitrary native choices are not compared against the local zero policy.
Instead, **264 native repeated-use XOR and reflexive-integer-equality branch/
PHI checks**, plus **256 four-iteration native loop comparisons**, establish
choice-independent results. Float values are bitcast before these properties.
Interpreter controls pass for 132 fixed choices, 132 unfrozen poison/undef
results/rejections, 132 budget failures, 384 computed-shift cases, six profile
rejections, ten live/dead-block metadata corruptions and five output corruptions.
A frozen poison branch condition executes without a poison-condition error.
Mixed units check preceding undef arithmetic and division by zero still reject.

Sanitized regressions pass with all maintained controls:

| Suite | Comparisons | Result contract |
| --- | ---: | --- |
| Integer execution | 17,280 | Exact native results |
| Integer flags | 10,240 | 4,845 defined values, 5,395 poison tags |
| Float execution | 649,216 | Includes 5,641 arithmetic NaN-class comparisons |
| Half execution | 2,587,648 | Includes 62,180 arithmetic NaN-class comparisons |
| Half/float precision casts | 1,167,424 | Includes 4,624 conversion NaN-class comparisons |
| Carry-less multiplication | 325,972 | Exact native results |
| Saturating shifts | 651,944 | 445,194 defined values, 206,750 poison tags |

All fifteen mixed execution unit groups and shared intrinsic units pass.
The first regression attempt found the obsolete rejection of scalar freeze;
that diagnostic and its complete fixture/comparisons remain in the bundle.
Four existing fixture generators now reject unsupported i128/double/vector
freezes, preserving their guard counts. The final focus checker positively
covers every newly admitted scalar type. Other full intrinsic, integer/float
conversion and FMA reference suites were not rerun; their numerical helpers
were unchanged. Native LLVM/JIT code is not sanitizer-instrumented; leak
detection is disabled. Existing usize FFI warnings remain.

Mixed execution units also link as a static little-endian AArch64 Linux ELF,
with no INTERP/DYNAMIC segment. No guest execution was performed.

Complete evidence is retained outside Git:

`/Users/alex/Library/Caches/vinix-ios/air-freeze-validation-20261112-r1/`

It contains pinned source, fixtures, bitcode, all comparison output, binaries,
generated C, versions, selected compiler hashes, logs and reproduction notes.
The full compiler/SDK/LLVM/JIT/sanitizer dependency closures are not sealed.
The unchanged complete typed inventory checker passes for the original and
fresh `air-freeze-restoration-20261112-r1/` restore, including every path,
byte, type, size and permission. Whole-archive decoding and extraction exit
zero; the disposable decoded tar was removed afterward. Restored sanitizer
binaries pass all 459,806 comparisons and every focus control again, plus the
mixed execution and shared intrinsic units. Post-replay full original/restored
inventories, relative identities, selected compiler hashes and compressed
archive checksum pass. Replay outputs and receipts remain beside the sealed
bundles.

No AIR shader, iOS application, GPU command or new Fortnite probe ran. The
default Metal device stub still returns nil; no new frame or launch gate
is verified.

| Artifact | SHA-256 |
| --- | --- |
| Inventory JSON beside bundle | `71c5736eef768117e9450b8bc1b9d94b02b21063a6bd6b804124d69303bfcc45` |
| Complete `.tar.zst` beside bundle | `2deec0dcc28c2c3c344ac25863b0f7a16892d23953e938d679a4267e89e7ab59` |
| `source.tar`, revision `838dd24e1` | `f49cbe049340687f6e4d4d9742dcad64f53896ff57577b4bd9e9d999d5059eff` |
