# Software Metal vector bit permutation checkpoint — 2026-11-16

Source revision: `730c2e7cacff03b2bac0f6c6821b2ce6e6af12a7`.

The bounded AIR interpreter now executes ordinary direct vector `llvm.pext`
and `llvm.pdep` calls for fixed 1..16-lane i1..i64 vectors. Extraction gathers
mask-selected bits into low positions; deposition scatters low bits into
mask-selected positions. Source poison remains lane-local, including zero
masks; any executed undef source lane rejects eagerly. Source/result freezes
retain existing semantics. Integer, mixed, void and memory execution support
the calls, including pure integer address graphs with prewrite validation.
Canonical names, exact signatures, declaration identity, attributes and source
profiles use the existing bounded intrinsic scanner.

`tests/ios/air-vector-bit-permutation.v` passes with ASan/UBSan:

- 244,608 cases: 141,781 exact address outputs and 102,827 prewrite refusals,
  including 45,864 whole-vector undef cases. Ordinary execution, prepared
  execution and nonmutating validation check all backing bytes and marker
  ordering. Invalid selectors, poison, undef, freezes and bounds are modeled
  separately; native LLVM executes only defined replacement inputs.
- 54,848 native LLVM lane outputs match an independent bit-position oracle.
  Coverage includes both operations, all i1..i64 widths with three lanes and
  every count 1..16 at widths 1/8/16/32/64, three selector widths, eight operand
  patterns and four expression modes: 278 operation/width/count combinations.
- 696 controls cover raw scalar/integer and ordinary/prepared memory round
  trips, both source poison/undef states, source/result freezes, zero masks,
  composition, multiple selectors, cold/unchosen undef, argument/metadata
  mismatches, duplicate cache identities and malformed overloads.
- Exact graph depth/node boundaries exercise both operand paths, selectors and
  cached roots. Shared construction/work controls cover 4,096 versus 4,097
  vector results and the 1,000,000 lane-work boundary in memory and void APIs.

The new sanitized unit suite checks 314,048 independent lane outputs,
including every i1..i8 input/mask pair, all widths/counts, upper-bit masking,
zero/full/sparse masks and snapshots; 417,792 poison/undef/freeze checks cover
both operand positions. Existing scalar permutation and vector rounding units
also pass. The cache unit covers all 24,256 old/new identities injectively.
The 2,048 appended identities preserve every previous key. Generated checker C
confirms both existing profile caches now use i64[24256], adding 16 KiB of stack
per cache. The focused host C contains its used memory-profile cache and omits
the unused integer profile. No persistent cache owner is added.

Computed-index regression passes 26,029 exact native cases, 50,771 prewrite
refusals (21,399 LLVM overflow cases) and 4,096 vector-coordinate cases.
Prepared memory passes 28,928 byte comparisons and 3,314 changing-input,
recovery, bounds/budget and copied-metadata controls. Earlier address controls
pass: 67 scalar/vector bitcast, 125 funnel and 98 saturating controls.

Fresh normal and deterministic software Metal processes each pass 106 geometry
dispatches, 88 shader images, 182,722 checked invocations, 106 rejected pipelines
and two prewrite bounds failures. The new image gathers coordinate bits with
`pext`, scatters them with `pdep`, reconstructs the destination coordinate and
uses gathered bits in the pixel color. Tests cover queued dispatch, RGBA8
buffer/texture readback, padded backing bytes, both dispatch selectors,
clipped groups, repeated commits and drained runtimes.

Generated checker and host C use fixed by-value lane records and the existing
bounded scalar permutation helper. Address projection reuses existing POD
nodes, ownership and cleanup. No new evaluator kind, node field, escaping
pointer, lifetime extension or free path is added. Existing allocation/error
paths remain. Heap retention was not measured, leak detection was disabled
and native JIT code was not sanitizer-instrumented. Broader runtime, other
full vector matrices and kernel/guest builds were not repeated.

The initial complete probe matrix passed before extra overload and limit
controls were added. Shared disk exhaustion interrupted the first final run
and prevented parallel qualification/generated drivers from writing temporary
C. Partial `reference-final`/`software-bits` and initial logs remain unqualified;
the interrupted final run has no completed child run log/status. `retry.v`
saves commands before execution and retries serially. All six retries pass;
`reference-final-retry` and `software-bits-retry` are the final qualification.
The same captured final checker executable was reused. No production correction
was needed, and original evidence was retained. The initial finish audit
incorrectly required two caches in the focused host; the final audit asserts
two in the checker and one in the host, matching their emitted functions.
The rejected audit log is retained.

This is CPU software Metal evidence. Native GPU execution, guest/Fortnite
launch gates, a Fortnite frame and complete Metal support remain unverified.

## Retained evidence

Canonical original workspace (retained in place):
`/Users/alex/Library/Caches/vinix-ios/vector-bit-permutation-20261116-r1`.

Complete archive:
`/Users/alex/Library/Caches/vinix-ios/vector-bit-permutation-20261116-r1.tar.gz`

- Archive SHA-256: `fec70876a37994b18464dac18bde3c681f037d7de86ed13e2b35d0e1875a4de4`.
- Complete typed inventory: sibling `.inventory.json`, SHA-256 `29272abf505d51338fd5a5f3b24693389ba7e8cf445e9985cc7f8d34093920ec`.
- Source snapshot: workspace `source.tar`, SHA-256 `21f2fe92f93c931768098aacd88dd40a7e5e7cf968488c8aa8e4f59b75f23ea0`.

The archive check decodes all logical payloads and compares the complete
workspace's paths, types, modes, symlink targets, sizes and hashes, including
root mode. Inventory comparison passes before compression and is rechecked by
the archive tool afterward. This records integrity with originals retained;
it does not claim a restoration replay or authorize deletion. Commands,
source revision, LLVM target/features, generated C, captured compiler,
executable identities, sanitizer logs and failed attempts are in the bundle.
Sealing commands/statuses are siblings outside the sealed workspace.
