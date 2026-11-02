# Secure string writes and the API 28 tile request

`Settings.Secure.putString(ContentResolver,String,String)` now forwards exactly
two String entries, `name` and `value`, to the resolver's virtual `insert` at
`Secure.CONTENT_URI`. Null names and values are passed unchanged. A nonnull
returned URI means success; null or `SQLException` means false. A null resolver
still throws, and provider `SecurityException`, argument errors and other
runtime exceptions propagate unchanged. The provider owns permission checks,
replacement and persistence; no settings store or write grant is added.

This is the same registered-authority adaptation as the existing
[Global integer writer](../native-android-ws/settings-global.md). The runtime
resolver uses null when no provider exists, so the new method explicitly checks
it. Legacy AOSP's insertion helper instead returns true if insertion does not
throw; modern Secure uses NameValueCache and provider calls. This change does
not claim either implementation's byte-equivalence, moved-key routing or full
NameValueCache behavior. The observed GMS key is `nearby_sharing_component`;
the caller ignores the boolean result.

The next applicable initialization path requests tile listening. The new
TileService follows the
[API 28 broadcast request](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android-9.0.0_r3/core/java/android/service/quicksettings/TileService.java#L417):
it creates `android.service.quicksettings.action.REQUEST_LISTENING`, stores the
actual nullable component as a Parcelable under `android.intent.extra.COMPONENT_NAME`,
targets `com.android.systemui`, and calls the two-argument broadcast overload
with `android.permission.BIND_QUICK_SETTINGS_TILE`. A null Context throws at
that virtual call. The concrete Service subclass also has its normal constructor
and returns no binder from `onBind`, reflecting the absent Quick Settings
backend. It adds no tile callbacks, tile object or SystemUI implementation and
claims no successful listening state.

The final scope is one appended Secure method and one new three-method,
fieldless TileService class. All ten old Secure methods and all its metadata
are preserved. UserManager, ContextImpl, StatusBarManager and native-consumed
classes remain unchanged. Earlier provisional API 33 alternatives were never
compiled and are retained outside Git at
`/Users/alex/.local/state/vinix/android/secure-settings-provisional-api33-2026-11-02-r1`.
The retained native bundle still needs the complete successor equality audit;
this focused check does not substitute for it.

Focused checks passed on their first attempt: fifteen malformed/schema/helper
collision refusals, sixteen independent method/route controls, API-28 assembly
and two DEX roundtrips. They bind typed catch type, protected instruction span
and handler target while allowing canonical catch placement and label aliases.
Explicit controls reject altered spans/handlers. They also preserve every old
member and require the exact tile action, target package, Parcelable component,
permission-qualified call, Service superclass and null binder. Canonical second
DEX bytes are stable. Independent provider, checker and driver review approved.

Evidence is outside Git at
`/Users/alex/.local/state/vinix/android/secure-settings-source-check-2026-11-02-r1`.
It retains frozen sources, generated C, input pins, guarded commands, original
and patched DEX and both roundtrips. Proof receipt SHA-256 is
`b29121cbe5c268a26b39a1ee6dee789363855201d4182e16c86a85ae6bf4f77c`.
Source parent before this commit is `46ed43fd6ff4eef324dd708cc9ec1bd29e374944`.
Secure/Tile provider hashes are
`dea6f0cdfeaaee7b717fa2a4d8602336e7af67e419ac9af17ab9dfd9756fb03c`
and `87b5c5cb651d21ec0e4f356e924a2685971effe46db742b9359642b138092949`.
The integration, driver and checker hashes are respectively
`d4df92e7ca05be5859dc4de38aa89e03accd7dbebe968b3ac2969d1f92540e76`,
`d3c237a4e9a9aca6144c2821e6dfc450fb71ad79a2b1c3187ab021845c04e10f`
and `961c91bc54a7c893ed84542a4227539452d8b806cbc7e8be606da7e95c928885`.

The focused run took 6.555 guard seconds, sampled 239,124,480 bytes aggregate
RSS and recorded 176,668,672 bytes detailed RSS. Compiler sampled/detailed
maxima were 246,136,832/278,249,472 bytes. All guards and children exited zero,
with complete cleanup and zero swaps under the original 600 MiB RSS,
300-second, 512 MiB shared-growth, 1 GiB reserve, 4 MiB output and file cap
16777216 limits. Full SDK, native equality, ARM and live GMS/Maps checks remain
separate; host checks establish no authentication or imagery result.
