# Software Metal stepvector checkpoint — 2026-11-16

Source revision: `68ca9d45aa3e17a50934bf9823f2dae3bd9c42fb`.

The AIR interpreter executes fixed 1..16-lane i8..i64 `llvm.stepvector` calls,
following the [LLVM lane-sequence contract](https://llvm.org/docs/LangRef.html#llvm-stepvector-intrinsic).
Each call creates defined lane values 0, 1, 2, ... without source operands.
Its ordinary direct operand list contains only the callee, and its signature
contains only the result type. Exact declaration identity, arity, attributes,
metadata and name/type checks remain. Missing arguments to older intrinsic
families still reject. Scalar, void and both memory APIs share the existing
result slots. Calls cost one executed step and N validation work units; keys
41716..42627 append 912 identities without moving previous families. The scalar
cache remains 2,154 entries. Scalable vectors, floating types, widths below i8
and vector returns remain outside this profile. Lane truncation cannot occur
within the admitted 16-lane/i8-minimum bounds.

Pure integer addresses use one existing shuffle-selector node and two packed
words containing lane numbers. Invalid selectors poison the extraction, including
through a vector freeze, and preflight rejects them before writes. Existing
node/depth checks, source-plus-selector caching, result slots and profile cleanup
remain. No node kind, owner or profile field is added.

`tests/ios/air-vector-step.v` passes with ASan/UBSan:

- 57,456 data cases across every admitted width/count and six constructions:
  30,951 exact native values, 20,121 poison results and 6,384 selected-undef
  failures. Scalar/integer APIs pass 114,912 checks. Both memory APIs check every
  byte, preceding markers, shifted views and nonmutating validation. Construction
  coverage includes freezes, insertions, selections with poison/undef and reversal;
  unused insertions do not mutate the original sequence.
- 459,648 address API checks and 174,762 native address comparisons cover every
  width/count, selectors of i1/i32/i64, all in-range lanes and invalid boundaries,
  upper-bit normalization, freezes, reversal and selection with undef. Invalid
  addresses refuse before marker writes; defined references compare all bytes.
- 10,944 short memory-budget refusals and 9,120 metadata/arity refusals cover
  omitted/excess stepvector operands and missing operands on existing reverse
  calls, alongside flags, calling convention, attributes, signature and callee
  mutations. Ten further checks cover poison/undef indices with scalar freezes,
  discarded zero-argument results and duplicate declarations.
- Sixty-two graph/resource checks scan both sides of existing limits. The
  fixtures accept 29 vector freezes and reject 30, and accept 254 shared
  extractions and reject 255. Eight checks cover memory/void admission at 4,096
  versus 4,097 slots and 1,000,000 versus 1,000,016 lane-work units. The work
  fixture uses 4,096 sixteen-lane calls plus 58,404 extractions; one extra rejects
  before writes. These use public admission rather than private graph storage.
- 192 exact native vector-PHI loop results, 384 scalar/integer checks and
  192 executed-budget refusals cover i8/i9/i32/i64, counts 1/3/16 and 1, 2, 3,
  7, 16, 257, 513 and 1,024 visits. Insertions accumulate one lane across PHIs
  while each stepvector call recreates the other lane values in reusable slots.

Total new native comparisons: 205,905. Original AIR bitcode is LLVM-verified.
The native reference independently substitutes explicit constant sequences and
runs LLVM always-inline before JIT; it calls no production stepvector evaluator.
Poison and undef have separate checks without observing indeterminate native
results. The initial native address wrapper disagreed when loading a narrow
selector directly from storage with higher bits set. The maintained wrapper
now loads the supplied i64 word and explicitly truncates it to the selector type,
matching binding normalization. Interpreter expectations and output comparisons
were unchanged; the qualified full run passes. The original failed binary, IR
and diagnostics remain retained. This is a native constant-sequence reference,
not a claim about direct native lowering of every stepvector intrinsic.

Units check all 912 overload/key identities, 7,752 defined lane values, clear
state and unused lanes, and canonical name/shape guards. Interleave, rounding,
canonicalization and multiply-high units pass; cache checks cover all 42,628
entries with earlier family intervals intact. The complete shuffle-index
regression passes 879,093 exact outputs and 919,947 prewrite refusals, including
123,670 selected-undef cases and 46 controls. Computed-index, prepared-memory,
pointer-PHI and full pair-freeze self-test checks also pass. Other full intrinsic
matrices and kernel/guest builds were not repeated.

Fresh normal and deterministic software Metal processes each pass 106 geometry
dispatches, 200 shader images, 306,986 checked invocations, 106 rejected pipelines
and two prewrite bounds failures. The new shader uses i8/i9/i32/i64 stepvector
calls, including one-lane and maximum-lane shapes, to reconstruct its coordinate
and red channel. Queued dispatch, both selectors, clipped groups, RGBA8
buffer/texture readback, padding, repeated commits and two drained runtimes pass.

Generated checker and focused host C confirm fixed result records and packed
selector words without array allocation in the sequence evaluator or projection
helper. Existing owned result slots, graph arrays and cleanup remain. Declaration
caches gain 912 integer entries. Existing boxed errors and machine/SSA/profile
allocations remain; heap retention was not measured, leak detection was disabled
and native JIT code was not sanitizer instrumented. This extends CPU software
Metal. Native GPU execution, Fortnite launch gates, a Fortnite frame and complete
Metal support remain unverified.

## Retained evidence

Canonical original workspace:
`/Users/alex/Library/Caches/vinix-ios/vector-step-20261116-r1`.

Complete archive:
`/Users/alex/Library/Caches/vinix-ios/vector-step-20261116-r1.tar.gz`.

- Archive SHA-256: `0bfb976d6401b16a9c8272d69cc2ff5f1f23ac8a7a78f6d0f3b82460c4160777`.
- Complete typed inventory: sibling `.inventory.json`, SHA-256 `bf7840f98661cd4fe3e39e39eab04d310c0e2ec3ca8854a12bf2ed80c75bde63`.
- Source snapshot: workspace `source.tar`, SHA-256 `0907a9d568c0319dfcd55bae00c6a2b8ec296e008ffaff69c411027566537788`.

Inventory and archive checks compare every path, type, mode, link, size and
logical file hash, including root mode. Originals remain retained. This records
integrity without restoration replay or permission to delete evidence. Source,
commands, executable/tool identities, native targets, generated C, attempts and
sanitizer logs remain; sealing receipts are siblings outside the sealed workspace.
