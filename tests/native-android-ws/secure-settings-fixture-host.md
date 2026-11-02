# Secure settings and API-28 tile request fixture

The signed standalone fixture contains four application classes: Main,
SettingsResolver, RecordingContext and TileAdapter. It declares minSdk 28 and
supplies no platform class, settings provider, write grant or SystemUI service.
Its actual Settings.Secure.putString calls test the narrow Vinix provider
adaptation already used by Global writes; this is not a claim of complete
legacy or modern AOSP Settings behavior.

The recording resolver checks one virtual insert per call, the actual
Secure.CONTENT_URI object and canonical URI text, exactly two ContentValues
entries named `name` and `value`, and exact String or explicit null payloads.
Cases include the audited `nearby_sharing_component` key with
`com.google.android.gms/com.google.android.gms.nearby.sharing.main.MainActivity`,
its empty clear value, null name/value, empty names and repeated keys. Thirteen
recording inserts cover nonnull URI true, null URI false, SQLException false,
exact SecurityException/IllegalArgumentException/NullPointerException identity,
and recovery after exceptions. Two real Activity/application resolver calls
require false without a settings provider; a null resolver must throw NPE.
Reflection checks the public static primitive-boolean descriptor. Existing
unknown String/default-int, known-int and getUriFor behavior is checked before
and after writes as preservation of existing fallbacks, without claiming
persistence or read-after-write support.

TileService checks use the API-28 listening-request broadcast contract. A
RecordingContext overrides the real two-argument sendBroadcast method and
checks five dispatches: exact REQUEST_LISTENING action, `com.android.systemui`
package, one explicitly present Parcelable COMPONENT_NAME extra, identical
component or null, BIND_QUICK_SETTINGS_TILE permission, a fresh Intent each
time, preserved component state and the original broadcast exception. Real
Activity/application calls are smoke returns only; they do not assert callback
absence. Reflection verifies a public static final void request on a Service
subclass, and actual base/adapter constructors and null onBind results are
exercised. The loaded TileAdapter resolves the inherited static request while
retaining a dormant getQsTile/Tile-return reference. The fixture supplies no
Tile stub and invokes no dormant callback path.

The final scope follows the source-derived SDK 28 path of the pinned APK and
bootstrap. Provisional SDK-33 user/statusbar controls were removed before any
fixture build. Their complete source copies remain externally in
`S/secure-settings-fixture-provisional-sdk33-2026-11-02-r1`, with main/source
hashes `529fec7a41a5ebab2aafeba640b253c94a9f0987a492b55219fee1770422acc2`
and `031f2d444b12ad6816d21ef6d31d44260d8ad9062bac59fc2367b5e7d705b9af`.
No SDK override or provisional framework API is required by the final fixture.

The V builder and signed production passed on their first attempts. Host
checks cover the complete frozen source/tool closure, API-28 assembly, two
canonical disassemblies around reassembly, equality and exact membership of
all four classes, source-bound invocation assertions, v3 signature and exact
signed DEX extraction. Independent source and register/exception-flow review
passed before compilation. All original inputs were rehashed at completion.
Host checks do not establish ART verification or execution of the assertions;
the ARM run remains separate.

Paths use `S=/Users/alex/.local/state/vinix/android`. The complete fixture root is
`S/secure-settings-fixture-2026-11-02-r1`; build logs, guards and the executable
builder are in `S/secure-settings-fixture-controls-2026-11-02-r1`.
The immutable build records source revision
`46ed43fd6ff4eef324dd708cc9ec1bd29e374944` and the exact current/frozen generator
hashes `8b5a2c64dcd78164520f1e57e6b85f09b0d55804fb8bf5e8eed1a590527d17d7`
and `fd73bb093976a40609bc8d27a5b661c7517a2d888b2ece653c5d01dd37794d6e`.

| Artifact | SHA-256 |
| --- | --- |
| Signed probe.apk | `1e2628151f851619bbae164f0c3a6830c354d11fe3f2104e584afe39482ccdd8` |
| Build receipt | `fdd8eacd953d3b125dd6087e4a2c5a28e3a84585fadb496ded23d4891a58e9fe` |
| Production, signed-extracted and roundtrip DEX | `d81a94b09677a3b70d3d028b7a7af69a558735da5504b7cbff4e86ca6a1cb549` |
| Both canonical Main classes | `90506d07b15d5e72bed92f79430e3efd74cf1e81290d77900be8ccb5118d68a6` |
| Both canonical TileAdapter classes | `aefe493285b5adbe9cccd1700f8149dd082b4eb579ef2403502417ba6378115e` |

Compile and production guard/child exits were zero with empty reasons and
complete cleanup. Compile elapsed 1.265 seconds, sampled RSS 354,353,152 bytes,
detailed maximum 365,297,664 bytes and observed growth 1,355,776 bytes.
Production elapsed 5.697 seconds, sampled RSS 98,385,920 bytes, detailed maximum
96,059,392 bytes and growth 1,286,144 bytes. Both report zero swaps. Limits stayed
600 MiB aggregate RSS, 300 seconds, 512 MiB observed growth, 1 GiB reserve,
4 MiB output and shell file cap 16777216. The compiler lane was released after
actual completion. The terminal marker is:

```text
SECURE-SETTINGS-PASS public-static virtual-insert secure-uri exact-string-null-values nearby-component empty-clear provider-result SQLException narrow-exceptions null-resolver absent-provider preserved-getters tile-broadcast intent-payload nullable-component fresh-intents inherited-static
```

This fixture establishes no SystemUI delivery, Quick Settings backend or tile
callback behavior, Android settings persistence, permission grant, account
authentication or Maps success.
