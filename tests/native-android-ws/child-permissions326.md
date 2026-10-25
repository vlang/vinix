# Child-order callback and asynchronous permission results

Source baseline: `14e5ebb74a288df4636d87f89a5fb31c96ef20d6`.
Framework325 restores the protected `ViewGroup.getChildDrawingOrder(II)I`
default and completes Activity permission requests through the main Handler.
The callback returns the supplied drawing position, allowing inherited,
virtual and super calls to resolve. This change does not add renderer
dispatch through custom drawing-order callbacks.

Normal permission results use a snapshot of the requested names and the
existing PackageManager decisions, in the same order and with the original
request code. The pending flag is cleared before virtual callback dispatch,
so a callback can request again. An overlapping request receives the
Android-compatible synchronous cancellation with empty arrays. Validation
retains the negative-code, overlap and null/empty-array precedence. The base
`onRequestPermissionsResult` remains a no-op. No grants, location provider or
permission-controller UI are introduced. The deferred result checks the
existing destroyed-Activity flag; recreation routing and a destroyed-Activity
runtime case are outside this regression.

The child-order contract comes from immutable Android10
[ViewGroup.java](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/57bb140be9e48cf08acba131f7463e461777bb8e/core/java/android/view/ViewGroup.java),
revision `57bb140be9e48cf08acba131f7463e461777bb8e`.
Its original source, tag receipt and capture receipt are retained at
`/Users/alex/.local/state/vinix/android/child-drawing-order325-sourceproof-v2-2026-10-25`,
manifest SHA256
`5260ec9a36fbd6303715433e741c263dc1a5239c56bbc452c624e3a38d1ed6cd`.
Root independently checked the exact file set and all three payload hashes.
Its receipt is
`/Users/alex/.local/state/vinix/android/child-drawing-order325-root-readback-2026-10-25.json`.

Permission ABI, validation and pending-request semantics are authenticated
against Android10 revision `dff3deab5d25f8bbfd49abfb423043c9be47b7db`:
[Activity.java](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/dff3deab5d25f8bbfd49abfb423043c9be47b7db/core/java/android/app/Activity.java)
and
[PackageManager.java](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/dff3deab5d25f8bbfd49abfb423043c9be47b7db/core/java/android/content/pm/PackageManager.java).
The complete 15-file source bundle also retains ActivityThread and the exact
selected framework permission-policy, lifecycle, Handler and Looper inputs:
`/Users/alex/.local/state/vinix/android/activity-permissions325-sourceproof-2026-10-25`,
manifest SHA256
`3e0b4959f67e7df78cce5ef252a79392aa0d5d3b5ec78f6e39b128f59edf8820`.
The maintained `activity-permissions-sourceproof.v` checker SHA256 is
`f8c3ba9e188df7f9518e275b6bcf15cb5509affcd7c0cf22ecd8a7cc13ae718f`.
This local fixed-policy result path preserves the existing policy rather
than implementing the Android permission-controller flow.
Root independently verified all 15 payloads; its receipt is
`/Users/alex/.local/state/vinix/android/activity-permissions325-root-sourceproof-readback-2026-10-25.json`.
Reproduce with assertions enabled and a fresh receipt outside the bundle:

```sh
VROOT=/Users/alex/code/v build/android-maps/queue284-tools/v_old276 -o /tmp/permission-sourceproof tests/native-android-ws/activity-permissions-sourceproof.v
/tmp/permission-sourceproof verify /Users/alex/.local/state/vinix/android/activity-permissions325-sourceproof-2026-10-25 3e0b4959f67e7df78cce5ef252a79392aa0d5d3b5ec78f6e39b128f59edf8820 /tmp/permission-sourceproof-fresh.json
```

The child-order helper SHA256 is
`d603f94ef71f3a972b0f0bdb5d984b225ff7d097572875403049502536cb9e8d`;
the permission helper SHA256 is
`620fce7c53d94ea963e2047d8cf33d3d4d1574cba49352b7cbf28ea30c94d96e`.
Framework325 is retained at
`/Users/alex/.local/state/vinix/android/maps-runtime325-framework-build-2026-10-25`,
manifest SHA256
`17df965baca0c030e1111a9b974410e9594b6e9ccfb814d371df6a53b0ead682`.
Its source-map SHA256 is
`5415b60509b4e3454800aed3a04dc7f41dc1fa68da078afd2ba7d848bc17dc9a`
and framework JAR SHA256 is
`181743124944671e934bc6003f6915511f3b43aabd060842e793309b8d988cfa`.
The consumed generator closure contains 138 sources: the permission helper
is added, `framework_classes.v` and the child-order helper change, and 135
existing sources remain byte-identical to322.
Independent review of the assembled DEX passed. Relative to322, only Activity
and ViewGroup change, VinixPermissionResult is added, 2,065 classes remain
identical and none are removed. Root independently checked the exact file
set and all 7,017 payload hashes; its receipt is
`/Users/alex/.local/state/vinix/android/maps-runtime325-root-readback-2026-10-25.json`.

