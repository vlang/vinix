# Framework boot Maps media

The successor makes Android framework classes visible to boot-isolated GMS
module loaders. The native launch preserves the ten original core boot entries
and appends only `api-impl.jar`; it retains the original system class path,
including the resource-only framework APK. Native JNI initialization uses the
library's exact absolute path. The companion SDK changes one loader call in
each of `Resources.getSystem()` and `ATLLoadedApp.loadFromPath()` to use the
system class loader for framework and package resources.

Only those two existing SDK methods change. Class membership stays 2,117, all
other 2,115 canonical classes remain unchanged, and no methods, fields or
classes are added or removed. Native production changes exactly
`build-support/android/nativews/bootstrap.v`,
`build-support/android/nativews/runtime.v` and their generated C. Generated JNI,
binding declarations, all 721 exports, native source membership and copied
header bytes remain unchanged. The fresh native producer must couple to the
exact completed new SDK; old native provenance remains historical.

The planned nine-file overlay inherits prepared `maps-webview-package-r1`,
manifest `d6ca42875b50ff239966e42933bd9eab711905e314371b9d68af3c3eb0226b87`.
It replaces the JAR, DEX, native DSO, four framework/native metadata files,
headless input receipt and deployment receipt. All eight replacement input
identities and the framework/native manifests must change. Module 59 follows
all 58 retained modules. Every inherited module digest remains exact.

All 134 complete inherited inventories remain required, using bounded
64 + 64 + 6 batches. The successor requires exactly 137 dependency seals:
134 inherited roots, the prepared parent, new SDK and fresh native producer.
The stager and ancestry companion require exactly 52 parent stages; ancestry
retains 135 sealed selectors. The 5 GiB initial-space gate, 4 GiB outer growth,
512 MiB internal growth, 1 GiB reserve, 600 MiB RSS and existing time/output
bounds remain unchanged. Insufficient space does not authorize weaker checks
or deleting evidence.

All 70 consumed raw classes must equal the new SDK. Two consumed canonical
classes change: Resources and ATLLoadedApp. Canonical SDK cloning normalized
the unchanged WebView source from raw
`3cd08baf04f82e1f0d7587219f4f6e5c3310d439086ba6ad6c016b20e543ba1d`
to `dd38134f402fbcb5297a50cea97eb7f903963e526026be3a49301ba67e69434e`.
The complete producer readback confirms exactly that third raw formatting
pair; no general formatting allowance is accepted.
Complete 91-origin, 92-input, 721-export, 58-C/header and native helper closures
remain audited. The C/header inventory may rebase exactly five owned paths,
with only the generated C value changing; the other 53 path/value pairs stay
exact. The complete measured builder closure is 659 to 660 inputs, with exactly the
registry helper and new `framework_boot_classpath.v` helper changed/added.
The native-generator closure remains 340 inputs. Complete producer readback
confirmed every count and identity, including unchanged generated JNI,
bindings and all 721 exports.

The completed SDK at
`combined-account-webview-framework-boot-framework-2026-11-03-r1` has manifest
`af23c13d90f557c4f7f208ae75c39ad8bcf0efd86fc88fddfe399fe2e66a4e91`.
Fresh native root `current-native-build-2026-11-03-framework-boot-r1` has
manifest `0a6d8126bd0842985123578550fc3fa60c0eb12543e8fcf680d1644f6b49f81f`
and DSO `f3dafa843033f7fb5245cde6007e66eb603ae0fb747fdc1824a33f731ca7088d`.
All SDK/JAR/DEX/raw/canonical/helper and native/source/header/JNI/binding/export
identities were independently rehashed before the media source freeze.

Complete native readback is retained outside Git at
`framework-boot-native-controls-2026-11-03-r1/readback-r2/result.json`, SHA-256
`39e02e7413d2844ebcfbb5e8cbb1ebb053e329063bfe00152cb82fcbaa75f5e7`.
Its whole-file generated C audit permits only changes to `ws_bootstrap` and
`ws_load_jni`, plus new `ws_boot_classpath` and its prototype. All other bytes
remain equal; the changed JNI-loading function also matches its exact
absolute-path transformation. The media gate
pins the complete resulting C file as
`8321888455233a0a01c657182b79320733fc4ef8f02f4b65f236f122d7bcfff3`.
The complete C/header inventory is
`df1b7598fdb9fe687f8db41b04c9a0e887b655e9dd3a38af4814e7977e953a3c`.

