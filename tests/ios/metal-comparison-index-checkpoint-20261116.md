# Comparison buffer indices checkpoint — 2026-11-16

Source revision: `329507452bdc5727855d03068a9c104c1da5e4c0`.

Pure address expressions accept all ten scalar integer icmp predicates over
i1..i64, including samesign. Comparisons retain separate operand and i1 result
widths; the result can feed existing integer casts/arithmetic. A direct i1 true
GEP index is negative and rejects, while zero-extension gives positive 0/1.
Samesign with different operand signs produces poison and rejects before writes,
including in cold/unused index expressions. Floating, pointer and vector
comparisons, loads, PHIs, select/freeze and pointer-integer dependencies remain
outside the address profile.

A POD compare node reuses source_bits, opcode, flags and two child fields. The
builder validates source type/predicate/flags and records full subtree height.
Evaluation reuses the existing scalar comparison helper. Fixed stack storage,
256 shared nodes/32 levels, transient cache and profile ownership/free paths
remain unchanged. No new per-node owned storage or resource lifetime is added.
Retained heap is unmeasured.

ASan/UBSan checks pass on macOS ARM64:

- 576,000 LLVM reference cases cover i1..i64 source widths, all ten predicates,
  flagged/unflagged forms, direct-i1 indices and zero-extended i64 indices. There
  are 359,880 native exact outputs and 216,120 prewrite refusals, including
  96,160 samesign-poison cases. Validation alone, prepared and ordinary execution
  agree and preserve full output on refusal. Noisy interpreter padding is tested
  separately from canonical native words. The oracle uses unflagged comparisons
  and a defined sign-bit test; native targets run only for accepted addresses.
- Eighteen existing core programs pass, including add/sub/mul, bitwise and
  division index matrices, graph depth/node boundaries, casts, aliases, cold
  bounds/division and memory/layout/vector/intrinsic checks. A new cold comparison
  checks poison refusal in an unvisited block. Unsupported comparison controls
  now cover floating, pointer and vector forms; the unsupported/depth/node guard
  count increases from nine to eleven. Historical bundles keep original sources.
- The image kernel gates its final address with a zero-extended samesign
  comparison of x against grid width. Exact texture readback and padding checks
  pass in both hashing modes. Fresh processes of that executable pass all focused
  builtin/grid/multidimensional/computed-index/size/image/group-coordinate/
  indirect/geometry-type/vector/prepared-reuse modes.

Evidence: `/Users/alex/Library/Caches/vinix-ios/comparison-index-20261116-r1`.
Archive: `/Users/alex/Library/Caches/vinix-ios/comparison-index-20261116-r1.tar.gz`.
Complete inventory and archive byte/metadata comparison pass. Originals remain
retained; no restoration replay is claimed.

- Archive SHA-256: `92f5c328194c2ab24b7a1dd3b95b2c647f933c516d8e640ef7a119a26a9906c4`.
- Inventory SHA-256: `c4153bf7a9afbc8d5e85ada032680108c3ae329563742cd0ff19d092ed557e93`.
- Source archive SHA-256: `7f2d5bd89041ea874d07ddb89b2875c56912635242faa54005dee7269e6de7ca`.

The bundle preserves comparison rows, IR/bitcode, generated C, images, binaries,
commands/logs, tool identities, ownership review and source hashes compared with
the feature commit. Reproduce with `tests/ios/air-memory-compare-index.v LLVM_AS
FRESH_EXTERNAL_DIR` and `tests/ios/metal-software-checks.v FRESH_EXTERNAL_DIR sizes`,
using repository module paths and the retained toolchain. Dependencies remain
referenced; this is not hermetic. LLVM JIT code is uninstrumented and leak
detection is disabled. No full broad runtime suite, native GPU, guest launch or
new Fortnite frame is verified.

The [LLVM language reference](https://llvm.org/docs/LangRef.html) defines integer comparisons and samesign poison.
