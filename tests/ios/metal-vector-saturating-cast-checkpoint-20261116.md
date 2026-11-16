# Saturating vector float-to-integer conversion — 2026-11-16

Source revision: `9e6044a15f2df8886ac8e1051a311e9231f7a558`.

Software Metal shader execution now accepts direct `llvm.fptosi.sat` and
`llvm.fptoui.sat` vector calls from half/float to matching 1..16-lane i1..i64
results. They truncate toward zero and clamp to destination limits; all NaNs
become zero, infinities clamp and negative unsigned inputs become zero.
Numeric inputs introduce no poison. Source poison remains lane-local and any
undef source lane rejects the whole executed call. Source/result freezes,
independent snapshots and write ordering retain their existing rules. Integer-only
execution and pure address graphs continue to reject these floating sources.
Other formats, scalable vectors, mismatched counts, malformed overloads,
fast-math/tail calls and call-site attributes remain excluded.

Canonical two-width names add 4,096 distinct declaration identities after all
18,112 previous identities. All 22,208 cache slots are covered without collisions.
Generated checker C confirms both existing per-profile caches are fixed
i64[22208] arrays: each grows by 32 KiB on this host. Value execution uses fixed
by-value vector records and the existing integer-based scalar saturation helper.
Generated host C confirms the helper call and no new arrays or f32/f64 arithmetic
in the vector wrapper. No managed storage, owner, node kind, escaping pointer,
lifetime extension or free path is added. Existing construction slots, step/work
budgets and address graph limits remain. Existing profile/execution/cache and
ordinary error allocations remain; heap retention is unmeasured.

Final ASan/UBSan checks pass on macOS ARM64:

- 556 shapes cover every integer width with count 3, plus all counts 1..16 at
  widths 1/8/16/32/64, both floating formats and both signs. Eight patterns,
  four modes and selector widths 1/32/64 produce 489,216 cases: 319,892
  exact/frozen outputs, 108,172 poison-store failures and 61,152 strict undef
  failures. Scalar insertion, constants, source/result freezes, noisy padding,
  invalid selectors and ignored indeterminate lanes are included. Validation
  preserves all bytes; ordinary/prepared execution agrees on exact results and
  preserves preceding marker writes on execution errors. Scalar values and
  integer-only API rejection add 978,432 checks.
- 109,696 defined native LLVM vector lanes match an independent rational
  significand/scale oracle. Another 655,360 exhaustive half-input cases cover
  every encoding at signed/unsigned i1/8/16/32/64, using 16-lane calls and
  checking the inserted lane through native LLVM, the oracle, scalar execution
  and both memory APIs. Total execution cases: 1,144,576; total native/oracle
  comparisons: 765,056. Native references use a pointer-only ABI and defined
  replacements for poison/undef; native poison and invalid memory never run.
- Unit tests check 8,912,896 independent vector values: every half encoding and
  float sign/exponent/fraction patterns at every i1..i64 destination width.
  Another 417,792 poison/undef lane states check freezes and guards. Scalar
  saturation, complete intrinsic cache identities, nonsaturating conversion,
  sign operations and funnels also pass, for six unit suites.
- 54 controls cover nonfinite values, fractional truncation, poison isolation,
  eager undef, freezes, discarded/old results, an unexecuted undef block,
  comparison/select/shuffle composition, all four source-format/sign overloads
  in one function, loop reuse, malformed calls/sources, duplicate canonical
  declaration identity and floating-address rejection. Eight memory/void
  storage/work limits pass: 4,096 results are accepted and 4,097 rejected;
  4,096 32-lane-work calls plus 54,308 16-lane extractions consume exactly
  1,000,000 work units, and the next extraction rejects before writes.
- Computed-index and prepared-memory programs pass. The full earlier vector
  sign-intrinsic checker repeats 266,516 exact LLVM values, 557,744 scalar/
  integer checks, 200 controls, 16 declaration attribute guards and eight
  shared limits. The full nonsaturating float-to-integer checker repeats
  511,264 defined LLVM values, 204,616 poison-store failures, 1,432,784 scalar/
  integer checks, 546 controls and eight shared limits. Earlier bit/funnel/
  saturation address control modes pass 50/125/98 controls, retaining their
  unsupported floating-conversion fixtures. Other full address matrices, the
  broader 43-program regression, broad runtime and kernel/guest builds were
  not repeated.
- Both image modes retain seven earlier kernels and add a saturation kernel.
  Float signed-i8 and half unsigned-i8 conversions combine fractional values,
  both clamps, NaN and both infinities in the red channel. Independent integer
  arithmetic checks exact RGBA and full backing padding at four sizes in fresh
  binaries/processes. Each mode reports 106 geometry dispatches, 64 images,
  156,094 checked invocations, 106 rejected pipelines and two prewrite bounds
  failures. Both runtimes drain completely. Addresses remain integer-only.

An initial checker build needed standalone mask/borrowed-array fixes. Shared
disk exhaustion then interrupted evidence writes in the first matrix and two
regressions. Their partial outputs remain retained and unqualified. The same
sanitized binaries passed complete reruns in fresh directories; `retry.v` saves
commands before execution. Final receipts are required by the finish checker.
Production executable source remained unchanged during qualification. Full
attempt details are in `attempts.txt`; no originals or historical checks were
removed or weakened.

Evidence: `/Users/alex/Library/Caches/vinix-ios/vector-saturating-cast-20261116-r1`.
Archive: `/Users/alex/Library/Caches/vinix-ios/vector-saturating-cast-20261116-r1.tar.gz`.
Complete inventory and archive logical-byte/metadata comparisons pass. Originals
remain retained; no restoration replay is claimed.

- Archive SHA-256: `51aeb17cd5da6dd0c6c36b1e3d12cd9e9fe08fa9245ab5ce5a6567b643f61309`.
- Inventory SHA-256: `2495b52a4e8f80305af4b29c839a65bf9acef778077f9edf4977ceee5cda9a78`.
- Source archive SHA-256: `3d0e04e51650efcb3026b983d6d99704aab59b0829dcb79406cf5eb2e3676962`.

The bundle retains rows, IR/bitcode, generated C, images, binaries, commands/logs,
source/tool hashes and ownership review. Source inputs match the feature commit.
Reproduce with `tests/ios/air-vector-saturating-cast.v LLVM_AS FRESH_EXTERNAL_DIR`
and `tests/ios/metal-software-checks.v FRESH_EXTERNAL_DIR sizes`, using repository
module paths and retained tools. Dependencies remain referenced; this is not
hermetic. Native JIT is uninstrumented and leak detection is disabled. CPU
software Metal only is qualified; no native GPU, guest launch or new Fortnite
frame is verified.
