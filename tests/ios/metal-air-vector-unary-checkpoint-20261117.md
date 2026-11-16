# Software Metal AIR vector unary math checkpoint — 2026-11-17

Source revision: `c4c1928be8084543c9f4500ccff560a573aeae14`.

Prepared compute pipelines now execute fixed 1..16-lane float32 AIR `fabs`, `floor`, `ceil`, `trunc`, `sqrt`, `round` and `rint`. Names use `air.OP.vNf32`. The [AIR declaration builder](https://github.com/vertex-language/air/blob/main/intrinsic.go) supplies vector suffixes and pure signatures; its [compiler comparison cases](https://github.com/vertex-language/air/blob/main/intrinsic_test.go) include vector sqrt. This checkpoint uses synthetic AIR across all 112 bounded shapes. Apple compiler emission for those shapes and upstream compiler comparisons were not run.

The decoder reuses the existing unary lane evaluators and the checked vector call profile. Fabs preserves NaN payloads and clears their sign; arithmetic NaNs use the existing positive canonical encoding. Round takes half ties away from zero; rint and sqrt use nearest rounding with ties to even. Signed zeros and numeric subnormals retain the established software policy. The retained [Metal specification](https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf) permits weaker signaling-NaN/subnormal behavior (page 368); no hardware equivalence for those choices is claimed.

Keys 61604..61715 append 112 separate AIR identities, bringing the vector cache to 61,716 entries. All previous LLVM/scalar keys remain unchanged; scalar entries stay 2,179. AIR and LLVM calls coexist in one function. Exact vector signatures and all call/source types remain checked, including after cache hits. Ordinary pure calls, step/work/slot bounds, local lane poison, strict unfrozen undef and existing freeze/discard rules remain. Half, scalable, fast and other AIR vector families are excluded. Floating address projections still reject before writes.

`tests/ios/air-native-vector-unary.v` passes under ASan/UBSan using LLVM 23.1.5 MCJIT on arm64 Darwin:

- 114,688 typed/loaded vector cases each run through direct and prepared memory APIs: 974,848 native lane comparisons and 57,344 scalar extractions across all 112 shapes. Every lane rotates through 32 boundary words before deterministic samples. Upper binding bits, unaligned shifted buffers, markers and full padding are checked. Mixed AIR/LLVM compositions match LLVM-only native references. Arithmetic expected NaNs alone are canonicalized; fabs payloads remain exact.
- 1,008 state/discard/isolation cases and 448 ordered store/repair cases preserve lane poison, strict undef, source/result freezes, unaffected scalar lanes and preceding stores. Memory controls exercise both APIs.
- 2,240 metadata/type refusals, 560 short budgets, 84 native vector-PHI loops with executed-budget refusals, 896 host-rounding checks, 560 corrupted-result controls, 49 overload/type/arity/address guards and a duplicate AIR identity refusal pass. Invalid profiles preserve output before writes. Saved native disassembly has all 112 LLVM declarations, 238 LLVM call sites and no active AIR calls.
- Units verify all 61,716 cache identities without collisions and the new canonical name/shape boundaries. Existing sign, rounding and sqrt suites pass 4,194,304 raw-bit, 7,340,032 rational binary16 and 1,048,576 squared-midpoint comparisons respectively, plus their state controls. Canonicalization, multiply-high and clamp units pass. The unchanged scalar clamp reference passes 98,304 memory cases and 49,152 scalar cases, including 21,708 domain-poison results.

A fresh software Metal host passes normal and deterministic sizes runs: 448 shader images, 667,228 checked invocations, 212 rejected pipelines and four prewrite bounds failures. Sixteen canonicalization image cases check both lanes of all seven AIR operations against independent coordinate expressions before the RGBA8 pixel/padding oracle. Two drained runtimes per process pass.

Generated C confirms fixed 61,716-entry vector and unchanged 2,179-entry scalar caches. Successful name/index/key decoding allocates no storage; unsupported-input error returns keep the existing boxed-error convention. The appended i64 entries add 896 bytes. Existing evaluators, vector result/PHI owners and cleanup are reused. Retained heap was not measured, leak detection was disabled, and native JIT instructions are not sanitizer-instrumented.

This extends CPU software Metal. Native GPU execution/rendering and new Fortnite launch/frame evidence remain unverified. No kernel/guest build or broader SIMD/indirect suite was repeated.

Evidence: `/Users/alex/Library/Caches/vinix-ios/air-vector-unary-20261117-r1`.

Complete archive: `/Users/alex/Library/Caches/vinix-ios/air-vector-unary-20261117-r1.tar.gz`.

- Archive SHA-256: `4d9cf428f49f601bf93ec6cdd1101619df5fb719c87ab75dde0ff77be3615594`.
- Typed inventory SHA-256: `13cfefa72b24928f792f19eac28817e5de993916b92d588bd929a5de1d4b44fa`.
- Source archive SHA-256: `37eed1265b1b03864398a6bc719a716312231ec34367c66c7dd2d7224248e3a7`.

Complete inventory and archive comparison passes for logical bytes, paths, types, permissions and links, including root mode. Originals remain retained. Source pins match the feature commit. Generated C, IR/bitcode, native disassembly, images, commands, binaries, primary PDF and sanitizer logs remain. Toolchain libraries are referenced externally, so the bundle is not hermetic. No restoration replay or evidence deletion is claimed.
