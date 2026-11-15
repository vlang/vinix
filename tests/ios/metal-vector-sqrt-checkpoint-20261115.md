# Software Metal vector square root — 2026-11-15

`373cd1b3ccfcf5dc6259713b9a3c43a1569ce115` adds direct unflagged `llvm.sqrt.vNf16` and `llvm.sqrt.vNf32`
calls for fixed 1..16-lane AIR vectors. Defined lanes use the existing integer
square-root evaluator and nearest, ties-to-even packing. Zero retains its sign;
positive infinity remains infinity. Negative nonzero inputs and NaNs produce
the preferred positive quiet NaN. Source bits are masked to the declared width
before evaluation, including the zero and infinity fast paths. Host floating
arithmetic and the host rounding mode do not determine VM results.

Poison stays local to each lane. Any undef source lane rejects at the executed
call, including discarded results. Source freezes repair indeterminate lanes;
result freezes do not suppress earlier undef errors. Dynamic errors preserve
prior stores. Independent result snapshots compose with fneg, rounding,
bitcasts, comparisons, selects, shuffles and extraction.

The shared canonical overload parser replaces duplicated sign/rounding suffix
parsers. Direct declaration identity, exact signature, arity, source order,
calling convention, call flags and declaration attributes retain the existing
checks. The vector declaration cache has 320 entries; all previous 288 keys
are unchanged and 32 square-root keys follow them. Duplicate reserved
declarations reject. Each sqrt call costs two lane counts, one executed step
and one of the existing 4,096 vector result slots. Shared lane work remains
bounded at 1,000,000.

Mixed scalar, void and memory APIs admit the calls; the integer-only API
rejects floating lanes even for constant vectors with integer results. Vector
arguments/returns, PHIs and loads/stores, scalable or wider vectors, double or
bfloat, fast-math flags, tail calls, call-site attributes, strict FP and FP
exceptions remain outside the admitted profile.

ASan/UBSan qualification passes:

- 1,048,576 independent binary16 checks cover every encoding and all 16 lanes.
  Finite positive results satisfy exact squared-midpoint inequalities with
  ties to even; the integer oracle does not call the production root or packing
  routines. Zeros, infinity, preferred NaNs, upper-bit masking and immutable
  sources are checked separately. Sixteen float edge patterns and 3,264
  poison/undef/freeze checks cover both formats and every count. All 32 new
  cache identities and malformed name/shape/tag guards pass.
- 800 decoded shapes cover both formats, every count 1..16, five source forms
  and five constructions. All 133,258 native LLVM comparisons pass, including
  131,072 exhaustive half/deterministic float sweep samples. Finite results
  and signed zeros compare bitwise; arithmetic NaNs compare by class while
  the VM must produce its preferred quiet NaN. A host-double oracle also
  checks VM results. Defined comparisons and the native projection remain.
- There are 1,256 explicit frozen choices, 3,040 poison-store failures,
  1,882 strict undef failures, 278,872 scalar/integer API checks, 16,000
  malformed-call/source refusals and 1,600 short-budget refusals. Output and
  guard bytes use unaligned bindings and derived bounds. Another 100 controls
  cover discards, freezes, isolation, old snapshots, composition, loop slot
  reuse, declaration mutations, duplicate identities and six host-rounding
  mode checks. Sixteen retained declaration-attribute mutations reject before
  writes. Eight public memory/void boundaries check exact shared storage and
  lane-work admission and refusal before earlier stores.
- Six unit and three reference regressions pass for sign/rounding intrinsics,
  scalar execution, memory operands, vector bitcasts and float-to-integer
  conversions. The complete sign and rounding comparisons run again. Their
  unsupported-intrinsic guards now target `sin`, since `sqrt` is admitted;
  the rounding cache unit covers all 320 identities. Original historical
  checkers and evidence remain in their pinned bundles.
- Both Swift hash modes pass all 24 software Metal groups with two drained
  runtimes each. Each runtime exercises 60 new dispatches across 14 kernels:
  56 complete and four fail as expected. Cases cover squares and neighboring
  inputs, irrational roots, subnormals, signed zeros, infinities, negative
  inputs, NaNs, deferred input writes, sparse bindings, pipeline reuse,
  poison/undef, source/result freezes, snapshots and composition. Strict
  undef failures preserve the marker; poison failures also preserve a
  frozen-zero store. A fast-math sqrt call rejects at pipeline creation.

Exact new unit/reference sources were saved before their first builds; all new
attempts pass. LLVM verifies the input modules. The native projection retains
comparison kernels and intrinsic declarations and uses the host target.
Indeterminate freeze choices are checked separately from native execution.

Complete archive:

`/Users/alex/Library/Caches/vinix-ios/air-vector-sqrt-validation-20261115-r1.tar.gz`

The expanded workspace at the same path without `.tar.gz` remains. It retains
results, fixtures, binaries, generated host C and objects, compiler captures,
commands, helpers and feature-pinned `bundle/source.tar`. Maintained V tools
compare every logical archive payload, path, type, size, byte, mode, symlink
target and root mode with the original. Complete before/after inventories and
archive/tool hashes agree. No restored replay was performed. Audit receipts
are beside the archive under `.tar.gz.audit`; the typed inventory is
`.tar.gz.inventory.txt`.

| Artifact | SHA-256 |
| --- | --- |
| `.tar.gz` | `264e81ab51694b058f6c7d0b465799af09ab1e17fd21bc406247771b76a8f16f` |
| `.tar.gz.inventory.txt` | `ff907b614088181cbc00cf7f0820f9e9420848f819bf05edb01493f652fa17dc` |
| `bundle/source.tar`, revision `373cd1b3ccfcf5dc6259713b9a3c43a1569ce115` | `47aeeccb20f56e514ccb25e7a13b31f754586775c9a5335847b51ee42adf6be5` |

The standalone compiler was captured after builds; the host compiler before
generation. V libraries, SDKs, assembler, symlink targets and dylibs remain
external prerequisites. Native JIT code is uninstrumented. Leak detection is
disabled and retained heap was not measured. The ordinary runner was not
rebuilt. These are synthetic CPU fixtures: no Apple shader, GPU rendering or
presentation, Vinix guest, Fortnite frame or launch gate is newly verified.
Archive integrity does not replace historical launch auditors.
