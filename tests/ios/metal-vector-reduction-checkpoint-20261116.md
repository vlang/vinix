# Software Metal integer vector reduction checkpoint — 2026-11-16

Source revision: `31bb2f0c9cfeaa31d2f4afa343162e1b057a0aa2`.

The bounded AIR interpreter executes ordinary direct integer
`llvm.vector.reduce.{add,mul,and,or,xor,smin,smax,umin,umax}.vNiW` calls for
fixed 1..16-lane i1..i64 vectors, returning scalar iW. Arithmetic wraps at W
bits. All source lanes are observed: poison poisons the scalar result, even
with annihilating operands, and executed undef rejects eagerly. Source freeze
repairs indeterminate lanes; result freeze chooses zero for poison but cannot
hide an earlier undef error. Integer, mixed, void and memory APIs support the
calls. Memory may consume existing vector arguments/loads. Pure address
graphs and floating/scalable reductions remain excluded. Canonical overloads,
exact signatures, declaration identities and attributes are validated.

`tests/ios/air-vector-reduction.v` passes with ASan/UBSan:

- 1,251 operation/width/count shapes and 40,032 cases: 32,526 exact/frozen
  scalar values, 2,502 poison-store errors and 5,004 strict undef errors.
  Coverage includes every width with three lanes, plus all counts 1..16 at
  widths 1/8/16/32/64, nine operations, eight patterns and four expression modes.
- 40,032 native LLVM results match an independent arithmetic/extrema oracle.
  Native calls use only defined replacement words; poison, undef and freeze
  choices are checked separately in the interpreter. There are 80,064
  scalar/integer API checks, plus ordinary and prepared memory execution for
  every case. Nonmutating validation and all backing bytes/marker ordering
  are checked. Each of 40,032 short budgets rejects before writes.
- 117 controls cover composition with insertion/binary/shuffle/select,
  all nine cached declarations in one body, literal and loaded vectors,
  cold and discarded indeterminate results, malformed call/type metadata,
  names and duplicate declaration identities. Sixteen scalar/integer loop
  checks cover 1 through 1,024 visits to reused construction slots.
- Memory and void controls check 4,096 versus 4,097 vector construction
  results and exactly 1,000,000 versus 1,000,001 validation lane-work units,
  including the expected rejection diagnostics. Scalar reductions consume
  N+1 work units each and no additional vector construction slots.

The sanitized unit suite passes 860,148 independent values, including all
widths/counts, exhaustive i1..i8 pairs, upper-bit masks and source snapshots;
156,672 all-lane poison/undef checks; and 8,640 later-undef-after-earlier-poison
checks. Existing vector carry-less multiply and rounding units pass. All
34,496 declaration-cache identities remain injective: 9,216 appended reduction
identities preserve the previous keys. Generated checker C contains both
profile caches; the focused host contains its used memory-profile cache and
omits its unused integer profile. Each cache grows by 72 KiB of stack.

Computed-index regression passes 26,029 exact native cases, 50,771 prewrite
refusals (21,399 LLVM overflow cases) and 4,096 vector-coordinate cases.
Prepared memory passes 28,928 byte comparisons and 3,314 changing-input,
recovery, bounds/budget and copied-metadata controls. Earlier controls pass:
650 vector carry-less multiply, 696 vector bit-permutation and 67
scalar/vector bitcast address controls. Other full vector matrices were not
repeated.

Fresh normal and deterministic software Metal processes each pass 106 geometry
dispatches, 104 shader images, 200,474 checked invocations, 106 rejected
pipelines and two prewrite bounds failures. The new image constructs a vector
of x/y/grid-width/grid-height, reduces it to a scalar sum and uses that result
in its red channel. Tests exercise queued dispatch, RGBA8 buffer/texture
readback, padded backing bytes, both dispatch selectors, clipped groups,
repeated commits and two drained runtimes per process.

Generated checker and host C retain fixed by-value source/result records and
a fixed prefix table without new arrays in the reduction helper or name
parser. Existing scalar SSA slots, ownership and cleanup are reused. No new
evaluator kind, graph node field, escaping pointer, lifetime extension or free
path is added. Existing allocation/error paths remain. Heap retention was not
measured, leak detection was disabled and native JIT code was not sanitizer
instrumented. Broader runtime and kernel/guest builds were not repeated.

Initial compile diagnostics are retained: an incorrect unary helper choice
was corrected to the existing binary extrema helper; the checker generator's
immutable string was made mutable; and a checker-local variable shadowing its
mask function was renamed. The corrected controls probe and all final
qualified matrix, unit, regression and image runs pass without runtime
failures. The final focused unit rebuild adds the 8,640 mixed-state guards.
All original evidence is retained.

This is CPU software Metal evidence. Native GPU execution, guest/Fortnite
launch gates, a Fortnite frame and complete Metal support remain unverified.

## Retained evidence

Canonical original workspace (retained in place):
`/Users/alex/Library/Caches/vinix-ios/vector-reduction-20261116-r1`.

Complete archive:
`/Users/alex/Library/Caches/vinix-ios/vector-reduction-20261116-r1.tar.gz`

- Archive SHA-256: `62278da352e1b0214284b740ca6c392713709130eaadde1336d7c5e0e23975c7`.
- Complete typed inventory: sibling `.inventory.json`, SHA-256 `72fb149c68be77677a97a470d43a88c879fd2b4be2268969a1b76c0a6af92960`.
- Source snapshot: workspace `source.tar`, SHA-256 `c6a1f4f39c0fda609c610dc37a8280cc5b5f0c9038d90b58741a612f9f2c66da`.

The archive check decodes all logical payloads and compares the complete
workspace's paths, types, modes, symlink targets, sizes and hashes, including
root mode. Inventory comparison passes before compression and is rechecked by
the archive tool afterward. This records integrity with originals retained;
it does not claim a restoration replay or authorize deletion. Commands,
source revision, LLVM target/features, generated C, captured compiler,
executable identities and sanitizer logs are in the bundle. Sealing
commands/statuses are siblings outside the sealed workspace.
