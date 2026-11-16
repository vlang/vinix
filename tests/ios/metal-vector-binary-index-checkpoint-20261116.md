# Integer vector arithmetic in buffer indices — 2026-11-16

Source revision: `547d3d1d2b96d15488432d1d990fbcc775642805`.

Pure buffer address graphs now accept integer vector add/sub/mul, unsigned and
signed division/remainder, shifts, and/or/xor with existing nuw/nsw/exact/disjoint
flags. Fixed vectors have 1..16 i1..i64 lanes and may use supported arguments,
constants, selections, insertion, shuffle, freeze and earlier binary results.
Every operand lane computes before extraction. Undef and invalid/poison division
operands reject the address dependency before writes, including ignored lanes,
invalid extraction selectors, later unchosen selects and result freezes. Other
poison stays lane-local and may be ignored or repaired by result freeze. Source
freeze repairs operands first but cannot suppress subsequent arithmetic errors.
Floating arithmetic, vector casts and loaded/PHI dependencies remain excluded.

Each binary instruction materializes a contiguous result table once, with POD
metadata under vector cache tag 3 retaining the base and maximum lane height.
Static selectors project both full sources; binary nodes reject undef and call
the existing integer evaluator. Table reads reuse constant-lane nodes with no
undef mask. All source, table, selector and cached heights charge the existing
256-node/32-level limits. Two fixed 16-int builder arrays hold temporary indices.
Generated C confirms stack arrays/push records and by-value metadata, with no new
runtime storage owner. Existing noslices graph/cache storage, growth and free
paths remain. Normal error allocation remains; heap retention is unmeasured.

ASan/UBSan checks pass on macOS ARM64:

- 5,024,160 cases: 1809032 exact outputs and 3215128 prewrite refusals.
  Whole-vector undef is present in 628020 cases; 789120 cases exercise
  rejected division/remainder inputs, including indeterminate operands. These
  categories overlap. All 64 lane widths, selector widths 1/32/64, counts
  1/2/3/16 plus every count at i32, thirteen opcodes, thirty flag variants,
  eight operand patterns and three expression modes cover direct arguments,
  constant poison/undef, source/result freezing and noisy argument padding.
  Masked, widened and high/low-bit-folded final addresses are checked.
  Defined flagless native LLVM vector operations provide result bits; independent
  carry/sign/magnitude promise checks decide poison. Native reference operands
  sanitize indeterminate lanes, zero/overflow division and overshifts before
  execution. No invalid native arithmetic or poisoned memory operation executes.
  Validation, ordinary and prepared execution agree, preserving every byte on
  refusal.
- Forty-seven controls cover exact cached left/right/selector/freeze/nested
  depths 32/33, exact 256/257-node limits, shared result tables with distinct
  selectors, whole-vector undef/division errors in ignored lanes, invalid
  extraction, scalar/result recovery limits, lane-local poison and overshifts,
  old/frozen consumers, independent roots in both orders, cold dependencies,
  insertion repair, shuffle sources, unsupported dependencies and malformed
  flags/opcode/arity/indices/result type.
- All 42 existing core programs and nine unit suites pass. Binary unit checks
  include 425,472 independent widened i1..i16 lane checks, 9,840 whole-vector
  division rejections and 452,608 poison/undef controls across i1..i64. Six
  maintained arithmetic-source rejection fixtures now use unsupported vector
  cast chains; rejection assertions remain. Other core checks are unchanged.
  Historical retained bundles and auditors remain untouched.
- The image shader freezes its shuffled permutation before vector add with
  nuw/nsw and vector remainder, then uses the resulting channel index.
  Independent red-channel expectations observe the arithmetic. Four sizes pass
  exact RGBA/padding readback in both hashing modes, using fresh processes and
  freshly compiled binaries. Each mode reports 106 geometry dispatches, eight
  shader images, 93,962 checked invocations, 106 rejected pipelines and two
  prewrite bounds failures.

The control smoke and complete matrix passed on their first runs. Production
remained unchanged throughout qualification. The generator partitions modules
by input count to stay within existing parser limits.

Evidence: `/Users/alex/Library/Caches/vinix-ios/vector-binary-index-20261116-r1`.
Archive: `/Users/alex/Library/Caches/vinix-ios/vector-binary-index-20261116-r1.tar.gz`.
Complete inventory and archive logical-byte/metadata comparisons pass.
Originals remain retained; no restoration replay is claimed.

- Archive SHA-256: `75fe11a0d6dc151d649f5a5cdbe3aa3eb9d8d3937b6183048218a62082bb1bf7`.
- Inventory SHA-256: `f3445105af5b7e184cebde4cd413ba24695c7d3d62643a959067020fd9d000d8`.
- Source archive SHA-256: `acebd9237d3521f6f400f4c127d6aa44757d2b2ed92f6020f5179bcfba336f2c`.

The bundle retains rows, IR/bitcode, generated C, images, binaries, commands/logs,
source/tool hashes and ownership review. Source inputs match the feature commit.
Reproduce with `tests/ios/air-memory-vector-binary-index.v LLVM_AS FRESH_EXTERNAL_DIR`
and `tests/ios/metal-software-checks.v FRESH_EXTERNAL_DIR sizes`, using repository
module paths and the retained toolchain. Dependencies remain referenced; this is
not hermetic. Native JIT is uninstrumented and leak detection is disabled.
CPU software Metal only is qualified; no broad runtime suite, native GPU,
guest launch or new Fortnite frame is verified.
