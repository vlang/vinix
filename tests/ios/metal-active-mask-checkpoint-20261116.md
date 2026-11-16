# Software Metal active-lane-mask checkpoint — 2026-11-16

Source revision: `3477168ade223599b7f181d1bdc5c10991113b33`.

AIR executes fixed 1..16-lane `llvm.get.active.lane.mask` results with i1
elements and matching i1..i64 scalar base/limit arguments, following the
[LLVM mathematical-add contract](https://llvm.org/docs/LangRef.html#llvm-get-active-lane-mask-intrinsics).
The evaluator compares remaining unsigned distance, so lanes beyond overflow
are false even when argument widths cannot enumerate the vector. Inputs are
normalized to their declared widths. Poison arguments poison all lanes; vector
freezes choose zero for them. Scalar undef arguments require a prior scalar
freeze. Exact canonical names, types, direct identity, attributes, metadata and
arity remain required. Scalable vectors and vector returns remain outside this
profile. This does not implement masked memory instructions.

One executed step, one existing result slot and N validation work units are
charged per call. Keys 42628..43651 append 1,024 identities without moving old
families. The vector cache has 43,652 entries and the scalar cache remains 2,154.
Pure integer addresses use existing packed selectors, i64 distance subtraction,
two unsigned comparisons and AND nodes. Invalid selectors stay poison through
vector freezes and reject before writes. Existing graph ownership, caches and
height/capacity checks apply; no node kind, owner or profile field is added.

`tests/ios/air-active-mask.v` passes with ASan/UBSan across every admitted
width/count, five base/limit boundaries each and every selector plus invalid
boundaries. The constructions include vector freezes, reversal and selection
with undef. Original AIR is LLVM-verified. The independent native reference
zero-extends arguments by five bits, adds lane numbers without wrapping, compares
and inserts i1 lanes; LLVM always-inline runs before JIT. It calls no production
mask evaluator. Narrow native inputs are loaded as i64 and explicitly truncated.
This qualifies the widened-add reference, rather than direct native lowering of
every intrinsic overload. Indeterminate native results are never observed.

- 806,400 data cases: 480,080 exact native outputs, 153,600 poison extractions
  and 172,720 selected-undef failures. Scalar/integer APIs pass 1,612,800 checks;
  both memory APIs check all bytes, preceding markers, shifted views and
  nonmutating validation.
- 1,612,800 address API checks and 700,800 native address comparisons cover
  i1/i32/i64 selectors, invalid boundaries, upper-bit normalization, vector
  freezes and prewrite refusal. Typed scalar argument bindings are included.
- 12,288 short-budget and metadata/arity refusals cover omitted/excess arguments,
  flags, fast math, calling convention, attributes, signature, callee and result.

Total new native comparisons: 1,180,880.

`tests/ios/air-active-mask-controls.v` passes 137 state, name/type, duplicate,
void, address and graph/resource checks. Both scalar APIs cover poison/undef on
either argument, input and output freezes, and unused void results. Frozen poison
can produce address zero; invalid selectors still refuse before marker writes.
The graph fixtures accept 26 freezes and reject 27, and accept 124 shared
extractions and reject 125. Eight checks cover memory/void admission at 4,096
versus 4,097 result slots and 1,000,000 versus 1,000,016 work units. The work
fixture uses 4,096 sixteen-lane calls and 58,404 extractions. The same checker
passes 210 vector-PHI loop properties, 420 scalar/integer checks and 210 executed
budget refusals for i1/i8/i9/i32/i64, counts 1/3/16 and 1, 2, 3, 7, 16, 257 and
1,024 visits. These loop properties use an independent carry-aware add oracle;
they are separate from the native comparison count.

The initial controls fixture omitted its explicit GEP data layout. A diagnostic
identified the admission error; adding that fixture layout made the checks pass
with unchanged expectations and production code. Original failed controls
binaries, logs and IR remain retained. The final controls add the exact resource
boundaries and pass. No unexpected execution or sanitizer failure remained.

Units pass all 1,024 new overload/key identities, 217,600 carry-aware lane
checks, poison/tag/normalization/unused-lane guards and all 43,652 cache entries.
Stepvector, rounding, canonicalization and multiply-high units pass. Computed
index, prepared memory, pointer-PHI and full pair-freeze self-test regressions
pass. Other full intrinsic matrices and kernel/guest builds were not repeated.

Fresh normal and deterministic software Metal processes each pass 106 geometry
dispatches, 208 shader images, 315,862 checked invocations, 106 rejected pipelines
and two prewrite bounds failures. The new image uses i1/i8/i32/i64 mask arguments,
including one-lane and maximum-lane results, to compute a bounded coordinate and
red channel. Queued dispatch, both selectors, clipped groups, RGBA8 buffer/texture
readback, padding, repeated commits and two drained runtimes pass.

Generated checker and focused host C confirm a fixed evaluator result without
array allocation. Projection appends POD nodes to existing owned graph storage;
existing result slots, SSA/PHI snapshots and error/profile cleanup remain. Heap
retention was not measured, leak detection was disabled and native JIT code was
not sanitizer instrumented. This extends CPU software Metal. Native GPU execution,
Fortnite launch gates, a Fortnite frame and complete Metal support remain unverified.

## Retained evidence

Canonical workspace: `/Users/alex/Library/Caches/vinix-ios/active-mask-20261116-r1`.

Complete archive: `/Users/alex/Library/Caches/vinix-ios/active-mask-20261116-r1.tar.gz`.

- Archive SHA-256: `69883ec542bd6c4e30e5c4b2bacd0cd944b33b6e364b7c47752fab8266d5717c`.
- Typed inventory: sibling `.inventory.json`, SHA-256 `a84408a621cd3a652c2b4422ce46f651aa227b3f319d2584f5e9ff191a2dca33`.
- Source snapshot: workspace `source.tar`, SHA-256 `b08e0171fb0bacb3d7f2af309cc6a689863eb1094035d854815098ac10778f16`.

Inventory and archive checks compare every path, type, mode, link, size and
logical file hash, including root mode. Originals remain retained. This records
integrity without restoration replay or permission to delete evidence. Source,
commands, executable/tool identities, native targets, generated C, attempts and
sanitizer logs remain; sealing receipts are siblings outside the sealed workspace.
