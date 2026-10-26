# Deferred Bundle parcel regression363

Experiment363 failed ART validation. The old framework reproduced the loader
exception, and the new framework failed a later decode assertion. The retained
bundle records both failures; it is not a passing regression qualification.

Fix `69432c5e3c2240862f0019ea2eec36132bc36f80` defers Bundle value decoding
until a map accessor runs, allowing the caller to set its application class
loader first. Bundle reads retain an independent Parcel snapshot, including
local Binder references. Copy and write paths preserve deferred state; clear
releases it without decoding. Explicit monitor instructions protect snapshot
ownership and recycling.
Bundle now supplies a loader-aware CREATOR, and `Parcel.readParcelable` dispatches
to the two-argument `Parcelable.ClassLoaderCreator` overload when available.

[Maps360](maps360-permission-metadata-replay.md) reached a live map and search
suggestions before failing with `ClassNotFoundException` for
`com.google.firebase.appindexing.internal.Thing` on `GoogleApiHandler`. Its stack
passed through `Parcel.readParcelable`, `readValue` and `readBundle`, using a
loader whose DexPathList contained only framework inputs. This fix addresses
that eager Bundle decoding path. Its effect on Maps requires a separate replay.

## Source and host validation

Fixture `2082297e21b003d63df2cf17a584c781aa903627` uses an application Parcelable
and a rejecting class loader to detect premature decoding. It is designed to
check default and explicit-loader Bundle reads, inherited BaseBundle map access,
copy and clone isolation, deferred `putAll`, loader-aware creator dispatch, Parcelable
arrays, nested Bundles, Binder identity, CREATOR/readFromParcel round trips,
null and empty values, cursor alignment and malformed framing. The focused APK
contains only Main and four probe classes.

Source checker `ced419c6c4b2954d2dc9fe1b2d423539e4625849` verifies five malformed
or destination/interface guard cases and duplicate application without output
mutation, all 78 baseline map reads, explicit monitor cleanup, Binder-preserving
snapshots and unchanged unrelated Parcel/PersistableBundle behavior. It
assembles and disassembles twelve API28 classes. The complete 719-file host
bundle is
`/Users/alex/.local/state/vinix/android/bundle-parcel-source-attempt2-2026-10-26`,
manifest `0fba28882f1cc77790535b65e703ca2b86ba560315e2e670a13544f629938d75`.
Root's complete readback exited 0 with every hash and the exact file set matching.

Builder `081a9a10796a344f9f4dd17375d62e308c986a2b` and ART harness
`f2de784e0f13b391f83f42c96bc5a583aa286aa5` each compiled with an explicit private353
VROOT, retained source/generated C, pinned compiler and host tools, and equal
270-input source closures before and after compilation. The harness's synthetic
semantic checks passed. Their complete 644-file bootstrap bundles are
`/Users/alex/.local/state/vinix/android/bundle-parcel363-framework-builder-build-2026-10-26`
and
`/Users/alex/.local/state/vinix/android/bundle-parcel363-run-bootstrap-build-2026-10-26`.
Recorded and root complete readbacks exited 0 for both.

| Source or host input | SHA-256 |
| --- | --- |
| `androidtools/framework_bundle_parcel.v` | `b53e908d4ce884c1f17ae1723093487a4ea2f4de87065e3eb6f79cb31014da3e` |
| `startupfixture/bundle_parcel.v` | `ea61bf298f17589252fda8612b616c463c7cdf01bdc7d3816402dc4462f1bfb5` |
| `bundle-parcel-source-check.v` | `7c671ab51b28fdbc2d0df17976e7aaefdb0cb76050458178922e9142f3b8d8ba` |
| `bundle-parcel-framework-build.v` | `d8408a2f70c737698d533c17d9f47148976ffc8fc232587e6c9adc075cc70028` |
| `bundle-parcel-run.v` | `80b0b752ba231687a3e45ae92854c797ce7b5395cd8ebf3007c3a27340f748b4` |
| Builder bootstrap manifest | `4a76d814e163fba3d8d389b60d38286b1b84d776b66b2a84e0c2e7ebb951a57e` |
| Harness bootstrap manifest | `fca8772d025e09a2d774ef93ef25052d0a5f1b41e793e9ab6df8bdc948b2bcb9` |
| Bootstrap harness executable | `5560df8589d0a74f28d568b267863632c18fa1821e9732065080aaf2fa0e0d17` |
| Frozen V compiler | `109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e` |
| Complete-bundle checker290 | `52c03dc3952acf9a51c5288c12784162171c1fa83522cd1cd5ae268d79092004` |

