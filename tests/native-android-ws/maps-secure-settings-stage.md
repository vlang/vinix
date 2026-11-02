# Secure-settings Maps media qualification

This profile adds Secure.putString through the supplied ContentResolver and a
fieldless TileService using the audited API 28 permission-qualified SystemUI
broadcast. Only Secure changes; TileService adds three methods. Class membership
grows from 2,111 to 2,112. ContextImpl, UserManager and StatusBarManager remain
unchanged, including ContextImpl's manually consumed JNI fields and native theme
method. Core is `2af821249`, producer `ecd559062`; the
[framework/native report](secure-settings-pair-2026-11-02.md) records the pair.

The six-file overlay inherits `maps-broadcast-permission-r1`, audits all 119
complete inherited inventories and requires exactly 121 dependency seals. It
appends module 52 after 51 retained modules. The actual 45-stage ancestry reaches
the original `maps-account-r5` inode inventory. Exactly five existing deployment
inputs and the framework manifest change. Only the JAR changes in the seven-key
headless input map; native files and provenance remain pinned.

The complete framework audit admits only Secure and TileService. All 70
native-consumed canonical classes remain equal; Context and ATLLoadedApp have
exactly two pinned raw formatting changes from canonical cloning. The other 68
raw inputs stay equal. The original broadcast SDK remains the native producer's
provenance. The native bundle, 91 origins, 92 inputs, 721 exports, complete
production sources, JNI, generated C, all 58 C/header inputs, and complete
650-entry builder / 340-entry generator closures remain unchanged. Historical
profiles, complete original bundles and their checkers remain required.

| Artifact | SHA256 |
| --- | --- |
| Prepared broadcast parent | `cd669a48739890494fd4780acd077c25e0bbcbf586330bb2f855ead92ae0fe7b` |
| New SDK manifest | `0c7485f9a38c52dd6ef6ddd60c936f49d694da267ae30fccf6dea1163a21529b` |
| Retained native manifest | `e371c8d365b78493f9f9d660ceceb1cb2b1382eaa60cae06bcbe4aad0c6c233b` |
| Retained native DSO | `29b2631c36a4a8c802e904e936c23e090fb2de3b5019ac93548df1b15de2a8f1` |
| Qualified stager | `a309311755daa0414c58c7a7bf77959431a4b9f0fa20b5d1fff523539120b5b8` |
| Qualified kernel patcher | `7250ef7a8b99d729822a3355a67aefaefaed08d86916f354f219f2c3327b5603` |

Required tool checks passed on first attempts: serial V/C builds, stager
selftests, full framework/native/header/helper audit, 45 receipt/profile checks,
38 FAT cases, every prior inventory test plus real 119-root positive/refusal and
full-byte tests through node 118, actual ancestry, and discovery of 284 V / 408 C
stager inputs and 273 V / 405 C patcher inputs. Complete original/copy/recheck
capture retained 862 inputs. The protected batch test parent existed before
invocation. Final sources match the frozen copies; independent source review
approved. Uncompiled provisional scope drafts are preserved outside Git.

All 28 tool guard and child exits are zero, reasons empty and cleanup complete.
Maximum sampled aggregate RSS was 514,097,152 bytes; detailed maximum
510,001,152 bytes, with zero swaps. Original limits remain: 600 MiB RSS,
300 seconds for builds/tests, 900 seconds for full audits, 1 GiB reserve,
512 MiB tool growth, 64 MiB seal growth and shell file cap 16777216. Compilers were
serialized and stopped before handoff.

Evidence remains outside Git at
`/Users/alex/.local/state/vinix/android/maps-secure-settings-tools-2026-11-02-r1`
and `maps-secure-settings-inventory-batches-tests-2026-11-02-r1`. The Secure
producer seal is
`4a56da489a48061b7fefbe860c88c81ab9d930e509542e2f103512a7d650fe7e`.
The complete original broadcast producer bundle stays separately required under
`b755b2951d12e064f648b6baa872019aba414dfe61739c65197500382d9ef67d`.
The closed tool and batch roots passed sealing and a separate fresh-process
readback: two roots, 11,638 entries, manifest
`d32d70f4317b70dcf58c6a04f4063437d0e5d2bea0e74f4e065dd457819c7300`
at `maps-secure-settings-tools-sealed-2026-11-02-r1/sealed/manifest.json`.
Both seal/readback guards and children exited zero, reasons empty and cleanup
complete under the original 64 MiB growth cap and 1 GiB reserve.

The source base before this tool commit is
`749cb77becbf8bf0750f857b8bc98519c41a4844`. Media preparation follows tool
qualification. This report claims no ARM, account, checkin or current imagery
result.
