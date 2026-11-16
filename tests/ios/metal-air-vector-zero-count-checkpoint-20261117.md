# Software Metal AIR vector zero-count checkpoint — 2026-11-17

Source revision: `d2137fa204935450b850ffcc825e136ff95730c7`.

Prepared compute pipelines execute `air.clz.vNi32` and `air.ctz.vNi32` for matching fixed 1..16-lane i32 vectors and a literal i1 flag. False defines the zero count as 32; true produces lane poison for zero. Existing evaluators, strict undef, freeze and checked address projections are reused. Keys 61972..62003 append 32 AIR identities, bringing vector entries to 62,004; scalar entries remain 2,179 and earlier keys stay stable. Exact signatures, ordinary pure calls, source types, duplicate checks and shared limits remain required. The flag is validated per call, including cache hits.

The [AIR declaration builder](https://github.com/vertex-language/air/blob/main/intrinsic.go) supplies the names, vector suffixes, i1 argument and pure attributes; its source is retained with a URL and checksum. Fixtures are synthetic. Apple compiler emission and upstream compiler comparisons were not run.

`tests/ios/air-native-vector-zero-count.v` passes under ASan/UBSan with LLVM 23.1.5 MCJIT on arm64 Darwin. Saved disassembly confirms 32 false-flag and 32 true-flag reference bodies calling only LLVM vector ctlz/cttz, with no native AIR calls. Independent V standard-library counts also match. Native true-flag inputs are made nonzero; no native poison result is executed or compared as a defined value.

- 139,264 native false-flag reference lanes supply 557,056 direct/prepared typed/loaded lane observations. Another 34,816 defined native true-flag lanes supply 139,264 direct/prepared observations of both AIR flags on identical nonzero inputs. Total: 174,080 native reference lanes and 696,320 verified lane observations. Every operation/count includes boundaries, all single-set/single-clear positions and deterministic inputs. Upper bits, unaligned buffers, markers, padding and nonmutating validation pass.
- Mixed zero/nonzero buffers check false counts and frozen true poison independently. Scalar/integer APIs pass 40,960 value/poison checks. There are 2,656 address checks, including out-of-range lane refusals and zero-poison refusal before marker writes. Another 320 metadata/source-type refusals, 128 short budgets, 1,024 AIR/LLVM coexistence cases, 128 short buffer refusals and 32 negative declaration profiles pass.
- 224 cached flag refusals cover undef, poison, dynamic and mistyped flags after a valid call to the same declaration. Another 142 controls cover state/freeze/lane isolation, strict undef, address preflight, duplicate declarations, strictfp, loop reuse/budgets and shared limits. False-flag loops XOR the source on each visit through 1,024 visits; scalar/integer results and exact 7 × visits + 3 budgets match. Twelve fixtures retain the 4,096/4,097 result-slot and 1,000,000/1,000,016 lane-work boundaries. No runtime limit increased.
- Leading- and trailing-zero units each pass 1,410,048 value/poison lanes, 655,424 sweep lanes and 208,896 poison/undef/freeze checks across i1–i64 and both flags. All 62,004 cache identities and bit-operation, integer extrema, saturation, multiply-high, scalar AIR integer, vector clamp/float extrema, FMA/unary names, rounding and canonicalization regressions pass. The unchanged AIR vector bit-operation checker passes its 139,264 native reference lanes and 557,056 lane observations with controls.

A fresh software Metal host passes normal and deterministic sizes runs: 480 images, 702,732 checked invocations, 212 rejected pipelines and four prewrite bounds failures. Sixteen updated `image_sizes` images use one-lane AIR counts in pixel data and compare both two-lane AIR operations and flags against LLVM false counts plus explicit zero masks. Frozen true-flag zero lanes must become zero under this interpreter's freeze choice. Full comparisons gate pixel data before the independent RGBA8/readback/padding oracle. Clipped groups, repeated dispatches and two drained runtimes per process pass. All prior comparison rows remain present in both hashing modes; the six other AIR image kernels are unchanged.

The initial checker incorrectly treated the now-valid three-operand call record as malformed. Its failed `reference/` bundle remains. The checker was corrected and then expanded to compare AIR and native true-flag results on identical inputs. A V loop-variable naming error during that expansion is retained in the failed build log. `reference-complete/` passes with the committed checker; the earlier successful `reference-verified/` bundle remains. A stale cttz unit rejection of already-supported `llvm.clmul.v2i32` now checks unsupported i65. No production evaluator correction was required.

Generated C confirms 62,004 vector and 2,179 scalar entries and no allocations on successful extended name/key paths; error paths retain boxed errors. Thirty-two i64 entries add 256 bytes. No evaluator, owner or graph node kind is added. Retained heap was not measured, leak detection was disabled and native JIT instructions are not sanitizer-instrumented.

This extends CPU software Metal. Native GPU execution/rendering and new Fortnite launch/frame evidence remain unverified. No kernel/guest build or broader SIMD/indirect suite was repeated.

Evidence: `/Users/alex/Library/Caches/vinix-ios/air-vector-zero-count-20261117-r1`.

Complete archive: `/Users/alex/Library/Caches/vinix-ios/air-vector-zero-count-20261117-r1.tar.gz`.

- Archive SHA-256: `c14536a854196265918fff81952bca224968e7de63fbecc0b173ee704001d3c7`.
- Typed inventory SHA-256: `1f9ec78d8e14876b421bc563fc8e4747af8369ece51dff6757c4081ea813df69`.
- Source archive SHA-256: `4a146bd15488660313b7cb59201217d98424482d50492c241355a6fac75a8813`.

Complete inventory and archive comparison passes for logical bytes, paths, types, permissions and links, including root mode. Originals remain retained. Source pins match the feature commit. Generated C, IR/bitcode, native disassembly, images, commands, binaries and sanitizer logs remain. Toolchain libraries are referenced externally, so the bundle is not hermetic. No restoration replay or evidence deletion is claimed.
