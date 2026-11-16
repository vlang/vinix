# AIR i64 vector zero-count checkpoint — 2026-11-17

Feature revision: `0369138e4986e359dabdb431e286adaca003f995`.

Software Metal accepts `air.clz.vNi64` and `air.ctz.vNi64` for fixed
1–16-lane i64 vectors and a literal i1 flag. Zero returns 64 with false and
lane poison with true. Existing evaluators, freeze and address projections
are reused. Keys 62100–62131 append 32 identities; earlier AIR/LLVM keys
remain stable. Vector cache entries total 62,132; scalar entries remain 2,179.

`tests/ios/air-native-vector-zero-count64.v` passes under ASan/UBSan against
LLVM 23.1.5 on arm64 Darwin:

- 139,264 false-flag native reference lanes and 557,056 observations across
  direct/prepared and typed/loaded paths; 32,768 scalar/integer comparisons.
- 34,816 defined true-flag native lanes and 139,264 direct/prepared false/true
  observations, plus 8,192 scalar/integer value/poison checks. Native true-flag
  inputs are made nonzero; native poison is never executed. Mixed zero vectors
  separately check false, true and freeze, with 224 cached-flag refusals.
- 2,144 address checks include 96 invalid lane projection refusals. Another
  512 address controls exercise both flags and poison preflight. Metadata/source
  type refusals (320), short budgets (128), AIR/LLVM coexistence (1,024), short
  buffers (128), negative profiles (32) and state/loop/limit controls (142) pass.
  Loops run through 1,024 visits with exact budgets; 12 fixtures retain the
  4,096 result-slot and 1,000,000 lane-work boundaries. No runtime limit changes.

Twelve unit groups pass, including scalar zero counts, both vector zero-count
families across i1–i64, every cache identity, AIR names, FMA, float extrema/clamp,
unary operations, canonicalization and multiply-high. The unchanged maintained
i32 AIR vector zero-count checker also passes its reference and flag controls.
Saved native disassembly has 32 reference functions in each of the false/true
modules, using only the corresponding LLVM i64 zero-count calls.

A fresh software Metal host passes normal and deterministic sizes runs:
480 images, 702,732 checked invocations, 212 rejected pipelines and four
prewrite bounds failures. Sixteen updated geometry images compare both i64
operations and flags against LLVM and explicit expectations on mixed low/high
and zero/nonzero lanes. One-lane i64 counts feed a checked address calculation;
the independent RGBA8/readback/padding expectations stay unchanged. All prior
comparison rows and the six other AIR image kernels remain unchanged. Repeated
dispatches, clipped groups and two drained runtimes per process pass.

The initial image fixture exceeded the existing 256-node address graph limit.
Its failed run remains in `software/`; the simpler address fixture passes in
`software-projected/`, without increasing limits. An initial checker build
rejected an overwide fixture literal during widening; that source and build
failure are retained. No production evaluator correction was required.

Generated host C confirms the cache sizes and no successful name/key path
allocations; error boxing remains. The added cache entries cost 256 bytes.
Retained heap was not measured; leak detection was disabled and native JIT
instructions are not sanitizer-instrumented. This is CPU software Metal.
Native GPU execution/rendering and new Fortnite launch/frame evidence remain
unverified. No kernel/guest build or broader SIMD/indirect suite was repeated.

Evidence: `/Users/alex/Library/Caches/vinix-ios/air-vector-zero-count64-20261117-r1`.

Complete archive: `/Users/alex/Library/Caches/vinix-ios/air-vector-zero-count64-20261117-r1.tar.gz`.

- Archive SHA-256: `4c6506bd1e3e8c3a0c8e284b0640eab06cbe2cd84d35f716b3b6cd2762117ece`.
- Typed inventory SHA-256: `8cf7d1f7ed2367371743f846164d609c34a023f9db5603a78117b71c397cd015`.
- Source archive SHA-256: `12a251a06b760e110d9a345fc4269440463c5be8e8822d73c5ca7744e2d3f456`.

Complete inventory and archive comparison passes for logical bytes, paths,
types, permissions and links, including root mode. Originals remain retained.
Source pins match the feature revision. Source, generated host C, IR/bitcode,
native disassembly, images, commands, binaries and sanitizer logs remain.
Toolchain libraries are referenced externally; the bundle is not hermetic.
No restoration replay or evidence deletion is claimed.