The V-generated combined fixture checks inherited and super identity results
including positions outside the child-count range, override dispatch and
super bypass. It then checks normal asynchronous main-thread permission
results, literal grant/deny values and order, request codes, input cloning
under caller mutation, result-array independence, inherited base callback,
validation precedence, reentrant requests and three synchronous overlapping
cancellations. Trace variables and the location override must be absent.
The permission fixture SHA256 is
`b17e0cd2fd1fee86079eedaab108dfb300201baff54d0f9e0684eb192a0b63b0`;
the child-order fixture SHA256 is
`8b459596bdcd73b2f861d4dca43ee51eec550d2e867e2b91d8da83e80350bb43`.
Independent source and actual signed-APK DEX reviews passed. The prepared
paired APK contains byte-identical DEX to the independently reviewed host
APK: SHA256
`04fe415b7ccaa7bb7f252201266f756e2b8f41c62958051805ffc832b8c3a812`.
This equality proof is retained at
`/Users/alex/.local/state/vinix/android/child-permissions326-paired-dex-review-2026-10-25`,
manifest SHA256
`eb76ffed1474ad7ad0ce92a293908c96199ae1d2596927aad18ee23bc644eb7d`.

Paired guest regression326 passed using one signed APK, SHA256
`c82a1745233c9b4d911c93505bfc92e0a4590de669e3067de775f4a85c438415`.
Both runs retain Native315
`54a2fd873abd6be543b236b7c123a052e456ec7b8c823f9063751b880d9127ab`,
clean283 launcher
`406b187bb0ef8f42c57cc26532abae6599b837b5b0226da7afd23fcda8ca67a0`
and the same other runtime inputs. Only the framework JAR changes from322
`8f814c91a597f4c4fee0adde46789d144b4256586fc7816e0a60c2f3d661d7c8`
to325. The fixture and runner sources match their frozen copies; runner
SHA256 is
`3699e0b5f394fa552e2e1a634ab14533d2cf19dc1548909684a54eb227784a8a`.

On322, the fixture catches the exact missing child-order method and continues
to the permission request. Its asynchronous deadline then reports
`java.lang.AssertionError: requestPermissions did not deliver callback`
and exits with code1. The strict old semantic check passes with no success
groups or READY; raw classification is `startup_failed` with the process
exited. On325, all five child markers and eleven permission markers appear
exactly once in order, followed by the combined PASS and READY. Raw
classification is `window_observed`, backend ready, process still alive and
no failure markers. Independent review of both raw serial logs and semantic
receipts passed. Both suite jobs exited successfully and stopped their guests.

The complete paired bundle is retained at
`/Users/alex/.local/state/vinix/android/child-permissions326-fixture-2026-10-25`,
manifest SHA256
`65a5460fd7538c73c48fcf3f1caffde3e379ee3933cd59509b3e73093c64f77f`.
It contains `run-old/results.json`, `run-new/results.json`, each run's
`bootstrap-fixture/serial.log`, strict semantic checks, suite receipts and
frozen tools and sources. Old raw-results/serial SHA256 values are
`c52941481eda84296a9afc14a25fac901285bf3b6b32935c3f2b2016b5d90bb2` /
`699f0016d3e68c9e323cfa398ab83bbbf6e2faf5525e051935d261514f4f2cbd`;
new values are
`74346323424213b2462b79b961a95f3336774260debae3db4ad972e7cbd1372d` /
`6c98502dbf17b155118556dc7c51d9f4ae6a96fd23cd76e571689063c6ab8e89`.
Root independently checked the exact file set and all 729 payload hashes:
`/Users/alex/.local/state/vinix/android/child-permissions326-root-readback-2026-10-25.json`.
Recheck the complete retained bundle with assertions enabled and a fresh
receipt outside it:

```sh
VROOT=/Users/alex/code/v build/android-maps/queue284-tools/v_old276 -o /tmp/build-bundle-check tests/native-android-ws/build-bundle-check.v
/tmp/build-bundle-check /Users/alex/.local/state/vinix/android/child-permissions326-fixture-2026-10-25 65a5460fd7538c73c48fcf3f1caffde3e379ee3933cd59509b3e73093c64f77f /tmp/child-permissions326-fresh.json
```

This regression qualifies the framework contracts above. Maps replay327 is
separate; no Maps success is qualified here.
