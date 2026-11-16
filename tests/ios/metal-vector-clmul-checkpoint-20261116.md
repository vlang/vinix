# Software Metal vector carry-less multiply checkpoint — 2026-11-16

Source revision: `baeac9da7e9977ad2dce583caef2da74f438d49b`.

The bounded AIR interpreter now executes ordinary direct `llvm.clmul.vNiW`
calls for fixed 1..16-lane i1..i64 integer vectors. Each lane multiplies binary
polynomials with XOR instead of carries and retains the low W bits. Source
poison remains lane-local, including zero multipliers; executed undef inputs
reject eagerly. Source/result freezes retain existing semantics. Integer,
mixed, void and memory APIs support the calls, including pure integer address
graphs with prewrite validation. Canonical overloads, exact signatures,
declaration identities and attributes use the existing bounded call scanner.

`tests/ios/air-vector-clmul.v` passes with ASan/UBSan:

- 122,304 cases: 67,881 exact address outputs and 54,423 prewrite refusals,
  including 22,932 whole-vector undef cases. Nonmutating validation and
  ordinary/prepared execution check all backing bytes and marker ordering.
- 27,424 native LLVM lane values match independently computed polynomial
  coefficients. Native code executes only defined replacement inputs;
  poison, undef, invalid selectors, freeze choices and bounds are modeled
  separately. Coverage includes all widths with three lanes and every count
  1..16 at widths 1/8/16/32/64: 139 width/count combinations, three selector
  widths, eight operand patterns and four expression modes.
- 650 controls cover raw scalar/integer values, ordinary/prepared memory,
  composition with earlier `pext` overloads, both source poison/undef states,
  zero multipliers, source/result freezes, cold/unchosen undef, metadata/type
  guards, duplicate cache identities, malformed names and shared selectors.
  Twenty scalar/integer loop checks cover 1 through 1,024 visits to reused
  construction slots, including polynomial cycles.
- Exact graph boundaries cover both operand paths, selectors and cached
  heights. Shared limits cover 4,096 versus 4,097 construction results and
  the 1,000,000 lane-work boundary in memory and void APIs.

The new sanitized unit suite checks 157,024 lane outputs using independent
polynomial coefficients, including every i1..i8 input pair, all widths/counts,
upper-bit masking and snapshots. It also checks 139,264 commutativity and
distributivity identities and 208,896 poison/undef/freeze states. Existing
scalar carry-less multiplication and vector rounding units pass. The complete
cache test covers all 25,280 identities injectively; 1,024 appended overloads
preserve every previous key. Generated checker C contains both i64[25280]
profile caches; the focused host contains its used memory-profile cache and
omits its unused integer profile. Each existing cache grows by 8 KiB of stack.

Computed-index regression passes 26,029 exact native cases, 50,771 prewrite
refusals (21,399 LLVM overflow cases) and 4,096 vector-coordinate cases.
Prepared memory passes 28,928 byte comparisons and 3,314 changing-input,
recovery, bounds/budget and copied-metadata controls. Earlier controls pass:
696 vector bit-permutation, 67 scalar/vector bitcast address and 125 funnel
address controls. Other full vector matrices were not repeated.

Fresh normal and deterministic software Metal processes each pass 106 geometry
dispatches, 96 shader images, 191,598 checked invocations, 106 rejected pipelines
and two prewrite bounds failures. The new image multiplies a coordinate by
polynomial 3, uses that product in its pixel color, then multiplies by the
inverse polynomial 0xffffffff modulo x^32 to reconstruct the destination
coordinate. Tests cover actual queued dispatch, RGBA8 buffer/texture readback,
padded backing bytes, both dispatch selectors, clipped groups, repeated
commits and drained runtimes.

Generated checker and host C retain fixed by-value lane records and the
existing bounded scalar helper. Address projection reuses existing POD nodes,
ownership and cleanup. No new evaluator kind, node field, escaping pointer,
lifetime extension or free path is added. Existing allocation/error paths
remain. Heap retention was not measured, leak detection was disabled and
native JIT code was not sanitizer-instrumented. Broader runtime and kernel/guest
builds were not repeated.

Initial probes passed before fixed aggregate assertions and 20 loop checks
were added. The final matrix passes all 650 controls. All builds, qualification
checks and image modes passed without implementation corrections or execution
failures. Initial probes and all original evidence are retained.

This is CPU software Metal evidence. Native GPU execution, guest/Fortnite
launch gates, a Fortnite frame and complete Metal support remain unverified.

## Retained evidence

Canonical original workspace (retained in place):
`/Users/alex/Library/Caches/vinix-ios/vector-clmul-20261116-r1`.

Complete archive:
`/Users/alex/Library/Caches/vinix-ios/vector-clmul-20261116-r1.tar.gz`

- Archive SHA-256: `1341dc7a381c16852535e727db763a06351e4834e23a8c61cdd1dde571bb746f`.
- Complete typed inventory: sibling `.inventory.json`, SHA-256 `83c0760e9f08119021dc5a55e95fddc118d3eba1ed7ae1fc840a91ae2e93b04c`.
- Source snapshot: workspace `source.tar`, SHA-256 `a91c7963da99077d375afb733dbd31b689536cb23d94a1e20ffa6ff5d27644f7`.

The archive check decodes all logical payloads and compares the complete
workspace's paths, types, modes, symlink targets, sizes and hashes, including
root mode. Inventory comparison passes before compression and is rechecked by
the archive tool afterward. This records integrity with originals retained;
it does not claim a restoration replay or authorize deletion. Commands,
source revision, LLVM target/features, generated C, captured compiler,
executable identities and sanitizer logs are in the bundle. Sealing
commands/statuses are siblings outside the sealed workspace.
