# AIR i64 vector saturating arithmetic checkpoint — 2026-11-17

Feature revision: `38749e4eba2f947b14254fecddf1eee2ecb1f8e8`.

Software Metal accepts signed and unsigned `air.add_sat`/`air.sub_sat`
overloads for matching fixed 1–16-lane i64 vectors. Existing evaluators clamp
signed overflow to its endpoint, unsigned addition overflow to UINT64_MAX
and unsigned subtraction underflow to zero. Keys 62132–62195 append 64
identities; earlier AIR/LLVM/i32 keys remain stable. The vector cache has
62,196 entries and the scalar cache remains 2,179 entries.

`tests/ios/air-native-vector-saturating64.v` passes under ASan/UBSan with
LLVM 23.1.5 on arm64 Darwin. Native references sext/zext i64 vectors to
i128, add/subtract, compare/select clamp and truncate. Saved disassembly
confirms 64 reference bodies, 64 i128 arithmetic operations, 128 i128
comparisons and 64 truncations, without calls. A separate V oracle uses
checked signed margins and explicit unsigned limb carry.

- 557,056 native reference lanes pass through typed and loaded inputs, each
  with direct and prepared execution. Every lane includes all 16² boundary
  pairs before deterministic/equal/complement inputs. Complete shifted
  unaligned buffers, output padding and nonmutating validation pass.
- 133,120 scalar/integer comparisons, 4,288 address checks (including 192
  invalid lane projection refusals), 704 metadata/source-type refusals, 256
  short budgets, 4,096 AIR/LLVM coexistence cases and 384 short-buffer
  refusals pass. Sixty invalid name/type/arity/definition profiles reject
  before marker writes.
- 307 state/freeze/strict-undef/address/loop/limit controls pass. Loops run
  through 1,024 visits with exact budgets. Twelve fixtures retain the 4,096
  result-slot and 1,000,000 lane-work boundaries. No runtime limit changes.

Fifteen unit groups pass, including all 62,196 cache identities, exact AIR
names, scalar/vector saturation across i1–i64, zero counts, integer operations,
FMA, float extrema/clamp, unary operations, canonicalization and multiply-high.
Scalar saturation checks 1,303,888 comparisons; vector saturation checks
2,820,096 values, a further 1,267,072-pair sweep, 36,864 boundaries and
835,584 poison/undef/freeze cases. The unchanged maintained i32 AIR vector
saturation checker passes its 557,056 reference lanes and controls again.

A fresh software Metal host passes normal and deterministic sizes runs:
480 images, 702,732 checked invocations, 212 rejected pipelines and four
prewrite bounds failures. Sixteen updated saturation images compare all four
i64 AIR operations with LLVM and explicit endpoints, including both signed
clamp directions and unsigned underflow. An i64 subtraction result reconstructs
the output coordinate before truncation to i32; full comparisons gate pixel
data. All prior comparison rows and the six other AIR image kernels remain
unchanged. RGBA8/readback/padding, clipped groups, repeated dispatches and
two drained runtimes per process pass.

An initial checker build rejected an overwide fixture literal during widening;
that source and build failure remain retained. Final runtime checks pass
without a production evaluator correction. Fixtures are synthetic; Apple
compiler emission and native AIR/GPU comparisons were not run. A retained
AIR declaration-builder source copy supplies spelling/signature context.

Generated host C confirms the cache sizes and no successful name/key path
allocations; error boxing remains. Sixty-four cache entries add 512 bytes.
No evaluator, owner or graph node kind was added. Retained heap was not measured;
leak detection was disabled and native JIT instructions are not sanitizer-
instrumented. This extends CPU software Metal. Native GPU execution/rendering
and new Fortnite launch/frame evidence remain unverified. No kernel/guest
build or broader SIMD/indirect suite was repeated.

Evidence: `/Users/alex/Library/Caches/vinix-ios/air-vector-saturating64-20261117-r1`.

Complete archive: `/Users/alex/Library/Caches/vinix-ios/air-vector-saturating64-20261117-r1.tar.gz`.

- Archive SHA-256: `a06813b6f9940b93c1c1a92d89743c51c954096d6d6bf7e78e0e92c3cb8d53a0`.
- Typed inventory SHA-256: `5419cc873fc2906804744b19c8c418f522962cb4ea688f1e6fcf31b1edba6bf0`.
- Source archive SHA-256: `b3b4f85fdd538c10eda4fc9c6b18a729c074acaf30fa9ffcb939d8f21842fc42`.

Complete inventory and archive comparison passes for logical bytes, paths,
types, permissions and links, including root mode. Originals remain retained.
Source pins match the feature revision. Source, generated host C, IR/bitcode,
native disassembly, images, commands, binaries and sanitizer logs remain.
Toolchain libraries are referenced externally; the bundle is not hermetic.
No restoration replay or evidence deletion is claimed.
