# Software Metal canonicalization checkpoint — 2026-11-16

Source revision: `90ed270ba2a4af45b595491abfad526cd2641ab6`.

The AIR interpreter executes scalar half/float and fixed 1..16-lane vector
`llvm.canonicalize` calls through scalar, void and both memory APIs. It preserves
finite encodings, subnormals, signed zero and infinity; NaNs preserve sign and
payload, with only a signaling NaN's quiet bit changed. This implements the
[LLVM canonicalization contract](https://llvm.org/docs/LangRef.html#llvm-canonicalize-intrinsic)
for the software target's gradual-underflow environment. Evaluation uses integer
bits independently of host FP state. Poison propagates per lane and observed
undef rejects; source freezes can repair state before the call. Arithmetic
intrinsics retain their existing NaN policies.

Exact ordinary direct declarations and existing attribute checks apply. Double,
scalable/wider vectors, fast-math, custom denormal modes and floating address
dependencies remain excluded. Calls cost one execution step; vectors consume
one existing construction slot and 2*N validation lane-work units. Scalar keys
2024..2025 and vector keys 34752..34783 append without moving existing identities.

The maintained `tests/ios/air-canonicalize.v` passes under ASan/UBSan:

- 133,258 exact native vector comparisons across 800 shapes, both formats,
  counts 1..16, five source forms and five constructions. This includes a full
  half encoding sweep and deterministic float sweep totaling 131,072 samples.
  NaNs compare exact sign, payload and quiet bits, without class substitution.
- 1,256 explicit frozen choices, 3,040 poison stores and 1,882 strict undef
  failures. Both memory APIs check every destination byte and earlier markers;
  prepared validation does not write. There are 278,872 scalar/integer API
  checks, 16,000 metadata/source refusals and 1,600 short-budget checks.
- 196,608 exact native scalar comparisons, checked through scalar and both
  memory APIs, including all half encodings, stratified/deterministic float
  encodings and 2,555 NaNs. Thirty scalar state/budget/API/metadata controls pass.
  Total native comparisons across scalar and vector fixtures: 329,866.
- Ten mixed scalar half/float/integer/conversion cache, rounding-mode, duplicate
  declaration and prewrite floating-address controls; 100 construction/state,
  composition, loop-reuse and declaration controls; and 16 memory/void declaration
  attribute refusals. LLVM canonicalizes the original strictfp declaration;
  the checker separately mutates its decoded attribute groups.
- Eight shared memory/void storage and lane-work checks cover 4,096 versus
  4,097 vector slots and 1,000,000 versus 1,000,016 work units. The work boundary
  uses 4,096 sixteen-lane calls and 54,308 extractions; one more extraction rejects.

Units pass 2,097,152 exact canonicalization lane/scalar/idempotence checks and
3,264 poison/undef/freeze state checks, plus name/shape/tag guards. Existing
rounding units pass 7,340,032 rational checks and complete coverage of all 34,784
vector declaration keys; saturating conversions pass 8,912,896 rational checks;
vector PHI snapshots pass 731,136 lane/state checks.

Computed index passes 26,029 native exact cases, 50,771 prewrite refusals and
4,096 coordinate cases. Prepared memory passes 28,928 byte comparisons and
3,314 recovery/bounds/budget/metadata controls. Pointer PHIs pass 54,712 native
comparisons and their admission controls. The complete pair-freeze self-test
passes 524,288 native defined/property comparisons and its negative controls.
Other full intrinsic matrices, kernel/guest builds and launch checks were not run.

Fresh final normal and deterministic software Metal processes each pass
106 geometry dispatches, 160 shader images, 262,606 checked invocations,
106 rejected pipelines and two prewrite bounds failures. The new shader observes
scalar/vector half/float NaN quiet bits, float negative zero and half subnormal
retention in its red channel. Queued dispatch, both selectors, clipped groups,
RGBA8 buffer/texture readback, padding, repeated commits and two drained runtimes
are checked. The earlier `software-bits` run generated the previous fixture;
`software-bits-final` contains and validates the new image.

Generated final checker and host C confirm fixed integer words and vector records
with no array allocation on successful canonicalization paths. Results copy into
existing stable construction slots; no new owner or profile field is added.
Declaration caches gain 34 integer entries. Error paths retain V's boxed-error
pattern; existing machine/profile/SSA allocations remain. Heap retention was not
measured, leak detection was disabled and native JIT code was not sanitizer
instrumented. This is CPU software Metal evidence; native GPU execution,
Fortnite launch gates, a Fortnite frame and complete Metal support remain unverified.

The initial checker passed its vector matrix but found a missing scalar entry in
the separate memory admission allowlist. That entry is fixed; fresh full checks
pass. Initial test-generator and host-edit helper diagnostics are documented;
all retained baseline/failed/successful evidence remains intact. The final
mixed-key fixture uses ctpop.i59 to guard against an enum-derived key collision.

## Retained evidence

Canonical original workspace:
`/Users/alex/Library/Caches/vinix-ios/canonicalize-20261116-r1`.

Complete archive:
`/Users/alex/Library/Caches/vinix-ios/canonicalize-20261116-r1.tar.gz`.

- Archive SHA-256: `70043fa96288c295ac8e6569d0a2c9620a7a0942ff8ffc243b6d3775469a2871`.
- Complete typed inventory: sibling `.inventory.json`, SHA-256 `a0bc53bd13a3c3d9c5c946e6eee25897696c3385b8c9e50e1b64170088d7f3f2`.
- Source snapshot: workspace `source.tar`, SHA-256 `1e6a35e0a6976964305ddb31b4dd173e3cece7203d10bc8fbbab70b70d1259f0`.

Inventory and archive checks compare every path, type, mode, link, size and
logical file hash, including root mode. Originals remain retained. This records
integrity without claiming restoration replay or authorizing deletion. Source
revision, commands, executable/tool identities, native targets, generated C,
failed attempts and sanitizer logs are retained; sealing receipts are siblings
outside the sealed workspace.
