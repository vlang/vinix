# TtsSpan support for Maps text metadata

Android source baseline: `1292bc867` (stateful nine-patch tint). Maps317 reached
Paris suggestions, then failed in `agdh.f(:20)` when allocating
`android.text.style.TtsSpan`, before allocating its argument bundle. Its next
required call is the missing `PersistableBundle(int)` constructor. The Maps
APK SHA256 remains
`6218d72f48b184eb71f68879bce48cb9ebb2b510be7f7cff88217ea3fd592bb2`.
The complete failed replay is retained at
`/Users/alex/.local/state/vinix/android/maps317-2026-10-25`, manifest SHA256
`7d7ad98af1170fed5e1b20b147fef5f1a1b540803966833c7a696f60224593d2`.

All ten original Maps DEX method tables contain exactly five TtsSpan method
references: the direct `(String, PersistableBundle)` constructor and the
String constructors and inherited `build()` methods of TextBuilder and
VerbatimBuilder. The maintained sourceproof authenticates those references,
the exact failing method, and the old provider gaps against retained inputs.
Its complete bundle contains 55 payload files and is retained at
`/Users/alex/.local/state/vinix/android/tts-span-sourceproof318-v2-2026-10-25`,
manifest SHA256
`b85bb0720dd0d2a36994690ea91fd66d2d285482ac952fce980b4282b8ba673d`.
Root independent complete readback passed all 55 payload files; the receipt is
`/Users/alex/.local/state/vinix/android/tts-span-sourceproof318-v2-root-readback.json`.

The generic implementation stores the supplied type and argument bundle by
reference. Builder results share their builder's mutable arguments, including
String, int and long arguments. TextBuilder and VerbatimBuilder inherit
SemioticClassBuilder and preserve the authentic erased fluent return types.
TtsSpan supplies span type 24 and writes type before arguments when parceling.
The capacity constructor treats nonpositive values as an ordinary empty map.
These contracts follow immutable
[AOSP TtsSpan](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/1cdfff555f4a21f71ccc978290e2e212e2f8b168/core/java/android/text/style/TtsSpan.java)
and [BaseBundle](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/1cdfff555f4a21f71ccc978290e2e212e2f8b168/core/java/android/os/BaseBundle.java)
at revision `1cdfff555f4a21f71ccc978290e2e212e2f8b168`. Parcel methods reuse
the framework's existing Bundle map codec, including its null marker. This
change does not qualify nested persistable bundles, add TextUtils span parcel
dispatch, or establish Android's external Parcel wire compatibility.

The production helper SHA256 is
`f294cf9f11439873b3ca4edb6cb21ac0ee2ff5edf1548f0765299be38d1ff2ed`.
Formatting, V checking and independent contract/register/access review passed.
Framework318-v2 is built from exact sealed315-v2 sources with only the helper
and its registration added. Its frozen source-map SHA256 is
`9f720f4ae4aae45273ecde30372f707d239b31540f37bde268b62f071c6b9a4a`.
Actual assembled DEX comparison finds exactly five added classes (TtsSpan,
Builder, SemioticClassBuilder, TextBuilder and VerbatimBuilder), changes to
Parcel and PersistableBundle, and 2,060 unchanged classes, with none removed.
Independent review of the emitted methods passed. The complete bundle is
`/Users/alex/.local/state/vinix/android/tts-span318-v2-framework-build-2026-10-25`,
manifest SHA256
`869d22f75a01c7ffd88604a04a73b67cc012daca9651a571e5eab30aafd0594c`.
Root independent complete readback passed all 7,008 payload files; the receipt
is `/Users/alex/.local/state/vinix/android/tts-span318-v2-framework-root-readback.json`.
Framework JAR SHA256 is
`6b826b2b7c37eb6b101d2627854064d1d06988f7c8bbdf1b94c1dea012e86b5d`.

The paired fixture uses the same signed APK, SHA256
`8a7eb2d883f84fc29b8cd04f07cf093d6dcda3299b10d24410e231e1df507df1`,
and common Native315, clean283 launcher and runtime/media inputs; only the
framework JAR changes. Native library SHA256 remains
`54a2fd873abd6be543b236b7c123a052e456ec7b8c823f9063751b880d9127ab`.
Its checks cover the exact Maps allocation order, aliasing, builder mutation
and long arguments, direct parcel layout in both directions, null and empty bundles,
nonpositive capacity, and typed span storage and removal. The initial318 and
319 working freezes were superseded before any guest run and remain
unqualified. The source checkout at freeze was
`f3ffd46665f1a5a2687fab6a9bab9cb51472b507`; consumed sources are pinned in the
retained source maps.

Paired guest regression319-v2 passed. The old315-v2 variant fails at the
first TtsSpan allocation with the exact NoClassDefFoundError and
ClassNotFoundException cause, before any later test. The new318-v2 variant
passes MAPS, CORE, BUILDERS, PARCEL-WRITE, PARCEL-READ, PARCEL-NULL,
PARCEL-EMPTY and SPANS in order, then final PASS and READY. The unchanged
historical classifier records `startup_failed` for the expected old failure
and `window_observed` for the fixed variant; semantic verdicts are recorded
separately. Independent runtime review of both variants passed, and root
reviewed the serial output and normal fixture window. Both guests stopped
before sealing. The complete bundle is
`/Users/alex/.local/state/vinix/android/tts-span319-v2-fixture-2026-10-25`,
manifest SHA256
`b293ffbdba4571658605e0fac2ddd3c5a91847b5d8e0f07bed3819b07197d42a`.
Root independent complete readback passed all 595 payload files; the receipt is
`/Users/alex/.local/state/vinix/android/tts-span319-v2-root-readback.json`.

The real Maps320 replay is still pending. Generic fixture success alone does
not establish route completion or visible switch tint in Maps.
