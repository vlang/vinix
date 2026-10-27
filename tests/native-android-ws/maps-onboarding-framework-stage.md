# Exact onboarding framework diagnostic stage

`maps-onboarding-framework-stage.v` overlays only the combined onboarding
framework on the immutable `maps-native-onboarding-trace-r3` stage, whose seal
is `96b90172e338080ff50bf0e1188bdefc1f50e61fe3ad654593dfbac4d918d741`.
The r8 controller, r5 native library, launcher, APKs, data, 16 inherited modules
and all 30 inherited dependency seals remain exact. The successor adds its
producer and base seals and one framework overlay module.

The overlay has six regular files: framework JAR, DEX, framework build receipt,
framework seal receipt, headless input receipt and deployment receipt. Only
the five framework-related deployment inputs and their two top-level pins may
change; the headless receipt changes only its JAR input pin. Files retain mode
0644 and containing directories mode 0755. The combined producer must retain
exactly 2104 classes and permit only the reviewed `ViewGroup.attachViewToParent`
method change and new `Settings.Global.putInt` method.

The tool checks complete source inventories, dependency seals, inode metadata,
payload inventories, retained startup ABI contracts and boot module hashes.
APFS clone updates retain a 1 GiB reserve and a cumulative 512 MiB write budget.
Read-only audits refresh observed volume baselines; each bounded module digest
receipt is explicitly charged. External process-tree guards bound aggregate
RSS, duration, output and shared-volume growth. No shell file-size limit is
claimed. The complete checks precede a new stage seal.

`clone-maps-account-stage.v` accepts this stage through its complete generic
inventory and metadata checks; it has no stage-kind or module-count exception.
The isolated kernel patcher profile is `--maps-onboarding-framework`; it pins
all 32 dependencies and rejects any altered overlay, retained module, inode or
deployment delta. Historical profiles retain their original restrictions.

The combined producer passed its complete before/after class and JAR delta
checks and full sealed-bundle readback. It retained exactly 2104 classes and
changed only the two permitted methods. The immutable bundle is
`/Users/alex/.local/state/vinix/android/combined-account-webview-onboarding-framework-2026-10-27-r1`:

| Artifact | SHA-256 |
| --- | --- |
| `sha256.json` | `bfd56090052ec6612179741c5ad88ecfe7fad83027a38cc5949c13892abd1c42` |
| `build.json` | `8ec80f25e35edd176ae333fd78d5e5503ba3f83eac3bf4d7191eacf33120ac60` |
| `api-impl.jar` | `e7d7d590da1ae5f9eb8f9f27aae0c003a30f10f5d79effc0c63f463f958263fd` |
| `classes.dex` | `12e4ad659e61941f0f37ea46dbe1bae8b97bc4ca874bbeaa4841e8832d2cc854` |

Producer source commits were `a968cda5e` (profile), `f908b4c92` (child attachment)
and `c2347e9c9` (Settings). The measured run took 74.10 seconds and peaked at
499,482,624 bytes RSS with zero swaps. Its log and successful process-tree
guard receipt are `framework-producer.log` and `framework-producer.guard.json`
under `/Users/alex/.local/state/vinix/android/maps-onboarding-framework-build-2026-10-27-r1/`.
Both focused fixtures passed signed APK verification and DEX roundtrips.

The stager and isolated patcher profile passed independent source review.
The pinned compiler with its own VROOT built the stager in 8.21 seconds at
508,903,424 bytes maximum RSS and the patcher in 11.01 seconds at 488,538,112
bytes; both had zero swaps. The stager self-test passed in 0.29 seconds at
12,337,152 bytes RSS. All historical and new kernel-profile/FAT tests passed
in 11.49 seconds at 23,887,872 bytes RSS. A first stager compile rejected an
old-V immutable-map alias in the new mutation fixture; constructing independent
fixture maps fixed it. That failed compile log remains retained.

The build directory above retains all compile/self-test logs and guard
receipts. The successful tools are:

| Tool path within the build directory | SHA-256 |
| --- | --- |
| `stage-tools-r2/maps-onboarding-framework-stage` | `a0e087f90cf09c5b83980c0c5f6c2dcf571e0c88ee898240557be45e6864e820` |
| `patcher-tools/patch-kernel-onboarding-framework` | `29235d2deb98f7d5a65ea5961f367ec5aeacadb59e2e6f8c72f88783b40e7cf5` |

Preparation uses the stager's `--prepare FRESH_EXTERNAL_OUTPUT` command. After
the complete sealed stage is cloned separately, the patcher accepts
`--maps-onboarding-framework FRESH_CLONE FROZEN_KERNEL_BUILD BUILD_JSON_SHA256`.
Stage preparation subsequently passed in the fresh immutable output
`/Users/alex/.local/state/vinix/android/maps-onboarding-framework-r1`, sealed by
`fcba5511b0cc2d305ee6e3ba48081bf6bc40fd6117cd91abc691fb2fd7ad01cf`.
All 32 dependency seals, 16 preserved media modules, appended overlay, complete
source/readback inventories, six-file scope and inherited modes passed. The
stage records checkout revision `b64291c5bba76c5799136982c7fd48ef459ffd5c` and
retains the exact tool sources from stage/profile commit `a87c76837`.

Preparation took 161.05 seconds (76.23 user, 49.47 system), peaked at
77,496,320 bytes RSS and used zero swaps. The final logged write charge was
494,768,128 bytes, including 34,603,008 bytes allocated for exact module digest
receipts, below the unchanged 536,870,912-byte limit. Final free space was
15,710,146,560 bytes. The external guard passed with cleanup complete and a
4,533,383,168-byte maximum observed shared-volume drop under its explicitly
budgeted 8 GiB limit.

| Evidence within the build directory | SHA-256 |
| --- | --- |
| `framework-producer.log` | `a8d60a7adef98ddb84e2e54f71b16c8fe3f974e2ed28326abe0001db79bd1c58` |
| `framework-producer.guard.json` | `50a3c2a44291588618512fc48d0eeddf9f5f1ace980bb4381f52eacdcd0fd9d5` |
| `prepare.log` | `abfcccaaef6e49c4d6ed6aab2c8225466eebc2d465e76e9cb9c0a4c6a3acc913` |
| `prepare.guard.json` | `1ea8ffbb9931aab5619b83fcef9a39899e07ff4309eab9416998a95516040576` |

Stage receipt `stage.json` has SHA-256
`f06087f5fdc596ac85f84d501f0bcb2a0cec53457709c9f82d8954b0ffb9acb0`.
Fresh mutable clone, frozen kernel patch and ARM/runtime validation are the
next steps; this preparation is not Maps or Google login proof. Generated
artifacts belong under the external Android state directory, not Git.
