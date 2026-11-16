# Zero-count buffer indices — 2026-11-16

Source revision: `c7aff34a912b7cc7b2ec9c70218659be9062ec01`.

Pure address graphs accept scalar llvm.ctlz/llvm.cttz over i1..i64 with a
defined constant i1 zero-poison flag. False returns the width for zero; true
produces poison for zero. Poison propagates through the existing graph and may
be suppressed/repaired by select/freeze; independent GEP roots still reject it.
The validated immediate is cached as node metadata. Declaration identity,
signature, immarg, attribute and duplicate checks remain in force. Other
intrinsic dependencies remain outside this profile.

The existing POD intrinsic node reuses its value field for the immediate. No
owned field or execution allocation is added. Cache/profile lifetime paths,
shared 256-node/32-level limits and fixed stack value/poison arrays remain.
Generated C confirms stack storage. Retained heap is unmeasured.

ASan/UBSan checks pass on macOS ARM64:

- 416,256 cases cover 128 overloads, both flags, six patterns and 271 words:
  343,010 exact outputs and 73,246 prewrite refusals. A defined false-flag LLVM
  oracle supplies counts while separate V checks model zero/literal/computed
  poison and signed bounds. Native true-flag zero calls never execute. Validation,
  ordinary and prepared APIs agree, preserving every byte on refusal. Patterns
  include masked indices, wrap poison, select suppression and frozen zero poison.
  Noisy interpreter padding and exact cached depth boundaries are checked.
- Focused controls cover cold poison versus freeze, independent poisoned GEP
  roots, a dynamic correctly typed i1 flag, three malformed call metadata forms
  and recovery after restoring metadata. All runtime controls exercise all three
  APIs. Cached intrinsic chains pass at 32 levels and reject at 33.
- Twenty-two existing core programs pass, including prior address matrices,
  graph limits, aliases, cold checks and memory/layout/vector/intrinsic checks.
  Unsupported ctlz dependencies become smin guards; all eleven guards remain.
  Complete historical bundles retain their original checkers.
- The image shader adds a self-XOR zero offset derived from leading/trailing
  counts. Trailing count uses true plus freeze, including at index zero. Four
  image sizes pass exact RGBA readback/padding in both hashing modes; each mode
  reports 106 geometry dispatches, eight shader images, 93,962 checked invocations,
  106 rejected pipelines and two prewrite bounds failures.

Evidence: `/Users/alex/Library/Caches/vinix-ios/zero-count-index-20261116-r1`.
Archive: `/Users/alex/Library/Caches/vinix-ios/zero-count-index-20261116-r1.tar.gz`.
Complete inventory and archive logical-byte/metadata comparisons pass. Originals
remain retained; no restoration replay is claimed.

- Archive SHA-256: `6f8136ff3f5eb0d4455403b5178a7b143140b5ce9add8c66bfd3e6b0b3dc3a5c`.
- Inventory SHA-256: `70b37fad4368a200d149d0c04d4c403a3da3d418102da550bb96428a8c73b1ba`.
- Source archive SHA-256: `afe71d03a655192f3cab7d493e9ad190e19124088d7710d77ecd1434956a1d72`.

The bundle preserves original/final comparison runs, rows, IR/bitcode, generated
C, images, binaries, commands/logs, tool identities, ownership review and source
hashes compared with the feature commit. Reproduce with
`tests/ios/air-memory-zero-count-index.v LLVM_AS FRESH_EXTERNAL_DIR` and
`tests/ios/metal-software-checks.v FRESH_EXTERNAL_DIR sizes`, using repository
module paths and retained toolchain. Dependencies remain referenced; this is not
hermetic. Native JIT is uninstrumented and leak detection is disabled. CPU
software Metal only is qualified; no broad runtime suite, native GPU, guest
launch or new Fortnite frame is verified.

Semantics follow the [LLVM language reference](https://llvm.org/docs/LangRef.html).
