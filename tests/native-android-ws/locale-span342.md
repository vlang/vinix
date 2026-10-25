# LocaleSpan for Maps place names

The qualified old runtime is [framework338](vpa-translation-z338.md),
from source revision `7818102b4`,
API JAR SHA256
`df8601f61867c276559c1799957865ef51a65b4cb8b343b848f2fca6370f16a7`.
Maps341 displays Attractions content after that fix, then opening a place row
exits with `NoClassDefFoundError: android.text.style.LocaleSpan` at `batc.z`.
The [actual APK investigation](maps341-localespan.md) verifies the app calls
the Locale constructor and applies the span over the entire place name with
flags `0x11`.

The [provider](../native-android-tools/androidtools/framework_locale_span.v)
adds LocaleSpan as a MetricAffectingSpan and ParcelableSpan. It retains an
ordered LocaleList, exposes its first locale and whole list, and applies
the list through Paint's existing text-locale state for drawing and measuring.
A null Locale creates an empty list; a null LocaleList throws
NullPointerException. Applying an empty list follows Paint's existing
IllegalArgumentException behavior. ParcelableSpan is an empty interface in
this runtime, so LocaleSpan also explicitly implements Parcelable.

LocaleSpan's parcel constructor and writers use the legacy LocaleList
language-tag string representation directly. The existing LocaleList lacks
writeToParcel and its CREATOR returns null; these remain unchanged.
Current AOSP uses String8 methods absent from this compatibility baseline.
The [pinned official source proof](locale-span342-contract.md) verifies the
current API and Android 7/8 language-tag string wire format.
The implementation does not add shaping, locale-sensitive native glyph
fallback, or repair the existing LocaleList parcel API.

The [fixture](startupfixture/locale_span.v) constructs the class through the
actual Maps ABI, verifies the span range and flags, ordered script/region
locales, list identity, first-locale semantics, type id 23 and Parcelable
metadata. Both paint updates dispatch through MetricAffectingSpan, change
locale metadata and preserve size, density and color. Public and internal
writers round-trip singleton, ordered and empty lists; independent string
reads/writes check the wire representation and consumed data position.
Nullable Locale, empty LocaleList, null LocaleList and empty paint updates
exercise their distinct contracts.

The [runner](locale-span-run.v) derives its complete frozen V compiler,
support sources, C helpers, embedded inputs and third-party assets from
qualified338. Only the new provider, registry line, fixture and runner are
overlaid. Full framework DEX comparison requires exactly one added class,
LocaleSpan, and identical disassembly for all 2,068 existing classes.
The same signed two-class APK runs against guest runtime directories that
differ only in api-impl.jar. Reapplying the provider must reject without
modifying its output.

The actual frozen runner compiled 636 V inputs with identical input closure
before and after compilation. Both actual ART runs passed their semantic
checks. The old framework fails exactly once while resolving LocaleSpan,
with its matching ClassNotFoundException and the expected activity wrapper.
The fixed framework prints all four PASS markers and remains alive through
the 35-second observation window. Full DEX comparison confirms only
LocaleSpan was added; all existing classes are unchanged. The fixture does
not qualify the subsequent real Maps replay.

The external bundle is
`/Users/alex/.local/state/vinix/android/locale-span342-2026-10-25`.
Its `sha256.json` is
`a48ee29feb4c34adfc1558117cf3c3db4ce1d3cb95d5f22f1a5c0e13cdeaaf9a`.
The complete official source proof is retained in `official-contract`.
Both independent complete readbacks pass all 8,535 files with an exact
file set and every checksum matching. Their sibling receipts are
`locale-span342-complete-readback-2026-10-25.json` and
`locale-span342-root-readback-2026-10-25.json`. Artifact SHA256 values are:

- New API JAR: `79023bd51618bc54f069fe6fd85c812679a81f6db70268f78bca38053b2d1972`.
- Same signed APK: `c35b0541bc5f35144dc90d689daf2c088762a44cdf59a4a54182f7c6a5393676`.
- Executed frozen runner: `24cecf2119507b24f1d2cc9767a312bcc5f083403852dff035bad7844d448b74`.
- Old raw serial: `cc79f2ce8ac1118325d790ac286df20a3ea79e524fdb7ee84e8823a78da90e52`.
- Fixed raw serial: `78534977471527cd5526d728fe109195dc6c1e53a5382351f358a9f374bb3808`.

The bundle retains raw serial and metadata, signed APK and disassembly,
complete old/new framework disassembly, duplicate-provider rejection,
frozen compiler/support/assets, generated C and compiler input closure,
actual command records, and unchanged host/runtime input receipts. Two
bootstrap diagnostics occurred before the fresh external preparation; the
retained notes distinguish those uncaptured diagnostics from preserved
successful bootstrap/build logs. The external preparation succeeded on its
first attempt.
