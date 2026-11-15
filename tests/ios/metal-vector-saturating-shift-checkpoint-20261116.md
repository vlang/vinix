# Vector saturating-shift checkpoint — 2026-11-16

Source revision: `c7b456bed525dad1402bfc728d4045868e6d33b8`.

The AIR interpreter now accepts signed and unsigned vector saturating left
shifts for i1..i64 and 1..16 lanes. Each lane preserves poison, rejects undef,
and saturates valid shifts. Width-truncated unsigned amounts at least the lane
width produce poison even for zero. The shared vector cache has 18,112 distinct
identities. This implements interpreter operations for the Metal effort.

Validation passed with AddressSanitizer and UndefinedBehaviorSanitizer:

- 1,251,520 independent checked-doubling unit comparisons, including 232,928
  poison results; narrow pair exhaustion, wider patterns, masking and snapshots.
- 34,816 source poison/undef/freeze positions, plus lane-tag/name/shape guards.
- All 18,112 declaration-cache identities and nine existing unit programs.
- 64 LLVM-verified modules covering 2,048 overloads: 152,064 defined memory
  outputs match native LLVM; 142,848 oracle-defined poison stores refuse after
  preserving the preceding marker write. Both scalar APIs check another
  589,824 value/tag results.
- 47,104 malformed call/source mutations and 2,048 short budgets refuse before
  writes. Exact execution steps and memory footprint profiles also pass.

The reference broadcasts inputs to vectors and extracts their final lane; the
unit matrix checks distinct lane values. Native execution receives canonical
padding and only defined shift amounts. Poison expectations use the independent
checked-doubling oracle, not execution of invalid native shifts. LLVM semantics:
[sshl.sat](https://llvm.org/docs/LangRef.html#llvm-sshl-sat-intrinsics),
[ushl.sat](https://llvm.org/docs/LangRef.html#llvm-ushl-sat-intrinsics).
The LLVM 23.1.5 JIT is uninstrumented; ASan leak detection is disabled and
retained heap is unmeasured. No AArch64 cross-build, host fixture/full host
suite, guest launch, GPU command or Fortnite frame is newly qualified.

Evidence is retained at `/Users/alex/Library/Caches/vinix-ios/vector-sat-shift-20261116-r1` and archived at `/Users/alex/Library/Caches/vinix-ios/vector-sat-shift-20261116-r1.tar.gz`. Complete typed
inventory verification and archive logical-byte/metadata comparison pass;
originals remain retained. This is an integrity check, not a restoration replay
or application launch audit.

- Archive SHA-256: `0f30e21ab22c2875032e63891b63426a4e090074442b095fd9e480473ba1815d`.
- Inventory SHA-256: `3f5bfe636d6c6813b8f3f2e8f8a55fc88436253354f4c98973e14dc3a3ef2cf7`.
- Committed source archive SHA-256: `039d108f5c77ecf4102dcc8c22e39ae0d8f10b7a6b65c2b8fcef61a4817899a5`.

The bundle retains generated IR/bitcode, every comparison, test binaries, build
and execution logs, commands, compiler/LLVM identities, and source hashes checked
before/after final tests and against the feature commit. Initial generator/build
failures remain as diagnostics; `final0`, `final1`, and `final2` are the successful
final shift-unit, cache-unit, and decoded-reference runs. The six changed legacy
name guards use unsupported vector carryless multiply.