The original native-only draft was superseded before compilation and is
preserved outside Git at
`/Users/alex/.local/state/vinix/android/framework-boot-native-only-draft-2026-11-03-r1`,
including source checksums. The existing WebView qualification and every older
complete bundle, failed attempt, source snapshot and auditor remain required.

SDK and native production passed; all producer-dependent media pins are filled
from direct readback. The [November 3 resource handoff](framework-boot-runtime-blocked-2026-11-03.md)
and original pending notes remain unchanged historical records. The five
original stager phases passed with a stricter 128 MiB growth budget; the
corrected patcher subsequently passed its complete 52-profile, 45-case FAT
suite on November 4 under the original 512 MiB growth budget. Both original
patcher source/input attempts and interrupted FAT scratch remain preserved.

Complete current input capture then failed because its November 3 lists named
`MacOSX27.0.sdk`, which was no longer installed. The generic `MacOSX.sdk` path
now resolves to SDK 27.2. The original complete SDK 27.0 bytes, input hashes and
resolved-path map remain at
`maps-webview-package-tools-2026-11-03-r1/current-closure`, covered by the
original three-root tool seal
`fb121f3d4581e003155af1bcb6d093f1ee5dbc1251825c2551b9a53b2c570ed2`.
The failed capture and partial output are retained without changing their
input lists or installing replacement files under `/Library`.

Production host tools were rebuilt from the same reviewed `sources-r2` with
explicit SDK 27.2 and fresh input lists. Their stager selftest, complete
SDK/native admission, native helper enumeration and batch checks passed.
Fresh discovery found 284 V / 408 C stager inputs and 273 V / 405 C patcher
inputs. Strict original/copy/recheck capture passed all 743 actual current
inputs, including the rebuilt batch tests and today's ancestry/discovery
helpers. A fresh readback of the complete original three-root SDK 27.0
provenance seal also passed; that full input closure remains separate history.

The SDK 27.2 patcher suite has reached the later FAT cases but full
qualification remains pending after three stops at the original shared-volume
growth cap. Each stopped with guard 125, child 137 and complete cleanup; no
functional failure appeared. All three complete scratch trees are retained.

| SDK 27.2 FAT attempt | Elapsed milliseconds | Observed growth bytes | FAT cases passed |
| --- | ---: | ---: | ---: |
| Original | 78,433 | 544,116,736 | 32 |
| r3 | 105,549 | 537,956,352 | 43 |
| r4 | 29,480 | 548,069,376 | 20 |

A wrong patcher flag in r2, an initial batch invocation missing its required
output-root environment variable and an initially rejected scratch-preservation
guard setup also remain recorded; corrected invocations preserve the original
attempts. The r4 complete scratch preservation passed with guard/child zero
and complete cleanup under the original limits.

Stager preparation is independently qualified and has no kernel-patcher
dependency. The current SDK 27.2 stager executable is
`318bdadd81538580b0247bda008b0f4bef95bfcb634b56b30cffb8a4920e736f`;
the SDK 27.2 patcher executable is
`628cd967d406e25123980be7f5f0daa188b8efb659f36442b6c776170188119f`,
with full FAT qualification explicitly incomplete. All six current executable
sources match frozen `sources-r2`. The separate batch snapshot retains its
older, unused patcher source before the three clone corrections; its other
five owned source copies match current. That historical patcher copy is
outside the batch import closure and remains unchanged.

Complete evidence is retained below `/Users/alex/.local/state/vinix/android`:
`maps-framework-boot-tools-2026-11-03-r1`, the separate
`maps-framework-boot-inventory-batches-tests-2026-11-03-r1`, and the original
complete SDK 27.0 input closure. These roots are closed. The first joint seal
at `maps-framework-boot-tools-sealed-2026-11-04-r1` stopped at the original
64 MiB shared-growth cap: guard 125, child 137, complete cleanup, 16,134 ms
and 73,519,104 bytes observed growth, with no output. Its entire failed
attempt is preserved for inclusion as a fourth root in a fresh seal retry.
Final evidence sealing, media preparation, kernel installation and runtime
checks remain pending; these source and stager checks establish no Maps
completion result.
No Android SDK, native library or signed fixture rebuild is needed for this
host SDK change. These host checks establish no Cronet, Maps rendering,
Google authentication or imagery result.
