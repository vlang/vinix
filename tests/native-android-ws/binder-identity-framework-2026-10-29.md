# Binder identity framework profile, 2026-10-29

The explicit `--binder-identity` profile targets the sealed authenticator-exception
framework at 2,104 classes. It permits exactly two changed public Binder identity
methods, two added private original-body fallbacks, and two native methods added
to `VinixAccountBrokerContext`. Every other class, method and field is preserved.

The allowed Binder helpers are `vinixOriginalClearCallingIdentity()J` and
`vinixOriginalRestoreCallingIdentity(J)V`. Additional checks require each private
static helper to retain the complete original method body and preserve the public
identity ABIs. Context additions must be exactly public static native
`clearCallingIdentity()J` and `restoreCallingIdentity(J)Z`. These checks run before
and after DEX roundtrip. Negative controls cover unrelated class/method changes,
wrong counts, access/body changes and nonnative or incorrect native declarations.
Historical narrow profiles retain their original contracts.

The pinned baseline is
`/Users/alex/.local/state/vinix/android/combined-account-webview-auth-exception-framework-2026-10-29-r1`,
manifest `4aa0c09e05c0d4fe3180a909648ebb344881ec1d2d6e60bba5d959148d93a284`,
JAR `0daae54d7755b255ed3335f58d8cafd6da4d03c8c95343ebb0f174d166da6916`.
The single provider is `framework_account_broker_context.v`; its explicit Binder
and append-only context transformers select this follow-up delta.

Standalone builder compilation, the full selftest and full framework producer
passed. Exact class/method/body/ABI deltas, DEX roundtrip, JAR-member delta, complete
input rechecks and output inventory verification all passed. Native coupling and
ART/login validation remain pending. Independent static review found no blocking
issue with the profile, negative controls or pinned baseline formatting.

Host artifacts are retained at
`/Users/alex/.local/state/vinix/android/binder-identity-framework-builder-2026-10-29-r1`
(`B`), including the exact source, compiler, builder and original guarded command
receipts/logs. SHA-256 identities:

- Builder source: `c3ca5f175ade548f4d309517f443e13561f0cdd895da2beea3204eaf8fb9b700`.
- Compiler: `0cc6c1d34c1811a818e4ae89853116861a4b067d4251af257851a7714f0d11fe`.
- `B/tools/builder`: `b17354964eed7cb5b7ad1fc1c81d5f99fba9e2a031a6e06bcd0cc1dde90db70f`.

The completed framework (`P`) is retained at
`/Users/alex/.local/state/vinix/android/combined-account-webview-binder-identity-framework-2026-10-29-r1`.
Its producer recorded revision `691c81bbecd9900d259c465b6ce92010574467f3`, with the
exact working builder above and broker provider SHA-256
`8a2baf5fbfbeffa873a9ee47abf69667b2a3f976c7bacac84f4f82de4be07d41`.
Compiler, consumed source closures, provider helper and smali tools are retained.

| Check | Seconds | Peak sampled aggregate RSS, bytes |
| --- | ---: | ---: |
| Builder compile | 2.558 | 340,082,688 |
| Full builder selftest | 0.220 | 1,261,568 |
| Full narrow framework producer | 43.941 | 495,960,064 |
| Evidence seal and inline check | 0.736 | 16,089,088 |
| Fresh-process complete seal readback | 0.669 | 13,402,112 |

All guards exited zero with complete cleanup; time reports record zero swaps.
Limits remained 600 MiB aggregate RSS, 300 seconds and a 1 GiB reserve.
Compile/selftest allowed 512 MiB observed shared-volume growth, the producer
1 GiB, and seal/readback 64 MiB. Observed producer global growth was 169,984,000
bytes; shared-volume changes do not isolate its own allocation. These host checks
do not qualify a prepared guest or successful Google authentication.

| Retained artifact | SHA-256 |
| --- | --- |
| `P/sha256.json` | `739fc9c17258915b0ce7ee01fa3d9e03f47c9d4f4de05ef0c6178d624f8ff3c5` |
| `P/api-impl.jar` | `3f2e3220d6c38feb885044fdb4806d4d3ca7736352bbcc7813e2ee6510463636` |
| `P/classes.dex` | `2bbe60c766a65daeb09b336ff9bd61c4d4f0c228ddbb97f9584eb44cb2b0e79a` |
| `B/compile.guard.json` | `dff1e0113df26c3fd5731a696e7098abea71991edaf702355cf90ee63269731b` |
| `B/selftest.guard.json` | `edb9c61d88b101df088477d3a504b048d4c19841868cc2e92640d5e15994fb7b` |
| `B/produce.guard.json` | `34e351fafa8547bc5a065a8978a4c8d6b02b2f8803a38f6a804e9ee71652c5cd` |

The complete seal binds both closed roots and 7,489 entries at
`/Users/alex/.local/state/vinix/android/binder-identity-framework-sealed-2026-10-29-r1/sealed/manifest.json`,
SHA-256 `4eb3fb91868e49926c1909025f4220b5a01789d78d7ddb388960a6a44056cdb3`.
Its independent fresh-process complete readback passed. Keep both original
bundles unchanged; this report does not replace them.
