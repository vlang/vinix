# Software Metal subvector extraction checkpoint — 2026-11-16

Source revision: `ac3bd310f1c961f66e07f328e838d3aad793602b`.

AIR executes fixed `llvm.vector.extract` calls over i1..i64, half and float
vectors with 1..16 source lanes, following the
[LLVM subvector contract](https://llvm.org/docs/LangRef.html#llvm-vector-extract-intrinsic).
The result must fit within the source and both overloads must name matching
element formats. Each i64 offset is a defined constant, a multiple of the
result count, with the complete window in range. Every call validates the
offset, including declaration-cache hits. Exact direct identity, signatures,
metadata, attributes and parameter-two immarg rules remain required. Scalable
vectors and vector returns remain outside this profile; integer-only execution
excludes floating formats.

Copying preserves raw lane bits, poison and deferred undef within the chosen
window; unselected indeterminate lanes are discarded. Existing source/result
freezes choose zero for observed poison/undef. Calls cost one executed step,
one existing result slot and source_count + result_count validation work units.
Keys 43652..52627 append 8,976 identities without moving previous families. The
vector cache has 52,628 entries and the scalar cache remains 2,154. Pure integer
addresses use existing packed selectors and projections. Invalid result selectors
remain poison through freezes and reject before writes. Existing graph cache,
height/capacity checks and ownership apply; no node kind, owner or profile field
is added.

`tests/ios/air-subvector.v` passes with ASan/UBSan over every admitted fixed
source/result shape and aligned in-range offset. Original AIR is LLVM-verified.
The independent native reference uses scalar extract/insert operations and
always-inline before JIT, calling no production subvector evaluator. This
qualifies that reference, rather than direct native lowering of every intrinsic
overload. Poison, undef and implementation-selected frozen values have separate
checks without observing indeterminate native results.

- 661,320 data cases across 66 element formats: 273,174 exact native values,
  84,348 frozen choices, 283,998 poison extractions and 19,800 selected-undef
  failures. Constructions include mixed lane states, source/result freezes
  and insertions. Half/float encodings include signed zero, infinities, NaN
  payloads and subnormals. Scalar/integer APIs pass 1,322,640 checks, including
  correct floating exclusion from the integer API. Both memory APIs compare
  all bytes, preceding markers, shifted views and nonmutating validation.
- 2,308,608 address API checks across i1..i64, all shapes/offsets and selector
  widths i1/i32/i64: 545,536 exact native addresses, 138,496 frozen choices
  and 470,272 prewrite refusals. Typed selector bindings normalize upper bits;
  native wrappers load i64 storage and explicitly truncate narrow selectors.
- 240,240 short-budget refusals and 216,216 metadata/arity refusals cover
  missing/excess arguments, flags, fast math, calling convention, attributes,
  signature, callee and result.

Total new native comparisons: 818,710.

`tests/ios/air-subvector-controls.v` passes 144 state, discard, cache-hit offset,
name/type, duplicate and graph/resource checks. The cache-hit tests replace a
second call offset with misaligned, out-of-range, negative, poison, undef and
dynamic argument operands; direct execution and preparation refuse before
marker writes. Unselected poison/undef is discarded; selected state and freezes
retain expected behavior. The graph fixtures accept 26 freezes and reject 27,
and accept 124 shared extractions and reject 125. Eight checks cover memory/void
admission at 4,096 versus 4,097 result slots and 1,000,000 versus 1,000,016 work
units. The exact work fixture uses 4,096 sixteen-lane calls and 54,308 extractions.
The same checker passes 280 vector-PHI loop properties, 560 scalar/integer checks
and 280 executed-budget refusals across i1/i8/i9/i32/i64, four source/result
windows and 1, 2, 3, 7, 16, 257 and 1,024 visits. Loop expectations use independent
wrapping products and are separate from the native comparison count.

The first controls run expected nine steps in a valid eight-step fixture. The
qualified checker uses the correct budget and the actual scoped argument value
number for the dynamic-offset refusal. Original failed binary, log and input IR
remain retained. Invalid-offset expectations and production code were unchanged.
No unexpected production execution or sanitizer failure remained.

Units pass all 8,976 new overload/key identities, 2,694,912 raw lane/state copy
checks, source snapshots, clear unused lanes and canonical shape/offset/tag guards.
Active-mask, stepvector, rounding, canonicalization and multiply-high units pass;
cache checks cover all 52,628 entries with previous intervals intact. Computed
index, prepared-memory, pointer-PHI and full pair-freeze self-test regressions pass.
Other full intrinsic matrices and kernel/guest builds were not repeated.

Fresh normal and deterministic software Metal processes each pass 106 geometry
dispatches, 216 shader images, 324,738 checked invocations, 106 rejected pipelines
and two prewrite bounds failures. The new image reconstructs coordinates from
four lanes extracted at offset eight from a sixteen-lane sequence. Float NaN
payload/subnormal, half subnormal and odd-width integer extractions contribute
to RGBA8 output. Queued dispatch, both selectors, clipped groups, buffer/texture
readback, padding, repeated commits and two drained runtimes pass.

Generated checker and focused host C confirm a fixed evaluator result without
array allocation. Projection appends POD nodes to existing owned graph storage;
existing result slots, SSA/PHI snapshots and error/profile cleanup remain. Heap
retention was not measured, leak detection was disabled and native JIT code was
not sanitizer instrumented. This extends CPU software Metal. Native GPU execution,
Fortnite launch gates, a Fortnite frame and complete Metal support remain unverified.

## Retained evidence

Canonical workspace: `/Users/alex/Library/Caches/vinix-ios/subvector-20261116-r1`.

Complete archive: `/Users/alex/Library/Caches/vinix-ios/subvector-20261116-r1.tar.gz`.

- Archive SHA-256: `100b726ae1fcf0547ba10e5abd01d7a9a6ee72a1d85a06a6be9c52978e67cf2b`.
- Typed inventory: sibling `.inventory.json`, SHA-256 `7ccf9eb900acb352272cd7505010cf972dc667837c675bebbc250c6a46617b3a`.
- Source snapshot: workspace `source.tar`, SHA-256 `55d958695491c46fa531eb917b60602a647a193d72dd392a5e4028e438fc5e0b`.

Inventory and archive checks compare every path, type, mode, link, size and
logical file hash, including root mode. Originals remain retained. This records
integrity without restoration replay or permission to delete evidence. Source,
commands, executable/tool identities, native targets, generated C, attempts and
sanitizer logs remain; sealing receipts are siblings outside the sealed workspace.
