# Integer vector casts in buffer indices — 2026-11-16

Source revision: `fcfc33d79b75ab966fd28a10d0a7cd2538763d87`.

Pure buffer address graphs now accept integer vector trunc/zext/sext with
matching lane counts and strict i1..i64 narrowing/widening directions. Trunc
accepts nuw/nsw and zext accepts nneg; violated promises and source poison stay
lane-local. Every input lane casts before extraction. Any undef rejects the
cast address dependency before writes, including ignored lanes, invalid
extraction selectors, later unchosen selects and result freezes. Source freeze
repairs operands first, while result freeze may repair cast poison. Original
extraction bounds remain checked. Supported arguments, constants, selects,
insertion, shuffle, arithmetic and earlier casts compose in either direction.
Vector comparisons, floating conversions, bitcasts and loaded/PHI dependencies
remain excluded from address graphs.

Each cast materializes a contiguous result table once, with POD metadata under
vector cache tag 3 retaining its base and maximum lane height. Static selectors
project all inputs; cast nodes reject undef then call the existing scalar integer
cast evaluator with source/destination widths and flags. Table reads reuse
constant-lane nodes with no undef mask. All source/result/selector and cached
heights retain the 256-node/32-level limits. One fixed 16-int builder array holds
parent indices. Generated C confirms stack arrays/push records, by-value metadata
and fixed runtime arrays, with no new runtime storage owner. Existing noslices
graph/cache storage, growth and free paths remain. Normal error allocation
remains; heap retention is unmeasured.

ASan/UBSan checks pass on macOS ARM64:

- 6,993,504 address cases: 3080480 exact outputs and 3913024 prewrite
  refusals, including 582792 checks with unrepaired undef operands.
  All 4,032 distinct i1..i64 width pairs, seven opcode/flag variants, selector
  widths 1/32/64, eight operand patterns and three expression modes cover
  direct arguments, constant poison/undef, source/result freezes and noisy
  argument padding. Every width pair uses count 3; the twenty ordered distinct
  pairs drawn from 1/8/16/32/64 additionally use every count 1..16. Masked,
  widened and high/low-bit-folded addresses are checked. Validation, ordinary
  and prepared execution agree and preserve all bytes on refusal.
- 1,239,504 defined native LLVM vector-cast lane results match an independent
  per-bit value oracle. Separate per-bit promise checks decide poison; native
  reference casts omit promise flags and use zero for indeterminate source
  lanes. No native poison or invalid memory operation executes.
- Fifty-two controls cover exact cached source/selector/freeze/nested depths
  32/33, exact 256/257-node limits, result-table reuse with distinct selectors,
  ignored undef and scalar/result recovery limits, lane-local poison, nneg
  and trunc nuw/nsw failures, sign extension, old/frozen consumers, independent
  roots in both orders, cold dependencies, insertion repair, shuffle/arithmetic/
  select composition, eager source division errors, unsupported dependencies
  and malformed flags/opcode/arity/indices/result type/width direction.
- All 43 existing core programs and ten unit suites pass. Existing cast unit
  checks include 1,806,336 independent per-bit lanes across every width pair
  and 719,712 poison/undef controls. Seven maintained cast-source rejection
  fixtures now use unsupported vector comparisons followed by sign extension;
  rejection assertions remain. Other core checks are unchanged. Historical
  retained bundles and auditors remain untouched.
- The image shader truncates its wrapped channel indices to i1, then
  zero-extends them to i32. Independent red-channel expectations observe the
  changed permutation. Four sizes pass exact RGBA/padding readback in both
  hashing modes, using fresh processes and freshly compiled binaries. Each mode
  reports 106 geometry dispatches, eight shader images, 93,962 checked
  invocations, 106 rejected pipelines and two prewrite bounds failures.

The control smoke, complete address matrix and native/per-bit lane checks
passed on their first runs. Production remained unchanged throughout
qualification. Modules are partitioned by width pair and lane count.

Evidence: `/Users/alex/Library/Caches/vinix-ios/vector-cast-index-20261116-r1`.
Archive: `/Users/alex/Library/Caches/vinix-ios/vector-cast-index-20261116-r1.tar.gz`.
Complete inventory and archive logical-byte/metadata comparisons pass.
Originals remain retained; no restoration replay is claimed.

- Archive SHA-256: `73dd6687f27a158a0cc1909b71361cf80a2d3dedce7a31649ff6447d45eef3a9`.
- Inventory SHA-256: `9d908cf9dca60515b848d3c5200bf7952e29183205192ad19718ab5060e33e8c`.
- Source archive SHA-256: `5f8ffd644331b82c4a451936ea90e2e746f3641cc9ee84eddb86ec11364d1819`.

The bundle retains rows, IR/bitcode, generated C, images, binaries, commands/logs,
source/tool hashes and ownership review. Source inputs match the feature commit.
Reproduce with `tests/ios/air-memory-vector-cast-index.v LLVM_AS FRESH_EXTERNAL_DIR`
and `tests/ios/metal-software-checks.v FRESH_EXTERNAL_DIR sizes`, using repository
module paths and the retained toolchain. Dependencies remain referenced; this is
not hermetic. Native JIT is uninstrumented and leak detection is disabled.
CPU software Metal only is qualified; no broad runtime suite, native GPU,
guest launch or new Fortnite frame is verified.
