# Intent URI framework369 build

[Maps368](maps368-timing-logger-replay.md) reached a tiled map and search
suggestions, then exited because a GMS Icing/AppIndexing worker called missing
`Intent.parseUri(String,int)`. Provider
`44ce06920f33b3a1d4c9ca0ae0c87642f2e6f665` implements API 28 URI parsing,
including modern intent, Android app and legacy forms, primitive extras,
selectors, source bounds, unsafe flag filtering and malformed-input errors.

Builder `8b26b93a1` and recorder `be605eeb981d340fc53cd1fb3346e0614080d085`
retain the complete qualified framework367 baseline, including complete
365/361/359/353 inputs. The provider is frozen from its committed source and
compiled in a private VROOT with the exact authenticated353
`framework_replace_method` helper. The live helper must match that retained
definition. Compiler, host tools, generated C, before/after V closures and
actual command exits are retained.

The complete 648-file builder bootstrap is retained at
`/Users/alex/.local/state/vinix/android/intent-uri369-framework-builder-build-2026-10-26`.
Manifest `f8efd6af2c765d356b33f0869990eb7531ba486162bf97433520f8e57d34e31f`
and builder binary
`16d2579abf9b52b1f3a7e4a1682ede757ac00864d5db4d795893395a0a3918e3`
are recorded. Compilation and all six class-delta mutation tests exited 0.
Its 270-file V closure remained unchanged. The original complete checker
verified all 648 file hashes and exact file set; adjacent own receipt SHA-256
`74781c57b24dceb9f6ea1c9fa61ec26bb56bd7e593ed62b32f718f21de9679ae`.
The external bootstrap invocation receipt SHA-256 is
`f59cc5bfb6fc52851506658408ac70f7a3e843750f5b4fdc08e46d44e25ef16f`.
The independent bootstrap check also exited 0, verified all 648 files and
the complete 270-file closure, and retained receipt
`/Users/alex/.local/state/vinix/android/intent-uri369-builder-bootstrap-peer-readback-2026-10-26/complete-receipt.json`,
SHA-256 `bdd96be99e66232ade6c9891df6d49f20dc50903a9338d4fc81332cc6316a2a1`.

The framework build retains source and disassembled DEX inventories with
exactly 2,076 classes before and after. Only `android/content/Intent.smali`
may change; no class may be added or removed. Only `classes.dex` may change
among the three JAR members. Duplicate application and a malformed required
Intent class declaration must reject without changing any input inventory.

The framework bundle is retained at
`/Users/alex/.local/state/vinix/android/intent-uri369-framework-build-2026-10-26`.
Its exact pins are:

| Artifact | SHA-256 |
| --- | --- |
| `sha256.json` | `9f52eb8f69aaaa6d57f8ca3ce11dd20c870de8032bc821aff5e7527473334c93` |
| `framework/api-impl.jar` | `74e1d74b9ecf51e302f2802a2d291ff15f1d1793495d67c7c108d1d5350a884b` |
| `framework/classes.dex` | `9fa3054f5000bc68a6ab6c159a98442305f287a8e8a5b28cf0a20402117c3ab5` |
| `validation.json` | `92d2d32fb15af9fd06f25d2e49e485cbc3c8213bd60421f082912371825c173c` |

The provider's 144-file V closure and the builder's 270-file V closure remained
unchanged. Original, cloned and final retained baseline367 checks exited 0.
All 33 recorded build commands exited 0. The final complete-bundle readback
verified all 50,901 file hashes and the exact file set, exit 0, at
03:11:57–03:12:50 UTC on 2026-10-26. The original builder invocation was
interrupted during its final readback after sealing. Its incomplete
`intent-uri369-framework-build-2026-10-26-before.json` remains retained,
SHA-256 `9e54f68286a051b4a32f5819bc57192ffaceeac76a1cab74955b64ffb4b67884`.
The recovery invoked the unchanged original complete checker against the
unchanged sealed bundle and wrote fresh adjacent artifacts:

| Recovery artifact | SHA-256 |
| --- | --- |
| `intent-uri369-framework-build-2026-10-26-own-recovery-receipt.json` | `bd131bed3fb855e841333a722cbb5147cb35def7b84c9e68b816f71dc005b085` |
| `intent-uri369-framework-build-2026-10-26-own-recovery-invocation.json` | `b2a7edcdb72b399179674659b68670819ec03662b7c6f4f8cc9999ae4f16fd4b` |

The independent reader in commit `41fd350ce` also passed, checking the actual
source and DEX inventories, sole Intent change, three-member JAR delta,
mutation guards, exact isolated helper and provider, all 33 command statuses
and all 414 closure inputs. Its original complete checker verified all
50,901 files and the exact set at 03:13:24–03:14:12 UTC. The executed reader
source and binary remain adjacent to these receipts:

| Independent artifact | SHA-256 |
| --- | --- |
| `intent-uri369-framework-peer-readback-2026-10-26.json` | `9232f60211e3826356ee00d8000726e014b4981fc9c9bdc74978255265f4c488` |
| `intent-uri369-framework-peer-readback-2026-10-26-command.json` | `0982e6314fd7afbd98c8d9cdc544e69e158ca7e088ee1108e365e6f409c1d472` |
| `intent-uri369-framework-peer-readback-2026-10-26-inspection.json` | `24d98d55ccea19be9f4e6c49731a0ad856f9b93c43e015cf91da52fd17ed8ffe` |

Same-APK ART behavior and the subsequent Maps replay are separate runtime
qualifications; this build performs no guest execution.
