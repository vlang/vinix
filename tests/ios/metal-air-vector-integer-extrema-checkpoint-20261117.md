# Software Metal AIR vector integer extrema checkpoint — 2026-11-17

Source revision: `c01d78cf05dac89500f7d15a59e0c5a9d9d78337`.

Prepared compute pipelines now execute `air.min.s.vNi32`, `air.max.s.vNi32`, `air.min.u.vNi32` and `air.max.u.vNi32` for matching fixed 1..16-lane i32 vectors. The [AIR declaration builder](https://github.com/vertex-language/air/blob/main/intrinsic.go) supplies signed/unsigned integer names, vector suffixes, binary signatures and pure attributes; its source is retained with a URL and checksum. Fixtures are synthetic. Apple compiler emission and upstream compiler comparisons were not run.

The change adds declaration decoding and cache identities, reusing the signed/unsigned integer comparison evaluator, result slots, poison/undef/freeze handling and checked address projections. Keys 61876..61939 append 64 identities, bringing vector entries to 61,940. Scalar entries remain 2,179 and previous keys stay stable. Exact ordinary direct declarations, matching source/result types, pure attributes, duplicate checks and shared resource limits remain required. Other AIR integer vector widths remain excluded.

`tests/ios/air-native-vector-integer-extrema.v` passes under ASan/UBSan with LLVM 23.1.5 MCJIT on arm64 Darwin. Native references sign-extend or zero-extend i32 to i64, compare/select and truncate. Saved disassembly confirms 64 reference bodies with 64 widened vector comparisons and no calls. An independent V i64 signed/unsigned comparison also matches every native expected lane. This checks native comparison/select references, without executing native AIR calls.

- 557,056 native reference lanes pass with typed and loaded inputs, each through direct and prepared memory execution. Every lane includes all 16² boundary pairs before deterministic/equal/complement samples. Shifted unaligned buffers, upper argument bits, earlier markers, complete output padding and nonmutating validation pass. Another 2,048 native scalar comparisons and 131,072 scalar/integer vector extractions total 133,120 scalar/integer checks.
- 4,288 scalar/vector address checks include 192 out-of-range vector projection refusals across validation and both memory APIs. There are also 704 call metadata/operand type refusals, 256 short budgets, 4,096 AIR/LLVM vector coexistence cases and 384 short input/output buffer refusals. Sixty negative name/type/arity/definition profiles reject during preparation and direct execution before marker writes.
- 307 controls cover lane poison, strict observed undef, source/result freeze, lane isolation, address preflight, duplicate declarations, strictfp rejection, vector-PHI reuse and executed budgets. Each loop visit XORs the source sign bit before comparison, checking independent i64 expectations through 1,024 visits. Exact budgets are 7 × visits + 3; one fewer step rejects. Twelve boundary fixtures exercise 4,096 versus 4,097 result slots and 1,000,000 versus 1,000,016 lane-work units across memory/void/scalar APIs; scalar fixtures also check the integer API. No runtime limit increased.
- Units cover all 61,940 cache identities and exact signed/vector spelling guards. Scalar integer extrema pass 1,267,024 independent comparisons. Vector integer extrema pass 2,820,096 values, a further 1,267,072-pair sweep and 835,584 poison/undef/freeze checks. Saturating arithmetic, multiply-high, scalar AIR integer, vector clamp/float extrema, FMA/unary names, rounding and canonicalization regressions pass. The unchanged vector saturating checker passes 557,056 native lanes and 133,120 scalar/integer checks with its controls.

A fresh software Metal host passes normal and deterministic sizes runs: 480 images, 702,732 checked invocations, 212 rejected pipelines and four prewrite bounds failures. Sixteen updated min/max images compare all four AIR vectors against LLVM and independent comparison/select expectations. The second lane distinguishes signed from unsigned order. AIR min/max results reconstruct the output coordinate, and full comparison results gate pixel data before the independent RGBA8 readback/padding oracle. Clipped groups, repeated dispatches and two drained runtimes per process pass. Every prior comparison row remains present in both hashing modes. Canonicalization, float extrema, clamp, multiply-high and saturation kernels are byte-for-byte unchanged.

The initial checker passed. A result-column label cleanup was then verified with the final committed checker in `reference-final/`; both successful bundles remain retained. The host passed without runtime evaluator changes.

Generated C confirms fixed 61,940-entry vector and unchanged 2,179-entry scalar caches, without allocations on successful extended name/key paths. Unsupported-input errors retain boxed-error allocation. Sixty-four i64 entries add 512 bytes; no evaluator, owner or graph node kind is added. Retained heap was not measured, leak detection was disabled and native JIT instructions are not sanitizer-instrumented.

This extends CPU software Metal. Native GPU execution/rendering and new Fortnite launch/frame evidence remain unverified. No kernel/guest build or broader SIMD/indirect suite was repeated.

Evidence: `/Users/alex/Library/Caches/vinix-ios/air-vector-integer-extrema-20261117-r1`.

Complete archive: `/Users/alex/Library/Caches/vinix-ios/air-vector-integer-extrema-20261117-r1.tar.gz`.

- Archive SHA-256: `0a918ac8cb4894cccfa2d6fc1343b9ae9bca1292494ebc41374b73026a3bbcae`.
- Typed inventory SHA-256: `834dd7a3b13347dcc2894fcd6dc645b55d73090d49de4a9a4ab9908a3ee52a87`.
- Source archive SHA-256: `8abebc5b1f6c7f25698f67c9f68b9e8b984dd419b2a68471fa65d0d528a90ab9`.

Complete inventory and archive comparison passes for logical bytes, paths, types, permissions and links, including root mode. Originals remain retained. Source pins match the feature commit. Generated C, IR/bitcode, native disassembly, images, commands, binaries and sanitizer logs remain. Toolchain libraries are referenced externally, so the bundle is not hermetic. No restoration replay or evidence deletion is claimed.
