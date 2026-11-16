# Software Metal ordered sum/product reduction checkpoint — 2026-11-16

Source revision: `d91e8a600240a1291132093b850bb326aaf6d7a5`.

The bounded AIR interpreter executes ordinary direct
`llvm.vector.reduce.fadd.vNf16/f32` and `fmul` calls for fixed 1..16-lane
half/float vectors and a matching scalar seed. Each call folds the seed with
lanes in increasing index order, rounding after every operation, following the
[LLVM sequential reduction contract](https://llvm.org/docs/LangRef.html#int-vector-reduce-fadd).
Existing binary16/binary32 arithmetic provides nearest/ties-to-even rounding,
gradual underflow, signed zeros, infinities and the preferred quiet NaN choice.

Seed or source poison poisons the result. Executed scalar seed undef and
vector undef lanes reject; seed poison or an earlier NaN does not suppress
later undef. Seed/source freezes repair indeterminate inputs, while result
freeze repairs poison without hiding earlier undef errors. Mixed, void and
memory APIs accept the calls, including earlier scalar results/PHIs as seeds
where admitted. Integer-only execution and floating address dependencies
remain excluded. Fast-math/reassociation flags and scalable/wider formats
remain excluded. Calls cost one step and N+2 validation lane-work units, with
no vector storage slot for the scalar result. Seed, element and return types
must match exactly; existing declaration, attribute and shared limits apply.

`tests/ios/air-vector-sequential-reduction.v` passes with ASan/UBSan:

- 272,384 LLVM intrinsic-versus-explicit-scalar-chain comparisons also match
  interpreter results: 262,008 exact non-NaN bit comparisons and 10,376 NaN-class
  comparisons. NaN payload/sign/signaling differences are permitted in native
  comparisons; interpreter bytes still match its explicit preferred choice.
  Native references execute only defined replacement inputs; poison, undef
  and freeze choices are checked separately.
- 64 operation/format/count shapes and 10,240 directed cases cover every count,
  both operations/formats, 32 patterns and five source/construction modes.
  Results comprise 8,704 exact/frozen values, 512 poison stores and 1,024 strict
  undef failures. Scalar and ordinary/prepared memory APIs check every byte,
  marker ordering and nonmutating validation with shifted bindings.
- 262,144 sweep samples cover every half encoding and 65,536 deterministic
  float patterns for both operations, using nonneutral scalar seeds and reused
  prepared plans. Multiplication preserves active inputs with one-valued
  remaining lanes; addition uses zero-valued remaining lanes.
- All 10,240 short budgets reject before writes with a budget diagnostic;
  64 integer-only API controls reject floating reduction bodies.
- 161 controls cover scalar seeds, vector arguments/loads, source composition,
  discarded/cold states, seed and result freezes, seed poison with vector
  undef, shared scalar seeds, metadata/type/name guards and floating address
  exclusions. Twelve directed native/interpreter cases distinguish forward
  and reversed cancellation, underflow and overflow in both formats. Seven
  loop controls reuse a scalar PHI seed across 1 through 1,024 visits.
- Memory/void controls check 4,096 versus 4,097 vector constructions and exactly
  1,000,000 versus 1,000,001 lane-work units, including expected diagnostics.
  The work boundary includes 65,536 insertion units, 51,914 reductions at
  18 units each, and a 12-lane extraction. Scalar reductions add no vector slots.

The sanitized unit suite passes 262,144 independent identity encodings,
including every half encoding, deterministic floats, NaNs, signed zeros,
upper-bit masks and source snapshots; 140 exact-value and rounding-order
checks; and 1,152 seed/lane poison and eager undef checks. Rounding and integer
reduction units pass, including all 34,624 cache identities. Sixty-four new
identities preserve the existing keys; each i64 declaration cache grows by
512 bytes of stack.

The full floating min/max regression passes 272,384 native/oracle values,
262,144 sweep samples, 10,240 budgets and 82 controls. The integer reduction
regression passes 40,032 native/oracle values, 80,064 scalar/integer checks,
40,032 budgets and 119 controls. Its former unsupported fadd fixture now
executes as a discarded floating reduction and checks both memory APIs.
Integer address, vector carry-less multiply and scalar/vector bitcast address
controls pass 150, 650 and 67 checks. Computed-index regression passes 26,029
native exact cases, 50,771 prewrite refusals and 4,096 vector-coordinate cases;
prepared memory passes 28,928 byte comparisons and 3,314 changing-input,
recovery, bounds/budget and copied-metadata controls. Other full matrices were
not repeated.

Fresh normal and deterministic software Metal processes each pass 106 geometry
dispatches, 128 shader images, 227,102 checked invocations, 106 rejected
pipelines and two prewrite bounds failures. The new image sums a scalar seed
and coordinate lanes, uses that result as a product seed, converts the result
to an integer and includes it in the red channel. Tests cover queued dispatch,
RGBA8 buffer/texture readback, padded bytes, both dispatch selectors, clipped
groups, repeated commits and two drained runtimes per process.

Generated checker and host C retain fixed by-value seeds, source vectors and
scalar accumulators, using the existing binary16/binary32 arithmetic helpers.
No new arrays occur in the reduction or name parser. The checker includes
both profile declaration caches; the focused host includes its used memory
cache. Existing scalar SSA slots, construction storage, profile ownership and
cleanup are reused. No evaluator kind, node field, escaping pointer, lifetime
extension or free path is added. Existing allocation/error paths remain.
Heap retention was not measured, leak detection was disabled and native JIT
code was not sanitizer instrumented. Broader runtime and kernel/guest builds
were not repeated.

Two edit-generator compile diagnostics and the first unit-build syntax
diagnostic are retained; corrections preceded execution. The corrected unit
probe passes all identities/order/state checks. The controls probe passes
149 checks before the 12 explicit native/interpreter order cases are added.
All final qualified checks pass without runtime failures. Saved original
artifacts remain.

This is CPU software Metal evidence. Native GPU execution, guest/Fortnite
launch gates, a Fortnite frame and complete Metal support remain unverified.

## Retained evidence

Canonical original workspace (retained in place):
`/Users/alex/Library/Caches/vinix-ios/vector-sequential-reduction-20261116-r1`.

Complete archive:
`/Users/alex/Library/Caches/vinix-ios/vector-sequential-reduction-20261116-r1.tar.gz`

- Archive SHA-256: `2d8b2c64b5234cc2708b311961f6c0c3083f4d6db63a301fadd4e0e7b88ca343`.
- Complete typed inventory: sibling `.inventory.json`, SHA-256 `a5be710b157451e38e217feec78a82a50c53dd8eb404ae72a439c4293ff242fc`.
- Source snapshot: workspace `source.tar`, SHA-256 `7ed3807c084eb3b451ac3ac989653807dbdf38fdb5b5750d7194e8b035a341d9`.

The archive check decodes all logical payloads and compares the complete
workspace's paths, types, modes, symlink targets, sizes and hashes, including
root mode. Inventory comparison passes before compression and is rechecked by
the archive tool afterward. This records integrity with originals retained;
it does not claim a restoration replay or authorize deletion. Commands,
source revision, LLVM target/features, generated C, captured compiler,
executable identities and sanitizer logs are in the bundle. Sealing
commands/statuses are siblings outside the sealed workspace.
