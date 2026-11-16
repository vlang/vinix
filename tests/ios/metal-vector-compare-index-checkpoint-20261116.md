# Integer vector comparisons in buffer indices — 2026-11-16

Source revision: `8a36a2dc82f9758886d6af57a0a0fc658ebc795b`.

Pure buffer address graphs now accept integer vector `icmp` with matching
1..16-lane i1..i64 operands and i1 results. All ten equality, signed and unsigned
predicates accept `samesign`. Operand poison and violated sign promises stay
lane-local. Both complete operands compare before extraction: any undef rejects
before writes, including ignored lanes, invalid selectors, later unchosen
selects and result freezes. Source freeze repairs operands first; result freeze
may repair comparison poison. Original extraction bounds remain. Existing
insertion, shuffle, arithmetic, cast, select and freeze sources compose with
comparison masks. Floating comparisons, bitcasts, vector conditions and
loaded/PHI dependencies remain excluded from these address graphs.

Each comparison materializes one contiguous i1 table, cached with POD metadata
under the existing vector tag. Static selectors project both operands; result
nodes check both undef tags and reuse the scalar integer comparator with its
source width distinct from i1. Maximum heights retain all source/result/selector
and cached dependencies under the existing 256-node/32-level limits. Two fixed
16-int builder arrays hold input indices. Generated C confirms stack arrays and
push records, by-value metadata and the existing fixed runtime arrays. No owned
field or runtime map/array is added; existing graph/cache storage and free paths
remain. Normal error allocation remains; heap retention is unmeasured.

ASan/UBSan checks pass on macOS ARM64:

- 1,834,560 address cases: 1084150 exact outputs and 750410 prewrite
  refusals, including 152880 checks with unrepaired undef. All i1..i64
  widths use count 3; widths 1/8/16/32/64 additionally cover every count 1..16.
  Each covers ten predicates with/without `samesign`, selector widths 1/32/64,
  eight operand patterns and three modes: direct arguments, constant operands
  with result freeze, and source freezes followed by vector zero-extension.
  Scalar zero-extension and masked sign-extension exercise 0/1 and 0/63 addresses.
  Validation, ordinary and prepared execution agree, preserving every output
  byte on refusal. Argument/selector padding is deliberately nonzero.
- 411,360 defined native LLVM comparison lane results match an independent
  oracle that flips the sign bit for signed order. Separate sign checks model
  promise poison. Native references omit `samesign` and replace indeterminate
  input lanes with zero, avoiding native poison and invalid memory operations.
- Fifty controls cover exact cached left/right source, selector and result-freeze
  depths 32/33 and 256/257 nodes, both operands' ignored undef, scalar/result
  recovery limits, lane-local poison, sign promises, old/frozen consumers,
  distinct selector reuse, independent roots in both orders, cold dependencies,
  insertion repair, shuffle/arithmetic/cast/select/nested comparison composition,
  eager source division errors, unsupported dependencies and malformed metadata.
- Eleven unit suites pass, including 2,088,960 integer comparisons across all
  64 widths, all counts 1..16 and all predicates/flags, 43,520 half/float truth
  table checks and the comparison undef/type/flag guards.
- All 43 earlier core programs pass, plus the earlier vector-cast checker's
  52-control mode. Its full 6,993,504-case matrix was not repeated. Nine older
  rejection fixtures now use floating vector comparisons; rejection assertions
  remain intact. Historical bundles and auditors are unchanged.
- Both image modes pass four sizes with exact RGBA/padding readback, using fresh
  processes and freshly compiled binaries. The shader compares its truncated
  lane mask against zero before zero-extension, and independent red-channel
  expectations observe the inverted permutation. Each mode reports 106 geometry
  dispatches, eight shader images, 93,962 checked invocations, 106 rejected
  pipelines and two prewrite bounds failures.

The matrix and all fifty controls passed their first checker executions.
An initial smoke wrapper reused its checker's filename and invoked the wrapper
again; distinct filenames fixed the tooling. The computed-index regression
initially rejected a newly supported integer comparison; changing that stale
guard to a floating comparison passed a fresh retry. Both failed attempts and
the original generated IR/binaries/logs remain. Production did not change after
qualification began. Modules are partitioned by width and lane count.

Evidence: `/Users/alex/Library/Caches/vinix-ios/vector-compare-index-20261116-r1`.
Archive: `/Users/alex/Library/Caches/vinix-ios/vector-compare-index-20261116-r1.tar.gz`.
Complete inventory and archive logical-byte/metadata comparisons pass.
Originals remain retained; no restoration replay is claimed.

- Archive SHA-256: `a9a3034f20b9d6f1132862a20585e3047cfd027a29374f8436b54788e17ea8ae`.
- Inventory SHA-256: `ecf985712e0a5e453ac848fd3add196cd258a4fcae109b2916c4bd863c2349db`.
- Source archive SHA-256: `050c9df09c2605452f72dd7d22817abe40a86396acb6b2f046652e9e7025a866`.

The bundle retains rows, IR/bitcode, generated C, images, binaries, commands/logs,
source/tool hashes and ownership review. Source inputs match the feature commit.
Reproduce with `tests/ios/air-memory-vector-compare-index.v LLVM_AS FRESH_EXTERNAL_DIR`
and `tests/ios/metal-software-checks.v FRESH_EXTERNAL_DIR sizes`, using repository
module paths and the retained toolchain. Dependencies remain referenced; this is
not hermetic. Native JIT is uninstrumented and leak detection is disabled.
CPU software Metal only is qualified; no broad runtime suite, native GPU,
guest launch or new Fortnite frame is verified.
