# Carry-less multiply and bit-permutation buffer indices — 2026-11-16

Source revision: `4237905f31ccf5e966846c050491cfb9ccd1b0a2`.

Pure buffer index graphs accept scalar llvm.clmul/pext/pdep over i1..i64 with
matching operands. Carry-less multiplication retains the low N polynomial
product bits. Extraction packs selected positions into low bits; deposition
scatters low bits into selected positions. Both dependencies and poison flags
are checked, with existing select/freeze suppression or zero choice. Declaration,
signature, attribute, duplicate and graph-budget checks remain shared.

The existing POD binary intrinsic node is reused. The builder caches one plus
the maximum of both subtree heights. Evaluation checks both poison flags before
calling the shared scalar dispatcher; saturating shifts keep tagged evaluation.
No owned field or per-operation execution allocation is added. Shared 256-node/
32-level bounds, fixed value/poison stack arrays and cache/profile free paths
remain. Generated C confirms stack storage. Heap retention is unmeasured.

ASan/UBSan checks pass on macOS ARM64:

- 302,400 cases cover 192 overloads, seven patterns and 15-by-15 operand pairs:
  188,346 exact outputs and 114,054 prewrite refusals. Native LLVM evaluates
  defined pure intrinsics; V checks model literal/computed poison and signed
  bounds. Validation, ordinary and prepared APIs agree and preserve every byte
  on refusal. Cases cover masks, low-bit truncation, non-power-of-two widths,
  poison in either input, computed right-operand wrap and select/freeze.
  Interpreter padding is noisy; native words are canonical. Cached chains through
  either dependency pass at 32 levels and reject at 33. No native poisoned memory
  operation executes.
- Scalar suites pass 325,972 carry-less multiplication and 651,944 extraction/
  deposition comparisons against independent polynomial-convolution and
  position/rank oracles. Both exhaust i1..i8 operand pairs and cover all widths,
  boundary pairs, identities, round trips and strict evaluator guards.
- Twenty-eight existing core programs pass, including prior address matrices,
  graph limits, aliases, cold checks and memory/layout/vector/intrinsic tests.
  Unsupported carry-less multiplication dependencies become floating saturating-
  conversion guards; all eleven guards remain. Historical complete bundles
  retain original checkers.
- The image shader deposits/extracts its address with an alternating-bit mask
  and multiplies it carry-lessly by one. Four image sizes pass exact RGBA
  readback/padding in both hashing modes. Each mode reports 106 geometry
  dispatches, eight shader images, 93,962 checked invocations, 106 rejected
  pipelines and two prewrite bounds failures.

Evidence: `/Users/alex/Library/Caches/vinix-ios/bit-manipulation-index-20261116-r1`.
Archive: `/Users/alex/Library/Caches/vinix-ios/bit-manipulation-index-20261116-r1.tar.gz`.
Complete inventory and archive logical-byte/metadata comparisons pass. Originals
remain retained; no restoration replay is claimed.

- Archive SHA-256: `38ffa497c743e0798415e124e89912f04286ca3168b60c28c5cf0ce8d1445768`.
- Inventory SHA-256: `114b6af0ba6324c3e40bc71e35c32b6a8e5ef8947459ee92d494fcd658ce0cbe`.
- Source archive SHA-256: `364455492930a4248ac18f75ecaa462ce0260da18e83425244a2e2ea6d70b6ee`.

The bundle retains rows, IR/bitcode, generated C, images, binaries, commands/logs,
source/tool hashes and ownership review. Source inputs are compared with the
feature commit. Reproduce with `tests/ios/air-memory-bit-manipulation-index.v
LLVM_AS FRESH_EXTERNAL_DIR` and `tests/ios/metal-software-checks.v
FRESH_EXTERNAL_DIR sizes`, using repository module paths and retained toolchain.
Dependencies remain referenced; this is not hermetic. Native JIT is
uninstrumented and leak detection is disabled. CPU software Metal only is
qualified; no broad runtime suite, native GPU, guest launch or new Fortnite frame
is verified.

Semantics follow the [LLVM language reference](https://llvm.org/docs/LangRef.html).
