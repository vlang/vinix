# Software Metal AIR i64 vector min/max checkpoint — 2026-11-17

Source revision: `b7c7fbea4b8497a6285c163b1b3ddbf4a821c5df`.

Prepared compute pipelines execute `air.min.s.vNi64`, `air.max.s.vNi64`, `air.min.u.vNi64` and `air.max.u.vNi64` for matching fixed 1..16-lane i64 vectors. Existing signed/unsigned integer comparisons, poison/undef/freeze, result storage and checked address projections are reused. Keys 62036..62099 append 64 identities, bringing vector entries to 62,100. Scalar entries remain 2,179; previous AIR/i32/i64-bit/LLVM keys stay stable. Exact ordinary direct declarations, matching source/result types, pure attributes, duplicate checks and shared limits remain required.

The [AIR declaration builder](https://github.com/vertex-language/air/blob/main/intrinsic.go) supplies signed/unsigned names, generic integer/vector suffixes, binary signatures and pure attributes; its source is retained with a URL and checksum. Fixtures are synthetic. Apple compiler emission and upstream compiler comparisons were not run.

`tests/ios/air-native-vector-extrema64.v` passes under ASan/UBSan with LLVM 23.1.5 MCJIT on arm64 Darwin. Native references use signed/unsigned i64 comparisons and vector selects, independently of the production sign-bit ordering method. Saved disassembly confirms 64 reference bodies with 64 comparisons and no calls. A separate V signed/unsigned comparison also matches every expected lane. No native AIR calls execute.

- 557,056 native reference lanes pass with typed and loaded inputs, each through direct/prepared memory execution. Every lane includes all 16² boundary pairs before deterministic/equal/complement samples. Inputs cover signed endpoints, full unsigned values and 32/64-bit boundaries. Unaligned buffers, markers, complete padding and nonmutating validation pass. Another 2,048 native scalar comparisons and 131,072 scalar/integer vector extractions total 133,120 checks.
- 4,288 scalar/vector address checks include 192 out-of-range vector projection refusals across validation and both memory APIs. Another 704 metadata/source-type refusals, 256 short budgets, 4,096 AIR/LLVM coexistence cases, 384 short input/output buffer refusals and 60 negative name/type/arity/definition profiles pass. Invalid profiles refuse before markers.
- 307 controls cover state/freeze/lane isolation, strict observed undef, address preflight, duplicate declarations, strictfp, vector-PHI reuse, budgets and shared limits. Loops XOR the top bit before comparison through 1,024 visits; scalar/integer expectations and exact 7 × visits + 3 budgets match, while one fewer step refuses. Twelve fixtures retain 4,096/4,097 result-slot and 1,000,000/1,000,016 lane-work boundaries across memory/void/scalar APIs; scalar fixtures also use the integer API. No runtime limit increased.
- Units cover all 62,100 cache identities and exact signed/unsigned spellings. Scalar integer extrema pass 1,267,024 comparisons. Vector integer extrema pass 2,820,096 values, a further 1,267,072-pair sweep and 835,584 poison/undef/freeze checks across i1–i64. Bit operations, saturation, multiply-high, scalar AIR integer, vector clamp/float extrema, FMA/unary names, rounding and canonicalization regressions pass. The unchanged AIR i64 vector bit checker passes 139,264 native lanes and 557,056 lane observations with controls.

A fresh software Metal host passes normal and deterministic sizes runs: 480 images, 702,732 checked invocations, 212 rejected pipelines and four prewrite bounds failures. Sixteen updated min/max images compare all four i64 AIR operations with LLVM and explicit comparison/select expectations. One lane is nonnegative and the other has bit 63 set, distinguishing signed and unsigned order. Checked i64 min/max results reconstruct the output coordinate before truncation to i32; complete comparison checks gate pixel data before the independent RGBA8/readback/padding oracle. Existing i32 operations coexist in the shader. All prior comparison rows remain present in both hashing modes, and the six other AIR image kernels are unchanged. Clipped groups, repeated dispatches and two drained runtimes per process pass.

The initial native checker retained a four-byte coexistence expectation after widening lanes to eight bytes. The corrected checker passes in `reference-verified/`; the failed `reference/` bundle remains. A source comparison in the evidence helper also crossed the end of the inline `image_sizes` string. Its failed check and original helper are retained; the corrected comparison checks each kernel through its actual return. No production evaluator correction was required.

Generated C confirms 62,100 vector and 2,179 scalar entries, without allocations on successful extended name/key paths; error paths retain boxed errors. Sixty-four i64 cache entries add 512 bytes. No evaluator, owner or graph node kind is added. Retained heap was not measured, leak detection was disabled and native JIT instructions are not sanitizer-instrumented.

This extends CPU software Metal. Native GPU execution/rendering and new Fortnite launch/frame evidence remain unverified. No kernel/guest build or broader SIMD/indirect suite was repeated.

Evidence: `/Users/alex/Library/Caches/vinix-ios/air-vector-extrema64-20261117-r1`.

Complete archive: `/Users/alex/Library/Caches/vinix-ios/air-vector-extrema64-20261117-r1.tar.gz`.

- Archive SHA-256: `c3b0b39e5a8c435860a4b3e307f10be98758db5aa4b762712bfc0bf998fc77c7`.
- Typed inventory SHA-256: `f7eefcb2a1568200735329c99cee08fd74f1d70ac58516a302b793745acef0ac`.
- Source archive SHA-256: `ecf5e3c470defc189ceec56753b31e7f271c2800b9d06f354bc3df316c6d1b1d`.

Complete inventory and archive comparison passes for logical bytes, paths, types, permissions and links, including root mode. Originals remain retained. Source pins match the feature commit. Generated C, IR/bitcode, native disassembly, images, commands, binaries and sanitizer logs remain. Toolchain libraries are referenced externally, so the bundle is not hermetic. No restoration replay or evidence deletion is claimed.
