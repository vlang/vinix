# Integer absolute-value buffer indices — 2026-11-16

Source revision: `c4fd098085d78b7448f57f05dd3b6381a4748d5a`.

Pure buffer index graphs accept scalar llvm.abs over i1..i64 with a defined
constant i1 signed-minimum poison flag. False preserves the signed minimum;
true produces poison there. Other negative inputs become positive. Input poison
propagates, and select/freeze retain their existing suppression/zero-choice
behavior. Independent roots still reject poison. Declaration identity, signature,
immarg, attribute and duplicate checks remain shared with ordinary execution.

Abs reuses the existing POD unary intrinsic node and cached immediate field.
The builder uses scalar_integer_poison_flag for zero counts and abs; evaluation
invokes scalar_integer_abs_value for defined words. No owned field or execution
allocation is added. Shared 256-node/32-level limits, fixed stack value/poison
arrays and cache/profile free paths remain. Generated C confirms stack storage.
Retained heap is unmeasured.

ASan/UBSan checks pass on macOS ARM64:

- 208,128 cases cover 64 overloads, both flags, six patterns and 271 words:
  83,421 exact outputs and 124,707 prewrite refusals. A defined false-flag LLVM
  reference supplies values; separate V checks model literal/computed poison,
  flagged signed minima and signed bounds. Native true-flag minimum calls never
  execute. Validation, ordinary and prepared APIs agree and preserve every byte
  on refusal. Cases include masked indices, wrap poison, select and freeze.
  Interpreter padding is noisy; native words are canonical. Every overload/flag
  checks cached depth acceptance at 32 levels and refusal at 33.
- Focused controls verify cold signed-minimum poison versus freeze, independent
  poisoned roots, dynamic i1 flag rejection, three malformed call metadata forms
  and recovery after restoring metadata. Runtime controls exercise all three APIs.
- Twenty-four existing core programs pass, including prior index matrices,
  graph limits, aliases, cold checks and memory/layout/vector/intrinsic tests.
  Unsupported abs dependencies become unsigned saturating-add guards; all eleven
  guards remain. Complete historical bundles retain their original checkers.
- The image shader negates the clamped address and restores it with abs using
  the true flag. Four image sizes pass exact RGBA readback/padding in both hashing
  modes. Each mode reports 106 geometry dispatches, eight shader images, 93,962
  checked invocations, 106 rejected pipelines and two prewrite bounds failures.

Evidence: `/Users/alex/Library/Caches/vinix-ios/abs-index-20261116-r1`.
Archive: `/Users/alex/Library/Caches/vinix-ios/abs-index-20261116-r1.tar.gz`.
Complete inventory and archive logical-byte/metadata comparisons pass. Originals
remain retained; no restoration replay is claimed.

- Archive SHA-256: `a3cd6e07015161660743b7d98eaf8f1fa90fa7762d3fbc503bc46f72847a4103`.
- Inventory SHA-256: `5943934f4d993de09c5d8046bbceea3ba86ffdc283adb2a5eaaffdece3f02d6f`.
- Source archive SHA-256: `36965331c100c0bff0375a447336af3fd45a352a48b5aec904ce99efc2c4cb78`.

The bundle retains rows, IR/bitcode, generated C, images, binaries, commands/logs,
source/tool hashes and ownership review. Source inputs are compared with the
feature commit. Reproduce with `tests/ios/air-memory-abs-index.v LLVM_AS
FRESH_EXTERNAL_DIR` and `tests/ios/metal-software-checks.v FRESH_EXTERNAL_DIR sizes`,
using repository module paths and retained toolchain. Dependencies remain
referenced; this is not hermetic. Native JIT is uninstrumented and leak detection
is disabled. CPU software Metal only is qualified; no broad runtime suite, native
GPU, guest launch or new Fortnite frame is verified.

Semantics follow the [LLVM language reference](https://llvm.org/docs/LangRef.html#llvm-abs-intrinsic).
