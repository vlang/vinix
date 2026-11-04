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

The prepared nine-file overlay inherits `maps-webview-package-r1`,
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

The SDK 27.2 patcher remains functionally unqualified. Its first three full
suite attempts stopped at the original shared-volume growth cap, each with
guard 125, child 137 and complete cleanup; no functional failure appeared.
All complete scratch trees remain retained.

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
complete SDK 27.0 input closure. These roots are closed. Two joint tool-seal
attempts stopped at the original 64 MiB shared-growth cap, both with guard 125,
child 137 and complete cleanup. Complete attempts remain preserved:

| Tool seal root | Elapsed milliseconds | Observed growth bytes |
| --- | ---: | ---: |
| `maps-framework-boot-tools-sealed-2026-11-04-r1` | 16,134 | 73,519,104 |
| `maps-framework-boot-tools-sealed-2026-11-04-r2` | 6,191 | 90,341,376 |

The first attempt produced no output. The second retained that first failed
root alongside the three evidence roots. Both complete failed attempts, and
the later failed retries, remain in the completed aggregate seal below.

Media preparation completed independently using the qualified stager and
source revision `38aa4e5dd7ae9471427afde9e90a0adea33f75cf`. The prepared root
`maps-framework-boot-r1` has completion manifest
`43309208792e5ce55ed9c4b8af9e0ae5b6ff1f849f43b27a04948659224dd499`
and stage receipt
`a87760cf0daef526558da7b2b24068b868fe16f194e2f8692da8548eed8f465b`.
Both complete 134-inventory audits and all 59 module readbacks passed, with
the 58 inherited module digests retained and the nine-file overlay appended.

Controls at `maps-framework-boot-preparation-2026-11-04-r1` record guard/child
zero, empty reason and complete cleanup in 606,929 ms. Sampled/detailed RSS
peaked at 91,766,784/92,241,920 bytes with zero swaps. Observed outer growth
was 1,628,585,984 bytes under the original 4 GiB limit. The stage receipt
records 137,650,176 bytes internal charge; the final completion sample was
153,235,456 bytes, below the unchanged 512 MiB internal budget. The original
5 GiB initial-space gate, 600 MiB RSS, 900-second, 1 GiB reserve and output
bounds remained unchanged. Preparation required no kernel-patcher invocation.

The completed aggregate tool-data seal is
`maps-framework-boot-tools-sealed-2026-11-04-r5/sealed/manifest.json`, SHA-256
`773f284250307ed0e40ca1481094d4e768b6069990bd0a39e843f08a81ba1124`.
Its 15 roots and 67,595 entries retain the original tool/batch/SDK closures,
all earlier failed seal roots, later r5–r7 FAT attempts, resource preflight
history and the qualified old-tool archive. Seal and separate fresh readback
both exited zero with complete cleanup in 21,219/12,448 ms and observed
growth 22,810,624/33,484,800 bytes under the unchanged 64 MiB growth cap.
This completes storage of those closed artifacts and does not qualify the
new SDK 27.2 patcher. Original pending notes remain historical records.

A later same-byte SDK 27.2 r8 suite stopped at the original 512 MiB growth
cap after 38 FAT passes: guard 125, child 137, complete cleanup, 134,064 ms
and 538,034,176 bytes observed growth. Its complete scratch is retained at
`maps-framework-boot-patcher-fat-2026-11-04-r8/scratch`; guarded preservation
passed zero/zero with complete cleanup in 176 ms, and executable comparisons
before and after matched. No reinstall used this unqualified executable.

The final four-root, 6,339-entry supplement is
`maps-framework-boot-resume-handoff-sealed-2026-11-04-r1/sealed/manifest.json`,
SHA-256 `1529cc760e8b75f610a55df2ecb1b106e5c55df443bcb141a26d575aa18138ab`.
It retains complete r8 evidence/scratch, the current CI-only R2 admission,
the Q5 aggregate archive with controls, and the kernel-handoff archive with
controls. Seal/fresh readback passed zero/zero with complete cleanup in
2,980/1,502 ms and growth 5,931,008/2,215,936 bytes under the original 64 MiB
cap. Current evidence storage is complete, including prior failed attempts;
this adds no functional qualification for `628cd967...`.

The installed frozen kernel uses the qualified original `864cd44...`
[archived patcher](framework-boot-archived-patcher.md).

Runtime checks remain pending. The guest has not booted this prepared image.
The current read-only admission attempt, with only the existing CI VM present,
refused its unsupported foreign drive configuration: guard/child one with
complete cleanup in 171 ms. CI remains running with its configured 32 GiB
and eight CPUs; no foreign action or guest boot followed. These stored
artifacts and preparation results establish no Maps completion result.
No Android SDK, native library or signed fixture rebuild is needed for this
host SDK change. These host checks establish no Cronet, Maps rendering,
Google authentication or imagery result.
