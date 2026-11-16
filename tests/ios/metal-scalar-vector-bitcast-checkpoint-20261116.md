# Software Metal scalar/vector bitcast checkpoint — 2026-11-16

Source revision: `9deda2752e8138e958f26fb41097367570db0298`.

The bounded AIR interpreter now executes unflagged scalar↔vector bitcasts
between i1..i64, half and float shapes of equal total width up to 64 bits,
with 1..16 vector lanes on little-endian layouts. Raw packing preserves
non-byte boundaries and floating NaN payloads without floating arithmetic.
Scalar poison spreads to split lanes; any poison vector lane poisons the
packed scalar. Executed undef inputs fail eagerly. Source/result freezes
retain the interpreter's existing explicit zero choice and error ordering.
Only vector results consume construction slots; scalar packs retain ordinary
SSA storage. Pure address graphs continue to reject these casts.

The maintained checker is `tests/ios/air-scalar-vector-bitcast.v`. Its final
ASan/UBSan run covers every supported type/container shape in both directions:

- 460 shapes and 255,456 execution cases: 166,218 exact/frozen outputs,
  57,306 poison-store refusals and 31,932 strict undef failures.
- 40,992 native LLVM outputs checked against an independent bit-position
  oracle. Native execution uses only defined replacement inputs; poison,
  undef and freeze expectations are modeled separately.
- 510,912 scalar/integer API checks, ordinary and prepared memory execution,
  nonmutating validation and 44,160 short prepared-budget refusals. Output
  checks cover marker ordering, backing offsets, all result bytes and guards.
- 54 controls cover composition, old results, source/result freeze, poison
  spreading on round trips, discarded/cold undef, loop slot reuse,
  unsupported widths, address rejection, metadata and endian guards.
- Eight shared-boundary outcomes cover ordinary memory and void APIs:
  4,096 vector splits plus 4,096 scalar packs fit construction storage;
  a 4,097th vector result rejects before writes. Exactly 1,000,000 lane work
  fits; one additional lane rejects before writes.

Four sanitized unit suites pass: new scalar/vector profiles and packing,
scalar casts, original integer/FP vector bitcasts and integer vector reshaping.
The new unit checks 9,464 independent packed/split outputs and round trips
plus 9,098 poison spreading/undef states over all supported integer shapes.
Five focused cast/reshape regressions pass their controls modes: 121 original
bitcast, 130 integer-cast, 590 int-to-float, 546 float-to-int and 42 floating
reshape controls. Their former scalar/vector rejection fixtures now exercise
unsupported 128-bit shapes; full default matrices remain intact.

The computed-index regression passes 26,029 exact native cases, 50,771
prewrite refusals (21,399 LLVM overflow cases) and 4,096 vector-coordinate
cases. Prepared memory passes 28,928 byte comparisons and 3,314 changing-input,
recovery, bounds/budget and copied-metadata controls.

Final fresh software Metal host processes pass in normal and deterministic
modes, each with 106 geometry dispatches, 72 shader images, 164,970 checked
invocations, 106 rejected pipelines and two prewrite bounds failures. The new
image kernel passes integer→half-vector→float→byte-vector→integer values
through actual queued dispatch and RGBA8 buffer/texture readback. Both the
selected byte and the packed scalar's nonzero high byte affect the pixels.
Checks include padded backing bytes, both dispatch selectors, clipped groups,
repeated commits and drained runtimes.

Generated checker and final host C retain fixed by-value source/result records
and existing vector slots, with no new owner, cache, escaping pointer or free
path. The execution wrapper introduces no array allocation, boxing or floating
arithmetic. Existing execution/profile/error allocations remain. Heap retention
was not measured, leak detection was disabled, and native JIT code was not
sanitizer-instrumented. Full earlier cast matrices, broader runtime tests and
kernel/guest builds were not repeated.

The first standalone checker compile failed on a conditional combining two
public result types; separate assertions fixed the checker. Failed logs remain.
The initial complete reference run and initial successful image run are retained;
`reference-final` adds fixed aggregate-count assertions and `software-bits-final`
strengthens scalar-pack pixel observability. These final runs are qualified.

This is CPU software Metal evidence. It does not establish native GPU execution,
a guest launch gate, a Fortnite frame or complete Metal support.

## Retained evidence

Canonical original workspace (retained in place):
`/Users/alex/Library/Caches/vinix-ios/scalar-vector-bitcast-20261116-r1`.

Complete archive:
`/Users/alex/Library/Caches/vinix-ios/scalar-vector-bitcast-20261116-r1.tar.gz`

- Archive SHA-256: `42d93d3101759afbd6c3b397b1b929048cb66c8cbb98f1e3a49d3694f832a359`.
- Complete typed inventory: sibling `.inventory.json`, SHA-256 `55597765393a64f1916f54782c6500a5cd0d92963872f46ab015b49f2eece0b6`.
- Source snapshot: workspace `source.tar`, SHA-256 `c915ef46824b685dba3ca0acc354b9389293cc4bffdde81551a591734f912ccd`.

The archive check decodes all logical payloads and compares the complete
workspace's paths, types, modes, symlink targets, sizes and hashes, including
root mode. Inventory comparison passes before compression and is rechecked by
the archive tool afterward. This is an integrity audit with originals retained;
it does not claim a fresh restoration replay or authorize deletion. Commands,
checksums, source revision, LLVM target/features, generated C, captured compiler,
executable identities, sanitizer logs, successful and failed attempts are in the
bundle. Sealing commands/statuses are siblings outside the sealed workspace.
