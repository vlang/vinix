# Software Metal saturating conversions — 2026-11-14

`cc42210b2562a73aa9f631e98b2e1843d7fcae8b` adds scalar
`llvm.fptosi.sat`/`llvm.fptoui.sat` for half/float to signed/unsigned i1..i64.
Calls truncate toward zero and clamp to destination limits; NaNs become zero,
infinities clamp and unsigned negative inputs become zero. Signed i1 has range
-1..0. This follows the [LLVM saturation semantics](https://llvm.org/docs/LangRef.html#saturating-floating-point-to-integer-conversions).
Poison inputs propagate, selected undef errors, and existing freeze/select
and poison-store rules apply. Calls retain one-step cost and share scalar,
void and memory execution validation/evaluation.

The evaluator uses bounded unsigned arithmetic and the existing integer-only
conversion helpers. Half widening is exact for finite values; NaN payload
canonicalization cannot affect a zero result. Strict overload spelling and
signature checks reject unsupported widths/formats and vector/aggregate forms.
The 256 signedness/source/result-width cache identities follow the existing
floating/integer identities without changing them. Fixed local caches grow;
no owned runtime array, cached-profile field or persistent allocation is added.
Existing direct-call and declaration-attribute restrictions remain in force.

ASan/UBSan checks pass:

- 8,912,896 independent rational checks: every half encoding for both
  signednesses and all i1..i64 destinations, plus float sign/exponent/fraction
  boundaries. All 256 names/cache keys and malformed-name/width guards pass.
- 1,663,040 defined native LLVM comparisons covering all 256 overloads,
  exhaustive half inputs at destination widths 1/8/16/32/64, boundary/sample
  inputs and mixed old/new intrinsic families in one cache lifetime.
- 1,048,576 scalar comparisons with high incoming argument bits, integer API
  isolation, 1,030 poison/undef/freeze/select/return/void controls, 256 short
  budgets and 22 call/type/name metadata controls, including after a cached
  call. Preflight failures precede marker stores; dynamic failures retain them.
- 8,192 interpreter checks across four host rounding modes preserve result
  bits and leave cleared host exception flags clear.
- Regressions: 210,112 ordinary conversion, 1,613,824 classification and
  66,963 defined flagged-cast native comparisons, plus 191,085 flagged-cast
  poison-store failures and their scalar/metadata/budget/choice controls.
  Sixteen integer/scalar execution, four scalar-intrinsic and one integer
  intrinsic groups pass, including 1,397,052 arithmetic-flag comparisons,
  327,680 square-root inequalities and 733,180 bit-operation comparisons.

LLVM verifies the complete new fixture module. Native calls use defined
saturation inputs, including NaNs/infinities; poison/undef and their freeze
choices are never native value oracles. The retained `native-input.bc` records
the host target and cleared layout used by MCJIT. Byte GEPs and align-1 accesses
agree with the explicit VM layout.

All 24 software Metal groups pass in both Swift hash modes. A synthetic AIR
kernel mixes the four signed/unsigned half/float conversions. Six deferred
dispatches check changed inputs, both infinities, signaling NaNs, positive and
negative fractions, and frozen poison. Both drained runtimes pass.

Complete archive:

`/Users/alex/Library/Caches/vinix-ios/air-saturating-cast-validation-20261114-r1.tar.zst`

The bundle retains binaries, fixtures/results, build receipts, compiler
snapshots, generated host C, LLVM headers, selected identities and `source.tar`
pinned to the feature revision. Preliminary admission/layout and helper-build
failures remain recorded. Final qualification uses `saturation-qualified-final`
and its matching results; the host is
`software/NotificationChecks.app/Contents/MacOS/center-host`.
Decode with `zstd -dc ARCHIVE | tar -xf - -C FRESH_DIRECTORY`.

A completed fresh extraction replaced the bundle path. The unchanged maintained
`tests/packages/wine-workspace-archive.v` checker matches complete bytes, sizes,
types, modes and link targets, including the root; selected identities match.
All ten restored runs exit 0: four references, four unit binaries and both
24-group host modes, with separate output roots. Full inventory, selected
identities and archive checksum match after replay. A fresh replay-archive
extraction also matches its complete inventory. Original expanded trees remain.

Standalone compiler capture followed builds; the harness captured its separate
toolchain before generation. SDKs, assembler, external library symlinks and
dylibs remain unsealed prerequisites. Native MCJIT code is not sanitizer
instrumented. Leak detection is disabled; retained heap was not measured.
The ordinary runner was not rebuilt. This remains single-thread CPU execution
of synthetic LLVM fixtures. No Apple-produced shader, GPU rendering,
presentation, Vinix guest, Fortnite frame or launch gate is newly verified.
Integrity checks do not replace historical launch auditors.

| Artifact | SHA-256 |
| --- | --- |
| Complete `.tar.zst` | `74e995b5316ab34776a51c2655f536222dc168f7728ced080ef3b5d0bfed8800` |
| `.inventory.json` | `b67f785996b0a6e2612f2574a8617be66ca5b35de9c324f5cce3a7b4cb10a540` |
| `.replay.tar.zst` | `388d047b0aabf7355513946570b66642c42822ba2f0f2d31897419b89d949b4b` |
| `.replay-inventory.json` | `1cf1788a5dcb2399e7543827b24d2a3c196ca3b857151ed9f2299dec301c264f` |
| `source.tar`, revision `cc42210b2` | `2c69fbd47bd0c38403fc358f86da163f537b23045925fe2effc5e34197b3a5f2` |
