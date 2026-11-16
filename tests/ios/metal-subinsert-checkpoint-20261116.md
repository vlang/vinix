# Software Metal subvector insertion checkpoint — 2026-11-16

Source revision: `f43d4f53ff0ede0b8a860acb5c26681786fd19d5`.

AIR executes fixed `llvm.vector.insert` calls over i1..i64, half and float
vectors with up to 16 result lanes, following the
[LLVM insertion contract](https://llvm.org/docs/LangRef.html#llvm-vector-insert-intrinsic).
The result matches the base vector; the inserted vector has the same element
format and fits within it. Each third-argument i64 offset must be a defined
constant, a multiple of the inserted count, with the full window in range. Every
call checks its offset, including declaration-cache hits. Copying preserves raw
bits and deferred state, removes overwritten base state and leaves surrounding
lanes unchanged. Source/result freezes keep their existing zero choice. Scalable
vectors and vector returns remain excluded; integer-only execution excludes
floating formats.

Exact direct identity, signatures, attributes and call metadata remain checked.
The vector call profile now returns an exact declaration immarg slot: three for
insertion, two for existing immediate families, zero otherwise. Scalar and memory
scanners pass it to the same bounded attribute validator with unchanged work
accounting. Calls cost one step, one existing result slot and 2*base_count +
inserted_count validation work units. Keys 52628..61603 append 8,976 identities
without moving previous families. The vector cache has 61,604 entries and the
scalar cache remains 2,154. Integer addresses use existing packed/rebased shuffle
selectors and projections of differently sized parents. Invalid result selectors
remain poison through freezes and refuse before writes. No node kind, owner or
profile field is added; existing graph cache, depth/capacity and cleanup apply.

`tests/ios/air-subinsert.v` passes with ASan/UBSan for every admitted fixed
base/inserted shape and aligned offset. The seven constructions include defined
inputs, mixed base state, mixed inserted state, input freezes, result freezes and
updates to either input. Original AIR is LLVM-verified. The independent native
reference extracts scalar source lanes and inserts them into the base, running
always-inline before JIT; it calls no production insertion evaluator. Float32
reference vectors use equivalent i32 bit patterns after an installed LLVM
AArch64 float-vector legalizer crash. The original AIR stays float32. This
qualifies that reference, rather than direct native lowering of every overload.
Indeterminate native results are never observed.

- 2,279,508 data cases across 66 formats: 1,445,268 exact native values,
  271,920 frozen choices, 498,828 poison extractions and 63,492 selected-undef
  failures. Scalar/integer APIs pass 4,559,016 checks, including correct floating
  exclusion from the integer API. Both memory paths check all bytes, preceding
  markers, shifted views and nonmutating validation. Half/float patterns include
  signed zero, infinities, NaN payloads and subnormals.
- 7,578,624 address API checks across i1..i64, all shapes/offsets and selector
  widths i1/i32/i64: 2,573,568 native addresses, 421,248 frozen choices and
  794,496 prewrite refusal cases. Typed selector bindings normalize upper bits;
  native wrappers load i64 storage and explicitly truncate narrow selectors.
- 336,336 short-budget and 216,216 metadata/arity refusals cover missing/excess
  arguments, flags, fast math, calling convention, attributes, signature, callee
  and result.

Total new native comparisons: 4,018,836.

`tests/ios/air-subinsert-controls.v` passes 170 state, discard, cache-hit offset,
immarg, name/type, duplicate and graph/resource checks. Invalid second-call offsets
include misaligned, out-of-range, negative, poison, undef and dynamic operands.
Third-parameter attributes placed at five wrong slots reject in memory and void
profiles. Overwritten poison/undef disappears; selected state and result freezes
keep expected behavior. Graph fixtures accept 25 freezes and reject 26, and accept
122 shared extractions and reject 123. Eight checks cover memory/void admission
at 4,096 versus 4,097 result slots and 1,000,000 versus 1,000,016 work units. The
exact work fixture uses 4,096 sixteen-lane insertion calls and 50,212 extractions.
The same checker passes 280 vector-PHI loop properties, 560 scalar/integer checks
and 280 executed-budget refusals across i1/i8/i9/i32/i64, four windows and 1, 2, 3,
7, 16, 257 and 1,024 visits. Loop expectations use independent wrapping products
and remain separate from the native comparison count.

The initial combined address module exceeded the unchanged AIR record limit.
Splitting by selector width kept every case. A combined data run passed i1/i2
before i3 also exceeded that limit; splitting by construction kept all seven
modes. All 65 integer/half batches passed before float32 native code generation
crashed; a fresh-process float-only attempt reproduced it. The retained macOS
report identifies `DAGTypeLegalizer::WidenVectorResult`. The raw-bit float32
reference passes all seven modes under ASan/UBSan. Its first converter attempt
exited with signal 9 before native input; chunk searches replaced per-byte suffix
copies in the passing implementation. `matrix-complete.txt` reconciles all 66
format aggregates, 462 mode receipts and 192 address-selector receipts; the failed
full-run status remains. Qualified runs retain part and aggregate receipts. Failed binaries,
complete generated modules and diagnostics remain. No parser limit or execution
expectation was relaxed. A leading-zero-count regression exposed a stale rejection
of the already-supported clmul name; that unit now rejects a spoofed ctlz name
and explicitly checks the zero-count evaluator rejects the clmul family.

Units pass 8,976 new overload/key identities, 8,883,072 raw lane/state copies,
both source snapshots, overwritten-state removal, unused-lane and shape/offset/tag
guards. Twenty-six checks cover exact no/second/third-parameter immarg policy,
properties and budgets. Extraction, active-mask, stepvector, rounding,
canonicalization and multiply-high units pass; cache checks cover all 61,604
entries with previous intervals intact. Leading-zero-count, scalar and memory
intrinsic attribute regressions and previous extraction controls pass. Computed
index, prepared-memory, pointer-PHI and full pair-freeze self-test regressions pass.
Other full intrinsic matrices and kernel/guest builds were not repeated.

Fresh normal and deterministic software Metal processes each pass 106 geometry
dispatches, 224 shader images, 333,614 checked invocations, 106 rejected pipelines
and two prewrite bounds failures. The new image inserts a four-lane sequence
window, extracts it again and reconstructs a bounded coordinate. Float payloads,
half subnormals and a defined odd-width lane amid undef contribute to RGBA8 output.
Queued dispatch, both selectors, clipped groups, buffer/texture readback, padding,
repeated commits and two drained runtimes pass.

Generated checker and focused host C confirm a fixed evaluator result without
array allocation. Projections append POD nodes to existing owned graph storage;
existing result slots, SSA/PHI snapshots and error/profile cleanup remain. Heap
retention was not measured, leak detection was disabled and native JIT code was
not sanitizer instrumented. This extends CPU software Metal. Native GPU execution,
Fortnite launch gates, a Fortnite frame and complete Metal support remain unverified.

## Retained evidence

Canonical workspace: `/Users/alex/Library/Caches/vinix-ios/subinsert-20261116-r1`.

Complete archive: `/Users/alex/Library/Caches/vinix-ios/subinsert-20261116-r1.tar.gz`.

- Archive SHA-256: `35c818807d76fa907a4e3f0cb27795133ebcedff0505654bc0bf8287d4e5b842`.
- Typed inventory: sibling `.inventory.json`, SHA-256 `b52bb333ed6874abc505323ad25dbc1d2be95af9c64e01245a01d250e878056a`.
- Source snapshot: workspace `source.tar`, SHA-256 `6ae64ea6d0b917f13ebec1b3227b32b7f98dc3ef44136c64d5284eb08124b64e`.

Inventory and archive checks compare every path, type, mode, link, size and
logical file hash, including root mode. Originals remain retained. This records
integrity without restoration replay or permission to delete evidence. Source,
commands, executable/tool identities, native targets, generated C, attempts and
sanitizer logs remain; sealing receipts are siblings outside the sealed workspace.

The reused inventory executable refused because its embedded source differed
from the current tracked auditor. That rejection remains retained. The unchanged
current auditor was rebuilt with the default V, excluding unused `os/fifo*.v`
wrappers to avoid their conflicting POSIX declaration. Its own FIFO checks remain.
Fresh/fast/existing sparse archive baselines, four archive refusals, eight typed
inventory refusals and the bounded FIFO refusal self-test pass. No historical
auditor or inventory expectation was weakened. Failed build attempts remain.
