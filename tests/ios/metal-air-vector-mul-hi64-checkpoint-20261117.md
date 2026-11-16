# AIR i64 vector multiply-high checkpoint — 2026-11-17

Feature revision: `ef20d31d7fb3e64d41900cc81a8189c4ab7a0490`.

Software Metal accepts `air.mul_hi.s.vNi64` and `air.mul_hi.u.vNi64`
for matching fixed 1–16-lane i64 vectors. Existing evaluators return the
upper 64 bits of the signed or unsigned full product. Keys 62196–62227
append 32 identities; earlier AIR/LLVM/i32 keys remain stable. The vector
cache has 62,228 entries; scalar entries remain 2,179. All currently admitted
AIR integer vector families now support i32 and i64 lanes.

`tests/ios/air-native-vector-mul-hi64.v` passes under ASan/UBSan with LLVM
23.1.5 on arm64 Darwin. Native references sext/zext to i128, multiply,
shift right by 64 and truncate. Saved disassembly confirms 32 reference
bodies, 32 i128 products, 32 shifts and 32 truncations, without calls.
An independent bit-column oracle computes magnitude products, carries and
signed two's-complement results without the production limb algorithm.

- 278,528 native reference lanes pass through typed/loaded inputs and both
  direct/prepared execution paths. Every lane includes all 16² boundary pairs,
  followed by deterministic/equal/complement samples. Complete shifted
  unaligned buffers, output padding and nonmutating validation pass.
- 66,560 scalar/integer comparisons, 2,144 address checks (including 96 invalid
  lane projection refusals), 352 metadata/source-type refusals, 128 short
  budgets, 2,048 AIR/LLVM coexistence cases and 192 short-buffer refusals pass.
  Thirty invalid profiles refuse before marker writes. Another 163 controls
  cover poison/undef/freeze, address preflight, loops through 1,024 visits,
  exact budgets, duplicate declarations and strictfp. Twelve fixtures retain
  the 4,096 result-slot and 1,000,000 lane-work boundaries; no limit changes.
- Fifteen unit groups pass, including all 62,228 cache identities, exact names,
  multiply-high across i1–i64, saturation, zero counts, integer operations,
  FMA, float extrema/clamp, unary operations and canonicalization. The unchanged
  i32 AIR multiply-high checker passes its 278,528 reference lanes and controls.

A fresh software Metal host passes normal and deterministic sizes runs:
480 images, 702,732 checked invocations, 212 rejected pipelines and four
prewrite bounds failures. Sixteen updated multiply-high images compare both
i64 AIR operations with LLVM and explicit formulas, using nonnegative and
top-bit-set lanes. The unsigned high half reconstructs the output coordinate
before truncation to i32; full comparisons gate pixel data. All prior comparison
rows and six other AIR image kernels remain unchanged. RGBA8/readback/padding,
clipped groups, repeated dispatches and two drained runtimes per process pass.

Generated host C confirms cache sizes and no successful extended name/key path
allocations; error boxing remains. Added cache entries cost 256 bytes. No new
evaluator, owner or graph node kind is added. Retained heap was not measured;
leak detection was disabled and native JIT instructions are not sanitizer-
instrumented. Fixtures are synthetic; Apple compiler emission and native AIR/GPU
comparisons were not run. Retained declaration-builder source provides context.
This extends CPU software Metal. Native GPU execution/rendering and new Fortnite
launch/frame evidence remain unverified. No kernel/guest build or broader
SIMD/indirect suite was repeated.

Evidence: `/Users/alex/Library/Caches/vinix-ios/air-vector-mul-hi64-20261117-r1`.

Complete archive: `/Users/alex/Library/Caches/vinix-ios/air-vector-mul-hi64-20261117-r1.tar.gz`.

- Archive SHA-256: `1a89001b1d494dc6ec1ea347098d7b7eea822a8263fba53de2e3b8dd25b7c558`.
- Typed inventory SHA-256: `809437b1439f70a20d352c55d34a5f340b040ad50fc5c2c1fcc56627b997a294`.
- Source archive SHA-256: `9160f3a05517a68329380e848328ab378965b6b8ac10864760c127f1eb4aa3db`.

Complete inventory and archive comparison passes for logical bytes, paths,
types, permissions and links, including root mode. Originals remain retained.
Source pins match the feature revision. Source, generated host C, IR/bitcode,
native disassembly, images, commands, binaries and sanitizer logs remain.
Toolchain libraries are referenced externally; the bundle is not hermetic.
No restoration replay or evidence deletion is claimed.
