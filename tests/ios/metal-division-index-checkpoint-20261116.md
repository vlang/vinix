# Division buffer indices checkpoint — 2026-11-16

Source revision: `c070322c39392582914c5302e98108e63258ee7e`.

Pure buffer index expressions accept signed/unsigned division and remainder on
i1..i64, plus exact division. Zero divisors and signed minimum / or % -1 reject
as undefined arithmetic; inexact results under exact division reject as poison.
All required nodes resolve before writes, even in cold/unused index expressions.
Unrelated non-address arithmetic retains its ordinary dynamic error behavior.
Negative final indices and invalid addresses still reject. Graph limits remain
256 shared nodes and 32 levels. Loads, PHIs, select/freeze, comparisons and
pointer-to-integer dependencies remain outside the address profile.

Only the binary-op admission predicate changes. Node/cache ownership, fixed
stack evaluation storage and cleanup are unchanged. Normal evaluation adds no
owned storage; errors reuse existing reporting. Retained heap is unmeasured.

ASan/UBSan checks pass on macOS ARM64:

- 86,400 cases across i1..i64, four operators and six forms: 50,448 native exact
  outputs and 35,952 prewrite refusals. Defined LLVM oracle tags distinguish
  18,249 exactness-poison cases and 7,185 undefined-arithmetic cases from bounds
  refusals. Validation alone, prepared and ordinary execution agree and preserve
  full output on rejection. Interpreter words have noisy upper padding; native
  words are canonical. The oracle divides widened i128 operands using a selected
  nonzero divisor, separately detecting original-width signed overflow. It never
  executes an undefined division. Native memory targets run only after acceptance.
- Existing add/sub/mul and bitwise index matrices pass, along with fifteen
  other memory/layout/structured-GEP/switch/vector/intrinsic programs (17 core
  regression programs in total). Graph-limit and cold-bounds controls remain.
  A new cold-divisor control verifies refusal in an unvisited block; the alias
  control uses exact division to verify immutable captured arguments. Unsupported
  division/remainder controls become comparison and pointer-integer controls;
  historical bundles retain the original source.
- The image kernel decomposes linear addresses using remainder and exact
  division, then reconstructs them with shifts/disjoint OR. Exact texture
  readback and padding checks pass in both hashing modes. Fresh processes of
  that executable pass all focused builtin/grid/multidimensional/computed-index/
  size/image/group-coordinate/indirect/geometry-type/vector/prepared-reuse modes.

Evidence: `/Users/alex/Library/Caches/vinix-ios/division-index-20261116-r1`.
Archive: `/Users/alex/Library/Caches/vinix-ios/division-index-20261116-r1.tar.gz`.
Complete inventory and archive byte/metadata comparison pass. Originals remain
retained; no restoration replay is claimed.

- Archive SHA-256: `0d051f570bad294ab8fba8ac72c073a0ca30627fa5f82b18c0f8706d16f1f59c`.
- Inventory SHA-256: `d99e89827f7b7e3683e75962f33bc1b15b10d219fd58cbb9eb0f7e5fb71e571c`.
- Source archive SHA-256: `67a35d332067aefcf32ab08a3b0ea2bb84fe5d33f3d57a4655ed0c6046ceb6c9`.

The bundle retains comparison rows, IR/bitcode, generated C, images, binaries,
commands/logs, tool identities, ownership review and source hashes compared with
the feature commit. Reproduce with `tests/ios/air-memory-division-index.v LLVM_AS
FRESH_EXTERNAL_DIR` and `tests/ios/metal-software-checks.v FRESH_EXTERNAL_DIR sizes`,
using repository module paths and the retained toolchain. Dependencies remain
referenced; this is not hermetic. LLVM JIT code is uninstrumented and leak
detection is disabled. No full broad runtime suite, native GPU, guest launch or
new Fortnite frame is verified.

The [LLVM language reference](https://llvm.org/docs/LangRef.html) defines division, remainder, undefined arithmetic and exactness semantics.
