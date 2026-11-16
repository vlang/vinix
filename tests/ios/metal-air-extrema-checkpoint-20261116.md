# Software Metal AIR integer min/max checkpoint — 2026-11-16

Source revision: `4cd38ea65002c98e7fd788030112833e2094aa45`.

Prepared compute kernels execute `air.min.s.i32`, `air.max.s.i32`, `air.min.u.i32` and `air.max.u.i32`. The exact signed/unsigned naming and binary signatures follow the [AIR declaration builder](https://github.com/vertex-language/air/blob/main/intrinsic.go), whose [compiler comparison cases](https://github.com/vertex-language/air/blob/main/intrinsic_test.go) include unsigned min and signed max. Our tests use synthetic AIR and native LLVM references; those upstream Apple compiler comparisons were not run here.

The four calls reuse existing signed/unsigned extrema IDs, normalization and evaluators. Keys 2156..2159 append four identities, bringing the scalar declaration cache to 2,160 entries without moving earlier keys. AIR/LLVM forms coexist; duplicate identities, exact i32 argument/result types, ordinary direct-call metadata and pure attributes retain their checks. Other AIR widths/vectors remain excluded. Integer-only scalar execution continues to reject calls.

`tests/ios/air-native-integer-extrema.v` passes under ASan/UBSan with LLVM 23.1.5 MCJIT on arm64 Darwin:

- 131,072 native value/address cases exercise both direct and prepared memory APIs, plus 65,536 scalar checks. Eight modes cover each operation alone and alongside its LLVM equivalent. All pairs of sixteen boundary values precede deterministic/equal/complement patterns. Both argument normalization paths, shifted views and complete output padding are checked.
- 96 native loop comparisons check PHI/result-slot reuse and exact executed-step budgets. Another 24 short budgets, 52 state/discard checks and 52 profile/metadata/duplicate refusals pass. State controls cover either operand, source/result freezes and existing scalar undef refusals. Invalid memory profiles preserve marker bytes before writes.
- The previous population-count/bit-reversal checker passes another 131,072 native value/address cases, 65,536 scalar checks and 24 loops. Name, integer-bit, integer-extrema, canonicalization and multiply-high unit binaries also pass; the extrema unit checks 1,267,024 independent values across i1–i64.

The freshly compiled software-final host passes normal and deterministic sizes runs: 448 shader images, 667,228 checked invocations, 212 rejected pipelines and four prewrite bounds failures. Thirty-two image cases exercise the new AIR calls across two image kernels, four shapes and both dispatch selectors. Address calculations and RGBA8 readback retain the independent pixel/padding oracle. Each process checks two drained runtimes.

The initial image fixture exceeded the existing 32-level address-expression bound. Its rejection, exact preparation diagnostic and intermediate diagnostic host remain preserved. The final fixture splits the calls across the two shorter coordinate paths; the limit and expected pixels are unchanged. Image-pipeline failures now print the kernel name and validation error. A qualified checker rebuild also makes its borrowed argument slices explicit.

Generated C confirms a fixed 2,160-entry scalar cache, unchanged 61,604-entry vector cache and allocation-free successful name decoding. Existing owners, result slots, address nodes, snapshots and cleanup are reused; four i64 cache entries add 32 bytes. Heap retention was not measured and leak detection was disabled. Native JIT instructions are not sanitizer-instrumented. This extends CPU software Metal; Apple compiler emission, native GPU execution, rendering and new Fortnite launch/frame evidence remain unverified. No kernel/guest build or broader SIMD/indirect suite was repeated.

Evidence: `/Users/alex/Library/Caches/vinix-ios/air-extrema-20261116-r1`.

Complete archive: `/Users/alex/Library/Caches/vinix-ios/air-extrema-20261116-r1.tar.gz`.

- Archive SHA-256: `2e17c1f2c8abed3d58d2e03a85cec8c4ef3078eea73fddea3f95e35d6f1bfb4e`.
- Typed inventory SHA-256: `7c1e1348c928d964d9ffea077a8d4cdee173fff60da1754345c320c1660b64e7`.
- Source archive SHA-256: `ee34e9b8184eafb6f0947ac9d2723657f23ebf702054c5e61e28b33ae0bf7a6f`.

Complete inventory and archive comparison passes for all logical bytes, paths, types, permissions and links, including root mode. Originals remain retained. Source pins match the feature commit; generated C, IR/bitcode, images, commands, binaries, intermediate attempts and sanitizer logs remain. Captured toolchain libraries are referenced externally, so the bundle is not hermetic. No restoration replay or evidence deletion is claimed.
