# Software Metal scalar/vector address bitcast checkpoint — 2026-11-16

Source revision: `d73a6b0903528a18071e8ceb705295ff50deb2ca`.

Pure integer scalar↔vector bitcasts now feed bounded memory address graphs.
All i1..i64 scalar and fixed 1..16-lane integer vector shapes of equal total
width up to 64 bits are supported on little-endian layouts. Scalar splits
share a result table across selectors; scalar packs eagerly observe every
input lane. Existing scalar and vector operations compose with the casts.
Floating dependencies, loaded values and PHIs remain excluded from pure
address graphs. Pointer access, bounds, alignment and permission checks retain
their existing contracts, and validation finishes before the first write.

`tests/ios/air-memory-scalar-vector-bitcast-index.v` passes with ASan/UBSan:

- All 422 integer type/container shapes in both directions; 235,104 cases:
  143,242 valid address outputs and 91,862 prewrite refusals. Refusals include
  52,602 poison addresses, 29,388 undef cases and 9,872 bounds cases.
- 37,856 native LLVM outputs checked against an independent packed-bit oracle.
  Native calls use only defined replacement inputs. Invalid selectors, poison,
  undef, freeze choices and addresses are modeled separately.
- 470,208 scalar/integer API checks and 37,980 short prepared-budget refusals.
  Prepared validation is nonmutating. Both memory execution APIs check all
  output bytes and backing offsets, including the preceding marker store.
  2,532 scalar-undef function profiles reject during preparation; their
  ordinary executions also reject without writes. Other runtime refusals are
  checked through prepared validation and both execution APIs.
- 67 controls include scalar/vector arguments, source/result freeze, poison
  spreading on round trips, insert/shuffle/binary/select composition, multiple
  selectors, cached roots before/after freeze, inactive/unchosen undef,
  negative/out-of-range offsets, metadata/endian guards and excluded sources.
  Eight of these controls exercise the exact 32-level and 256-node boundaries
  for both directions. Cached shallow roots retain their complete height;
  adding one level/node rejects without executing the preceding marker store.

Two existing sanitized unit suites pass: scalar/vector bitcasts and integer
vector reshaping. Three controls regressions pass: 54 scalar/vector value
controls, 42 floating reshape controls and 52 vector integer cast address
controls. The full earlier vector-to-vector integer bitcast address regression
passes 399 shapes, 220,733 exact outputs, 149,923 prewrite refusals (46,332 undef),
85,248 native/oracle lanes, 741,312 integer/mixed results and 44 controls.
Computed-index regression passes 26,029 native exact cases, 50,771 prewrite
refusals (21,399 LLVM overflow cases) and 4,096 vector-coordinate cases.
Prepared memory passes 28,928 byte comparisons and 3,314 changing-input,
recovery, bounds/budget and copied-metadata controls.

Fresh software Metal processes pass in normal and deterministic modes, each
with 106 geometry dispatches, 80 shader images, 173,846 checked invocations,
106 rejected pipelines and two prewrite bounds failures. The new image kernel
splits the x coordinate into bytes and packs it back through a constructed
vector; the destination GEP uses the reconstructed coordinate. Checks cover
actual queued dispatch, RGBA8 buffer/texture readback, every padded backing
byte, both dispatch selectors, clipped groups, repeated commits and drained
runtimes.

Generated checker and host C use fixed stack parent indices and POD records
in the existing bounded node array/cache. No persistent owner, node field,
evaluator kind, pointer or free path is added. Existing cache cleanup,
error cleanup and successful profile ownership transfer remain intact.
Existing array/map growth and error allocations remain. Heap retention was
not measured, leak detection was disabled and native JIT code was not
sanitizer-instrumented. Broader runtime, other full cast matrices and
kernel/guest builds were not repeated.

Early external generator builds needed literal interpolation escaping, and
the first checker compile incorrectly used nil for a value-returning prepared
plan. An explicit availability flag fixed the checker. Available failed logs
and initial successful probe outputs remain in the bundle. The final matrix
includes fixed aggregate count assertions and all graph-limit controls.
Production implementation needed no correction during qualification.

This is CPU software Metal evidence. Native GPU execution, guest/Fortnite
launch gates, a Fortnite frame and complete Metal support remain unverified.

## Retained evidence

Canonical original workspace (retained in place):
`/Users/alex/Library/Caches/vinix-ios/scalar-vector-bitcast-index-20261116-r1`.

Complete archive:
`/Users/alex/Library/Caches/vinix-ios/scalar-vector-bitcast-index-20261116-r1.tar.gz`

- Archive SHA-256: `70b9cee9820d56757e4e005b596caa4802bb90fd352851091c1ec131c7a55c98`.
- Complete typed inventory: sibling `.inventory.json`, SHA-256 `83589cdd178961e3170be42f445c548acf2b25f3b9b25033b1e6ddb3258f032b`.
- Source snapshot: workspace `source.tar`, SHA-256 `bf83af4dbfbb66eafaf0388e6a4f9ebaa75f154cb35cde3d4bf92705305cc735`.

The archive check decodes all logical payloads and compares the complete
workspace's paths, types, modes, symlink targets, sizes and hashes, including
root mode. Inventory comparison passes before compression and is rechecked by
the archive tool afterward. This is integrity verification with originals
retained; it does not claim a restoration replay or authorize deletion.
Commands, source revision, LLVM target/features, generated C, captured compiler,
executable identities, sanitizer logs and available failed attempts are in the
bundle. Sealing commands/statuses are siblings outside the sealed workspace.
