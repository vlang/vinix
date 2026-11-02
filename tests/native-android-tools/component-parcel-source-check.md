# ComponentName parcel prerequisite

The Messenger ARM fixture reached `Parcel.readParcelable` with a ComponentName
object, then failed with `BadParcelableException` caused by missing `CREATOR`.
ComponentName already declared Parcelable but inherited its empty writer.

The added contract follows [API 28 ComponentName](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android-9.0.0_r3/core/java/android/content/ComponentName.java#L304):
the instance writer emits package then class. The public Parcel constructor and
creator reject a null package before reading class, then reject a null class,
using the original exception messages. The nullable static writer emits one
null string for null, otherwise delegates with flags zero. Its reader returns
null after one null package string; otherwise it uses the private String/Parcel
constructor, which deliberately accepts a null class. Null Parcel arguments
fail naturally. These distinct paths retain the original cursor behavior.

The generator appends six methods and the public static final CREATOR field,
plus one fieldless three-method creator class. All 23 existing methods, both
private final fields and other metadata remain unchanged. The wrapper validates
the complete input and creator collision before either write. ComponentName is
outside the 70 native-consumed classes; manual native calls use preserved
constructors/getters. Messenger, Message, Handler, Binder, Parcel and the Intent
codec are unchanged. Full SDK/native equality remains a deployment check.

Focused qualification passed on its first attempt: 16 malformed/collision
refusals before writes, 19 independent semantic controls, API-28 baseline and
patched assembly, and two DEX roundtrips with stable second-roundtrip bytes.
Controls reject changed wire order, premature/extra reads, null validation,
private-versus-public constructor selection, flags, creator array type, old
method changes and metadata changes. Provider, checker, driver and integration
received an independent review. The original Messenger APK will be reused
unchanged for ARM validation; these host results establish no ARM or Maps result.

Evidence: `/Users/alex/.local/state/vinix/android/component-parcel-source-check-2026-11-02-r1`,
with frozen sources, generated C, input pins, guarded receipts and both DEX
roundtrips. Proof receipt SHA-256:
`909d550e3587a5719f1f377fe53fb3ed990b810c5f516e5ab7b075318b60f213`.
Recorded proof source parent: `55e59bb4209c228e566937705f6b37a0e3fd8c39`.
Parent Messenger SDK manifest/JAR SHA-256:
`e3d313ae3e51404da203344ef1a6db32a4aaf24fe01ac971a71fd69ae586aa85` /
`ddeeb613e7767cbfb3e2bf3818ff02f8f9ab10918f26868dba8047a2cc539129`.

All guards/children exited zero with complete cleanup and zero swaps. Proof
took 7.231 seconds, sampled 256,425,984 bytes aggregate RSS and recorded
177,045,504 bytes detailed RSS. Split compiler sampled/detailed maxima were
257,015,808/278,839,296 bytes. Original limits remain 600 MiB RSS, 300 seconds,
512 MiB observed shared-volume growth, 1 GiB reserve, 4 MiB output and file cap
16777216.
