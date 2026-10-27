# Child attachment regression

`ViewGroup.attachViewToParent` inserts a fresh child through `addViewInternal`,
then falls through into the temporary-detach reattachment branch and inserts it
again. A subsequent `removeView` removes one entry, leaving a child whose parent
is null in the drawable child list. `framework_child_attach.v` adds only an early
return after `addViewInternal`; the detached-child branch is unchanged. This is a
confirmed framework defect; its involvement in Maps onboarding is still unproven.

The golden input is `android/view/ViewGroup.smali` from the sealed broadcast
framework `combined-account-webview-broadcast-result-framework-2026-10-27-r1`:

- Bundle manifest: `21d53cc9cd2ccd9c53fc7774a826d83673f3391d30c1757074e3edcba2c8b046`.
- ViewGroup SHA256: `82d688fa5c04a130a59d1982faf6257a29f0aa80b87ddbd572f7c2eee2e55e88`.
- Focused checker: `tests/native-android-tools/check-child-attach.v` proves the
  return-only delta, unchanged detached branch, unchanged method/field counts,
  five incompatible-input refusals, and successful one-class DEX assembly.

`child-attach-fixture.v` builds a standalone signed APK that checks fresh attach,
repeat attach, removal without an orphan, detached reattachment at a new index,
child identities/order, parent and layout params. It uses package
`org.vinix.bootstrap`, activity `org.vinix.bootstrap.Main`, and prints
`CHILD-ATTACH-PASS fresh-once repeated-once remove-no-orphan detached-reattach-order params-parent`
only after all checks. The same APK can run on the baseline and successor.

Host evidence is retained outside Git at
`/Users/alex/.local/state/vinix/android/child-attach-checks-2026-10-27-r1`.
The sibling `-seal/manifest.json` SHA256 is
`cbf4f343aaf3d7596dfef2dbaa25b23dd082ebbbf67faec83f294793ef4cb9a6`;
its complete 243-entry readback passed. It retains exact source snapshots,
binaries, failed attempts, guard/time receipts, APK, DEX and roundtrip output.
Source baseline revision was `7bfc986b91ebd7b07b3b9a00b9387c674f138be3`;
the source change is the commit containing this report.

The focused checks passed. The signed APK passed separate v1/v2/v3 signature
verification and a byte-identical DEX disassembly/reassembly roundtrip. APK SHA256:
`27869d74fd03598dda9b75b740cbaf2efcc423ee0c5ff3b2f447d22ade9f999e`.
The fixture producer used retained compiler
`/Users/alex/code/v-tccbin-bootstrap-20261026/v`, SHA256
`0cc6c1d34c1811a818e4ae89853116861a4b067d4251af257851a7714f0d11fe`,
with its adjacent VROOT, default GC, `-nocache -cc cc`. It peaked at 351 MB RSS;
APK construction peaked at 121 MB, both with zero swaps. The checker build peaked
at 472 MB with zero swaps. Earlier current-compiler attempts stopped cleanly at
600 MiB/1 GiB aggregate guards; those attempts did not validate the fixture.

These are host construction checks. ARM execution, combined-framework validation,
Maps progression and Google sign-in remain pending.
