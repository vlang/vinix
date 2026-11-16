# Dynamic vector lanes in buffer indices — 2026-11-16

Source revision: `11eb5cf15f7468a070e32d24b6125b8976da5af6`.

Pure address expressions now extract from direct fixed integer vector arguments
using supported integer expressions as lane selectors. Lane words use unsigned
i1..i64 masking; poison or out-of-range selection produces poison before reading
a lane. Scalar select/freeze can recover it. Final GEP indices keep their signed
bounds rules. Direct undef selectors require freeze first; loads, PHIs and
constructed/loaded/constant vector sources remain excluded from address graphs.

A POD dynamic-lane node reuses existing fields for selector and lane count.
It adds one extraction level to the complete selector dependency height. Defined
in-range literal lanes retain their single-leaf cost; literal poison/out-of-range
selectors now use the repairable poison path. Shared 256-node/32-level caps,
fixed stack value/poison arrays and existing graph/cache ownership remain.
Generated C confirms the unsigned guard precedes narrowing and lane access.
No new execution allocation is introduced; heap retention is unmeasured.

ASan/UBSan checks pass on macOS ARM64:

- 3,391,488 cases: 1,854,931 exact outputs and 1,536,557 prewrite refusals,
  covering all 64 integer lane widths, selector widths 1/2/8/16/32/64, vector
  lengths 1/2/3/16, twelve patterns, both conditions and four lane data sets.
  Patterns cover direct, modular add/XOR, selected and frozen selectors, literal
  poison/out-of-range/zero selectors, scalar extraction recovery, direct/masked/
  widened addresses and nuw overflow recovery. Argument padding is noisy. Defined
  LLVM extracts provide the lane oracle; V models poison and bounds separately.
  No native invalid extraction or poisoned memory operation executes. Validation,
  ordinary and prepared execution agree, preserving every byte on refusal.
- 22 controls cover exact cached depths 32/33 and node counts 256/257,
  independent poison roots in both cache orders, cold repaired/unrepaired roots,
  nested selection, binding lengths, direct undef and unsupported dependencies,
  plus divide-by-zero hidden in an unselected selector dependency.
- Vector unit suites pass 1,351,680 extraction checks and 65,280 insertion
  state checks, plus shape/type/encoding guards. All 36 existing core programs
  pass, including all previous pure-index and overflow-pair address matrices.
- The final image shader selects x/y/z using x modulo three and exposes the
  chosen coordinate in red-channel readback. Four image sizes pass exact RGBA
  readback and padding checks in both hashing modes. Each mode reports 106
  geometry dispatches, eight shader images, 93,962 checked invocations, 106
  rejected pipelines and two prewrite bounds failures. Final image evidence is
  in software-variable-lane; software-bits retains the earlier zero-selector
  fixture check. Both use fresh processes and freshly compiled source.

Evidence: `/Users/alex/Library/Caches/vinix-ios/dynamic-lane-index-20261116-r1`.
Archive: `/Users/alex/Library/Caches/vinix-ios/dynamic-lane-index-20261116-r1.tar.gz`.
Complete inventory and archive logical-byte/metadata comparisons pass. Originals
remain retained; no restoration replay is claimed.

- Archive SHA-256: `09fd50c1ba11521bcc5d0d7b82080d3ad0de912b1d1219e411d031ff82955044`.
- Inventory SHA-256: `39c1d39c3daade12e64f2b054935b602ca0cd5c42882ae51b5c317cef08e46b5`.
- Source archive SHA-256: `3a778e1ca6d6f6602586cad4831fb8067e766e25d382fe5d186892cee76b3041`.

The bundle retains rows, IR/bitcode, generated C, images, binaries, commands/logs,
source/tool hashes and ownership review. Source inputs are compared with the
feature commit. Reproduce with `tests/ios/air-memory-dynamic-lane-index.v LLVM_AS
FRESH_EXTERNAL_DIR` and `tests/ios/metal-software-checks.v FRESH_EXTERNAL_DIR sizes`,
using repository module paths and the retained toolchain. Dependencies remain
referenced; this is not hermetic. Native JIT is uninstrumented and leak detection
is disabled. CPU software Metal only is qualified; no broad runtime suite, native
GPU, guest launch or new Fortnite frame is verified.