## Complete framework build

The sealed framework bundle is
`/Users/alex/.local/state/vinix/android/bundle-parcel363-framework-build-2026-10-26`.
It retains the complete qualified361 bundle and its complete359 and353 baselines.
Original, cloned and post-build baseline readbacks passed. Frozen builder and
driver source closures matched before and after compilation. Compiler, linker,
Java and Smali tool identities are retained; SDK/JDK libraries remain
environmental inputs.

Complete source and DEX comparisons change only `android/os/BaseBundle`,
`Bundle`, `Parcel` and `Parcelable$ClassLoaderCreator`, add only
`android/os/VinixBundleCreator`, and remove no classes: 2,074 become 2,075. Only
`classes.dex` changes among regular JAR members. Duplicate and malformed
provider guards preserve their complete 2,074-file inputs.

Builder, root and independent complete readbacks exited 0 for all 32,872 file
hashes and the exact file set. Independent filesystem inspection confirmed the
source/DEX inventories, exact class delta, JAR member delta, unchanged private
closures, all 32 command exits and retained baseline qualification receipts.
The independent receipt is adjacent to the sealed bundle as
`bundle-parcel363-framework-peer-readback-2026-10-26.json`, SHA-256
`1e85a89689e9ae8a0e9dea99e17f4d247759cf439626a551157557a5b83667bc`.
Adjacent `-command.json` and `-inspection.json` retain the actual checker exit
and the separate checks.

| Framework or runtime input | SHA-256 |
| --- | --- |
| Qualified361 complete manifest | `9649ab0f596dcd44ce5979a2e129548ca550d2ad54b4d2995fd3c714e125f8e9` |
| Old361 framework JAR | `077bb9f1784e2945accebc9043e0d8d54617bb0e01725e97824807d8cc57b10a` |
| Framework363 complete manifest | `584a5fb8315925d6f715dda02289ac1fc0c966cb06496cfe6afe36e32b43cf03` |
| New363 framework JAR | `14a019f166550f5cf5cff48b4c29d0d7aa61db35d3514cef00b4a67ad151de63` |
| Native351 SO | `d3da7eefd58c8f1faf7a88dd0b6fa0839cebdba145d236bd5fe1ecc185e257a1` |
| Launcher353 | `406b187bb0ef8f42c57cc26532abae6599b837b5b0226da7afd23fcda8ca67a0` |

## Same-APK ART evidence

The harness compares old361 and new363 with the same APK, native351, launcher353,
base runtime and frozen native closure. The framework JAR is the sole runtime
difference. Preparation and guest execution retain the 1,024/768 MiB capacity
gates. Old361 must reproduce the exact application-Parcelable class-loading
failure through `Parcel.readBundle`; new363 must emit all six ordered markers
exactly once and survive the full 35-second observation without failure markers.
The retained old361 run reproduced the expected app-class failure. Dalvik's
exception includes its full framework-only DexPathList. The stack enters a
nested Bundle before reaching the Parcelable array: one `readParcelable`, two
`readValue` and three `readBundle` frames. The original synthetic semantic
checker assumed a shortened exception and array-first stack and rejected this
valid negative result. Its original source, executable, APK and raw evidence
remain preserved. A fresh365 harness will check the actual exception shape.

The actual new363 run emitted `DEFERRED-PASS` and `COPY-PASS`, then failed the
shared `decoded` assertion while decoding a `putAll` result. DEX offsets map
`check(Unknown Source:113)` to that first post-copy decode and
`decoded(Unknown Source:99)` to its assertion. The existing generic Parcel tag21
path writes no Binder payload and constructs a new Binder when reading it,
which independently establishes an identity-loss bug. The assertion also checks
other decoded values, so follow-up ART must establish the causal fix. This run
does not pass.

