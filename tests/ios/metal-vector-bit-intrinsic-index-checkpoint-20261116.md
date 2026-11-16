# Vector bit intrinsics in buffer indices — 2026-11-16

Source revision: `9956bb0e7eb62f4fc0cc209ed887ccac09ca273b`.

Pure buffer addresses now accept canonical vector `llvm.ctpop`,
`llvm.bitreverse` and `llvm.bswap` calls. Population count and bit reversal
support i1..i64; byte swap supports i16/i32/i48/i64. Matching fixed 1..16-lane
source/result types retain the existing direct declaration, signature, call
header, attribute and duplicate-overload checks. Every source lane computes
before extraction. Any undef rejects before writes, including ignored lanes,
invalid selectors, cold blocks and later unchosen selects/result freezes.
Poison stays lane-local. Source freeze repairs indeterminate operands; result
freeze may repair poison, while original extraction bounds remain. Existing
pure integer vector operations compose. Other vector intrinsic families and
loaded/PHI/floating dependencies remain excluded from these address graphs.

Each call materializes a contiguous result table with POD metadata under the
existing source cache tag. One fixed 16-int builder array holds input projection
indices. Maximum heights retain all source/result/selector and cached
dependencies under the existing 256-node/32-level limits. New projected
intrinsic nodes reject undef and reuse scalar bit evaluators without invoking
declarations or external function pointers. Generated C confirms stack arrays
and push records, by-value metadata and existing fixed runtime arrays. No owner,
runtime array or free path is added. Existing noslices graph/cache growth and
normal error allocation remain; heap retention is unmeasured.

ASan/UBSan checks pass on macOS ARM64:

- 298,176 address cases: 181011 exact outputs and 117165 prewrite
  refusals, including 37272 with unrepaired undef. All supported widths use
  count 3; valid widths among 1/8/16/32/64 additionally cover every count 1..16.
  Selector widths 1/32/64, eight operand patterns and four modes cover arguments,
  unfrozen constants, source freeze and result freeze. Masked, high/low-bit-folded
  and unmasked widened addresses exercise exact values and bounds. Validation,
  ordinary and prepared execution agree, preserving every byte on refusal.
  Argument and selector padding is deliberately nonzero.
- 68,000 defined native LLVM intrinsic lane results match independent population
  count, bit reversal and byte-order oracles. Native references replace
  indeterminate inputs with zero; V separately models poison/undef and freezing.
  No native poison or invalid memory operation executes.
- Fifty controls cover exact cached source/selector/result-freeze/nested depths
  32/33 and 256/257 nodes, eager ignored undef, recovery limits, lane-local poison,
  old/frozen consumers, independent roots in both orders, distinct selectors,
  cold dependencies, insertion repair, shuffle/arithmetic/cast/comparison/mask/
  scalar-select composition, cross-family chains and source arithmetic errors.
  Canonical declaration attributes pass; malformed flags/opcode/arity/indices,
  call-site attributes, fast math, callee identity and result types reject.
- Fourteen unit suites pass, including independent unary bit values, exhaustive
  narrow-value sweeps, wide patterns, involutions, lane states, every overload
  identity and name/type/flag guards.
- Earlier complete comparison and per-lane selection matrices pass again:
  1,834,560 and 978,432 address cases, plus 411,360 and 219,392 native/oracle
  comparisons. All 43 earlier core programs and the cast checker's 52-control
  mode pass. Its full matrix was not repeated. Historical bundles and auditors
  remain unchanged.
- Both fresh image modes pass four sizes with exact RGBA/padding readback. A
  one-lane intrinsic chain supplies a separate bounded, unused address root,
  which preflight checks, and mixes its byte into the observable red channel.
  Independent expectations count x bits and reverse the resulting byte. Each
  mode reports 106 geometry dispatches, eight shader images, 93,962 checked
  invocations, 106 rejected pipelines and two prewrite bounds failures.

All fifty controls and the new full matrix passed their first executions.
The initial image fixture appended the chain to an already deep permutation;
the existing projection selector/depth guard rejected it. Its complete failed
host build/run, generated C, IR/bitcode and diagnostic remain. The fixture now
uses a separate bounded address dependency and observable red-channel result;
fresh binaries/processes pass both modes. Graph limits were not changed.
Executable production code stayed unchanged after qualification began; only
the image test changed. Modules are partitioned by width and lane count.

Evidence: `/Users/alex/Library/Caches/vinix-ios/vector-bit-intrinsic-index-20261116-r1`.
Archive: `/Users/alex/Library/Caches/vinix-ios/vector-bit-intrinsic-index-20261116-r1.tar.gz`.
Complete inventory and archive logical-byte/metadata comparisons pass.
Originals remain retained; no restoration replay is claimed.

- Archive SHA-256: `3cbe3cecd92ea77f77b88ceeeebeba9a882e1108a749d540a1b75e349a3b7a7f`.
- Inventory SHA-256: `2caaffacc6714c38e602faef62c0cd9c711528a721eaa9d4eac46a3789646d34`.
- Source archive SHA-256: `de1944498954fcf52e30767f1a8f6de669c57c48f4a8515fed6f43ed29332743`.

The bundle retains rows, IR/bitcode, generated C, images, binaries, commands/logs,
source/tool hashes and ownership review. Source inputs match the feature commit.
Reproduce with `tests/ios/air-memory-vector-bit-intrinsic-index.v LLVM_AS FRESH_EXTERNAL_DIR`
and `tests/ios/metal-software-checks.v FRESH_EXTERNAL_DIR sizes`, using repository
module paths and the retained toolchain. Dependencies remain referenced; this is
not hermetic. Native JIT is uninstrumented and leak detection is disabled.
CPU software Metal only is qualified; no broad runtime suite, native GPU,
guest launch or new Fortnite frame is verified.
