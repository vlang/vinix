# Unary bit intrinsic buffer indices — 2026-11-16

Source revision: `f7cf6c7dabc42ece6ebce292caebb8e83ec1325f`.

Pure buffer index graphs accept scalar llvm.ctpop/llvm.bitreverse over i1..i64
and llvm.bswap over i16/i32/i48/i64. Nodes reuse scalar evaluators and propagate
poison, composing with existing select/freeze. Earlier producers retain the
memory profile's direct declaration, signature, attribute, duplicate and shared
attribute-work checks; the builder rechecks call identity without repeating
attribute scans. Other intrinsic dependencies remain unsupported.

A POD intrinsic enum is added to nodes; the transient builder borrows IRModule.
No module ownership moves into the prepared profile. Existing cache/profile free
paths, shared 256-node/32-level bounds and fixed value/poison stack arrays remain.
Generated C confirms stack storage. No per-execution owned allocation is added.
Retained heap is unmeasured.

ASan/UBSan checks pass on macOS ARM64:

- 214,632 cases cover 132 overloads, six patterns and 271 boundary/pseudorandom
  words per pattern: 142,247 exact outputs and 72,385 prewrite refusals. A pure
  native LLVM reference evaluates defined intrinsic inputs; separate V checks
  model bounds and literal/computed poison. Validation, ordinary and prepared
  APIs agree and preserve every byte on refusal. Poison freeze uses the existing
  zero policy; an unchosen poisoned intrinsic is suppressed by select. Interpreter
  words contain noisy padding. Every overload checks cached depth acceptance at
  32 levels and refusal at 33. No native poisoned memory operation executes.
- Twenty-one existing core programs pass, including arithmetic, bitwise,
  division, comparison, select and freeze index matrices, graph limits, aliases,
  cold checks and memory/layout/vector/intrinsic tests. Unsupported ctpop guards
  become ctlz guards; the eleven guard cases remain. Historical bundles retain
  their original sources.
- Two bitreverse calls preserve the image shader's address. Four image sizes
  pass exact RGBA readback/padding in both hashing modes: each mode reports
  106 geometry dispatches, eight shader images, 93,962 checked invocations,
  106 rejected pipelines and two prewrite bounds failures.

Evidence: `/Users/alex/Library/Caches/vinix-ios/bit-intrinsic-index-20261116-r1`.
Archive: `/Users/alex/Library/Caches/vinix-ios/bit-intrinsic-index-20261116-r1.tar.gz`.
Complete inventory and archive logical-byte/metadata comparisons pass; originals
remain retained. No restoration replay is claimed.

- Archive SHA-256: `7ba37371650d82545e58d512d155645d7d7985d1653533bf43807065d99153ce`.
- Inventory SHA-256: `e10b93f870134b6e1b9b138f4720c101c244c308ff020a2046667fe42669c9d1`.
- Source archive SHA-256: `0b77c92200904ece374a44dfa52e948b3e28da8f9c07925c133e58e1d197dbc2`.

The bundle retains complete rows, IR/bitcode, generated C, images, binaries,
commands/logs, ownership review and source/tool hashes. Source inputs are compared
with the feature commit. Reproduce with
`tests/ios/air-memory-bit-intrinsic-index.v LLVM_AS FRESH_EXTERNAL_DIR` and
`tests/ios/metal-software-checks.v FRESH_EXTERNAL_DIR sizes`, using repository
module paths and the retained toolchain. Dependencies remain referenced; this
is not hermetic. LLVM JIT is uninstrumented and leak detection is disabled.
CPU software Metal only is qualified; no broad runtime suite, native GPU,
guest launch or new Fortnite frame is verified.

Operation semantics follow the [LLVM language reference](https://llvm.org/docs/LangRef.html).