Follow-up `f5f7ce38c5fe58cc7683fcbc552c9d9f67368cb5` changes generic Binder values
to use the `IBinder` interface and the existing strong-reference Parcel methods.
Checker `02d31e93d9faadbf0347b62a09435d8788284b73` adds original-branch rejection
guards. The fixture remains unchanged. Fresh365 ART evidence is pending; no
successful ART363 or Maps364 result is claimed here.

The follow-up host proof is `bundle-parcel-source-attempt4-2026-10-26`, manifest
`29291fde31a878075393157d5f86a9f656ed515feac522c0377381274d5339e2`.
Recorded and root complete readbacks exited 0 for 736 files; seven malformed
guards, duplicate rejection and twelve-class API28 assembly/disassembly passed.

## Failed evidence preservation

The original fixture root is
`/Users/alex/.local/state/vinix/android/bundle-parcel363-fixture-2026-10-26`.
The original runner, tools, APK, runtime inputs, logs and raw results are retained
unchanged. The original new-run after-check receipt is absent: the runner stopped
before writing it. Preservation checks compare the current complete shared input
closure with its independently pinned original map before and after inspection.
They do not create a replacement receipt or a passing ART result.

Checker `b4e202538e2a3d84c092e63e81bb298dd318e762` authenticates both exact traces,
their raw `startup_failed` outcomes, the same APK, the complete framework bundle,
and the native closure with only the framework JAR changed. It records explicit
`FAILED-ART-EVIDENCE` and `fixture_passed: "false"` fields. Its frozen bootstrap
retains source, generated C, compiler and host identities, explicit VROOT, actual
compile/self-test exits and equal 270-input source closures. The original local
`inflater-trace-seal` inventories the retained failure bundle separately from
regression qualification.

The complete 645-file checker bootstrap is
`/Users/alex/.local/state/vinix/android/bundle-parcel363-failure-check-build-2026-10-26`,
manifest `c2ebcb36f6254533cc4d83576c6d53949be19523e21da10a080539146b76df96`.
Recorded and root complete readbacks exited 0 for all 645 files and the exact
file set. The root receipt is adjacent as
`bundle-parcel363-failure-check-root-readback-2026-10-26.json`.

The original local sealer exited 0 for 34,089 files. The failed fixture's complete
manifest is `3c3fea1c43bef44399b69cc11dabe44d17fcad382978bb2a425e1b4ba05f4f94`.
It includes `failed-art-check.json`, the retained failure checker/source and
`qualification/failed-art-seal-check.json`. Adjacent command receipts record
the actual audit, seal and readback executions; original raw results remain
`startup_failed`.

The recorded complete failed-fixture readback exited 0 for every hash and the
exact file set. Its adjacent receipt is
`bundle-parcel363-fixture-failed-own-readback-2026-10-26.json`, SHA-256
`9a7a919f52017845cde47021030a70211da04767b09c0467dc06d13db1afa0b4`.
The independent root complete readback also exited 0 for all 34,089 files;
its adjacent receipt is `bundle-parcel363-fixture-root-readback-2026-10-26.json`.

| Retained failure input | SHA-256 |
| --- | --- |
| Signed APK | `c34f9b9b231fb2b1c7ce747c76c9fe695ba2ecc3980ee3775c547d86fbf1ff11` |
| Original shared input map | `9fd9d7d847c5ebaba5d668b89ff195e0a76df750ded451963635e7325bd40d49` |
| Old serial log | `3685de7f8ed7f929a0397194e1a22a18f61bbe77102aff1b035017bac210536d` |
| Old raw results | `3d77da281431e6885a16a8b57ec1d3c3bd217652f0e8eef6e734e5510c9c0a74` |
| New serial log | `95927bd8fc4e5b65dbf28c3b33738cab17649ab36a616243485d3ad02c236858` |
| New raw results | `b5a1e21b8e03bb17f3a50e854045bd9663414cef0d74871be0a21c0f5f2b307f` |
| Failure checker source | `6ce330aecc55ee9fc9077ea642953135e9c59d13238a437759a094320079e257` |
| Failure checker executable | `6a0708dbd54100985b9e9fef5389ffb622b216c7e308d17f8cf85ce6a6882a14` |
