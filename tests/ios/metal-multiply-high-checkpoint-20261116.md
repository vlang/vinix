# Software Metal multiply-high checkpoint — 2026-11-16

Source revision: `8563c951bf6ff62c33789dd04ddbe8ea09ffe15b`.

The AIR interpreter executes signed `llvm.smulh` and unsigned `llvm.umulh` for
scalar i1..i64 and fixed 1..16-lane integer vectors. Results are the high N bits
of the full 2N-bit product, following the
[LLVM multiply-high definitions](https://llvm.org/docs/LangRef.html#llvm-smulh-intrinsic).
Four 32-bit limb products handle i64 without host i128 or signed arithmetic;
signed high halves use modular unsigned corrections. Inputs are masked to N bits.

Scalar, void and both memory APIs admit exact ordinary direct declarations;
the integer-only API admits vector calls through its existing intrinsic path.
Poison propagates per lane and observed undef rejects, including unselected
result lanes. Source and result freezes retain existing behavior. Pure bounded
address graphs accept scalar calls and projected vector lanes; both operands
use existing binary node/height accounting. Existing 256-node/32-level bounds,
forward-only memory control flow and unsupported floating/scalable/wider forms
remain. Calls cost one step, vectors one shared construction slot and 3*N
validation lane-work units. Scalar keys 2026..2153 and vector keys 34784..36831
append without moving earlier identities.

`tests/ios/air-multiply-high.v` passes with ASan/UBSan across every width and
lane count, both signednesses, raw upper-bit garbage and independent bit-column
products. Native comparison uses explicit sext/zext to 2N bits, multiplication,
logical shift and truncation, including i128 for i64. Installed LLVM 23.1.5
reports intrinsic IDs zero for both names; interpreter-only definitions are
deleted before JIT. This checks widened LLVM arithmetic rather than claiming
native execution of unavailable multiply-high intrinsics.

- 278,528 exact native vector lanes and 65,536 exact native scalar values:
  344,064 native reference values total. A further 65,536 scalar/integer vector
  extraction checks use those references. Both memory APIs check every output
  byte, offset bindings, earlier markers and nonmutating prepared validation.
- 137,216 scalar/vector address checks include changing inputs, both memory APIs
  and 6,144 out-of-range projection refusals across validation/direct/prepared
  execution. Invalid addresses reject before the marker store.
- 16,384 metadata refusals and 4,096 short memory budgets preserve every output
  byte. Dedicated controls pass 163 state/freeze/undef/address, loop reuse/budget,
  duplicate declaration, name/type/attribute and resource-boundary checks.
  Vector-PHI loops run 1, 2, 3, 7, 16, 257, 513 and 1,024 visits. Twelve boundary
  fixtures exercise memory/void/scalar APIs at 4,096 versus 4,097 slots and
  1,000,000 versus 1,000,016 lane-work units; scalar fixtures also check the
  integer API. Work comprises 4,096 sixteen-lane binary calls plus 50,212
  extractions; one extra extraction rejects.

Units pass 240,296 independent bit-column products, including every signed and
unsigned i1..i8 operand pair and i1..i64 boundary/deterministic patterns;
17,408 independent vector lanes/snapshots; and 8,192 poison/undef/freeze states.
Strict name, width, shape, family and tag guards pass. Existing rounding units
pass 7,340,032 rational checks and full coverage of 36,832 vector cache entries;
scalar integer units pass 733,180 checks. Canonicalization units pass 2,097,152
lane/scalar/idempotence checks and its complete maintained reference program
again passes 329,866 exact native comparisons and all controls.

Computed index passes 26,029 native exact cases, 50,771 prewrite refusals and
4,096 coordinate cases. Prepared memory passes 28,928 byte comparisons and
3,314 recovery/bounds/budget/metadata controls. Pointer PHIs and the complete
pair-freeze self-test pass, including 54,712 and 524,288 native comparisons.
Other full intrinsic matrices and kernel/guest builds were not repeated.

Corrected fresh normal and deterministic software Metal processes each pass
106 geometry dispatches, 168 shader images, 271,482 checked invocations,
106 rejected pipelines and two prewrite bounds failures. The new shader uses
both scalar and vector signed/unsigned high products in its red channel and
reconstructs the output coordinate from a vector unsigned high product. Queued
dispatch, both selectors, clipped groups, RGBA8 buffer/texture readback, padding,
repeated commits and two drained runtimes are checked.

Generated checker and host C confirm fixed words, tuples and vector records
without array allocation on successful evaluation paths. Existing stable result
slots and binary/projected intrinsic nodes carry results; no owner, node kind or
profile field is added. Caches gain 2,176 integer entries. Existing boxed error
and machine/profile/SSA/graph allocation paths remain. Heap retention was not
measured, leak detection was disabled and native JIT code was not instrumented.
This is CPU software Metal evidence. Native GPU execution, Fortnite launch gates,
a Fortnite frame and complete Metal support remain unverified.

Initial unit/checker compile diagnostics, a missing fixture data layout and a
duplicate shader variable stopped earlier attempts. Corrected fresh checks pass;
original logs and sources remain. A finalization helper's Result-unwrap spacing
was corrected in `finish-v2.v`; it generated C, checked receipts and committed
the feature. No final sanitizer or runtime check fails.

## Retained evidence

Canonical original workspace:
`/Users/alex/Library/Caches/vinix-ios/multiply-high-20261116-r1`.

Complete archive:
`/Users/alex/Library/Caches/vinix-ios/multiply-high-20261116-r1.tar.gz`.

- Archive SHA-256: `bf151ceaf458e45e69e124432e2261df2fccfa01da8a7a938f67ec97b330e99d`.
- Complete typed inventory: sibling `.inventory.json`, SHA-256 `b03f0a8b7213c888df9059fc6b71c1765fab0cffdd9973a97550c579a2125913`.
- Source snapshot: workspace `source.tar`, SHA-256 `c52b9f9eb64f5bdce41dc1cda90b9f3461678a8b512f2aca47d15cef24e068d3`.

Inventory and archive checks compare every path, type, mode, link, size and
logical file hash, including root mode. Originals remain retained. This records
integrity without restoration replay or permission to delete evidence. Source,
commands, executable/tool identities, native targets/availability, generated C,
attempts and sanitizer logs remain; sealing receipts are siblings outside the
sealed workspace.
