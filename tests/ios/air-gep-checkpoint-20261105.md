# AIR scalar GEP checkpoint — 2026-11-05

`cd8d473d3ead35149e106af3d1d04da01e850eb9` adds scalar GEP byte-offset plans
using the [ABI layouts](air-layout-checkpoint-20261105.md). Plans retain operand
identities, structure offsets, sequential strides and pointer/index widths.
They calculate numeric addresses for supplied scalar index bits. Fortnite
remains at **4/8 observed launch gates**, last seen at the
[GPU requirements alert](controller-discovery-checkpoint-20261104.md). No rendered
game frame, menu, login or playable match is verified. The gate count is not an
engineering completion percentage.

The arithmetic handles signed narrow indexes, wider-index truncation, wrapping
at the pointer index width and preservation of higher pointer bits. Arrays use
element allocation stride; vector element steps use packed store stride.
Structure offsets include packed fields. Scalar pointers/indexes are supported
with pointer/index widths up to 64 bits; wide integers supply their low limb.
Vector-shaped GEPs, unsized/scalable layouts and sub-byte vector element steps
fail explicitly. The plan owns one array and needs no LLVM runtime dependency.
See [GEP.md](../../compat/ios/airbitcode/GEP.md) for APIs, ownership and limits.

Optimized and ASan/UBSan unit runs pass three groups, including exact term IDs,
nested/packed offsets, signs, truncation/wrap, 32-bit pointers, high pointer bits,
distinct array/vector strides, i128 low limbs and empty paths. All 18 malformed,
unavailable, unsupported and value-count cases reject. Existing sanitized memory
and ABI-layout suites pass their original corruption/mutation checks. Leak
detection is disabled; leaks were not measured.

The V inspector independently assembles three LLVM fixture profiles: 64-bit
pointer/index, big-endian 32-bit pointer/index, and 64-bit pointer/16-bit index.
Normal and sanitized comparisons verify 12 scalar plans and 72 address probes;
three vector-shaped GEPs are explicitly excluded. All six corrupted-plan controls
reject changed strides, constant offsets, pointer/index widths, operand identities
and input widths. All fixture assembler statuses are zero.

All 430 copied native modules pass the final sanitized LLVM comparison:

| Native corpus | Modules | Scalar GEP plans | Address probes | Vector GEPs excluded |
| --- | ---: | ---: | ---: | ---: |
| Contacts | 1 | 1 | 6 | 0 |
| MetalFX | 90 | 5,277 | 31,662 | 0 |
| SceneKit | 339 | 2,305 | 13,830 | 0 |
| Total | 430 | 7,583 | 45,498 | 0 |

The checker reconstructs matching LLVM types from the decoded graph, builds
flag-free constant GEPs with six synthetic index/base substitutions and runs
LLVM's `instcombine`. Every folded integer address matches the plan calculation;
term identities/widths also match decoded operands. All three corpus statuses
are zero. This qualifies arithmetic, not the type decoder independently, original
native operand values, flags, provenance or shader execution. LLVM itself is
not sanitizer-built. No generated function executes or dereferences memory.
These are macOS framework samples; Fortnite's packed shaders remain untested.

The unit program cross-compiles and links as a static little-endian AArch64
Linux ELF and passes header inspection. It has not run in a guest. No new
Fortnite probe was run and no runtime Metal capability changed.

Complete evidence is retained outside Git at:

`/Users/alex/Library/Caches/vinix-ios/air-gep-validation-20261105-r1/`

The bundle contains committed source, original libraries/raw modules, folded
LLVM outputs, count receipts, fixtures, binaries, logs, reproduction notes and
tool identities. Final inspectors/corpora/fixtures use `r3`; final unit binaries
are `unit-normal-final` and `unit-asan`. Preliminary build/test failures and older
passing results remain preserved. Compiler, SDK, LLVM dependency and sanitizer
runtime closures are not sealed. Installed tool/library hashes pass recheck.

The unchanged complete inventory checker passes. A full fresh restore under
`air-gep-restoration-20261105-r1/` matches every recorded path, byte, size, type
and permission. Its optimized unit and sanitized LLVM fixture pass again,
including all six controls. Sibling restore/replay logs preserve the results.
Archive and inventory hashes remain unchanged after replay.

| Artifact beside/inside the bundle | SHA-256 |
| --- | --- |
| `air-gep-validation-20261105-r1.inventory.json` | `04d522e9e32ea443fedb1d15695a01af2e5ac371c1725f171c1b1e31f365b69f` |
| `air-gep-validation-20261105-r1.tar.zst` | `9b9b5b0e474ce0cc9939fa8bf690ef6a74827b54447499061140b274dcb5faaa` |
| `source.tar`, revision `cd8d473d3` | `c3a3d5171d130ff6b6ec935ad074d58d7c60def73787edf71fd963e653b81350` |
| `unit-aarch64` | `3ba9ddc1c0ee88c9fbb40c90b5d0c528b6ba4d283d9b185e79afccc2cf4f99c9` |

Raw GEP flags are retained but their inbounds/no-wrap poison rules are not
enforced. Numeric address calculation does not establish pointer validity or a
legal memory access. Global initialization, constant expressions, instruction/
intrinsic lowering, resource/pipeline objects, command execution and presentation
remain unfinished. The default Metal device remains nil. The prior game capture
and historical auditor rejection are unchanged; this is a shader-addressing
prerequisite, not another observed game launch milestone.
