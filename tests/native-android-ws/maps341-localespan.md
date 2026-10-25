# Maps341 place-row LocaleSpan dependency

Investigation baseline: `4f1aba209296c9ef6642ba26053a28025f241c7d`.
The actual Maps APK is SHA256
`6218d72f48b184eb71f68879bce48cb9ebb2b510be7f7cff88217ea3fd592bb2`.
This records app callsites; it does not qualify a framework fix or another run.

Maps341's place-row click fails with `NoClassDefFoundError: LocaleSpan` at
`serial.log:15969`, from `batc.z:221` → `batc.A:85` → `atwo.x:301` →
`atwo.v` → `atwo.w` → `atwu.a`. The log is under
`/Users/alex/.local/state/vinix/android/maps341-2026-10-25/results/attempt341/google-maps/`.

The selected actual DEX establishes this exact requirement:

- `batc.smali:4102` constructs `android.text.style.LocaleSpan`.
- `batc.smali:4106` invokes `<init>(Ljava/util/Locale;)V`.
- The locale comes from an optional `bann.b()` result, `banv.a()` and its
  `cbue.c` language-tag string, parsed by `Locale.forLanguageTag`.
- With a nonnull locale and `baob` text, the app wraps `baob.b()` in a
  `SpannableString` and applies the span over `[0, text.length())` with flags
  `0x11` (`batc.smali:4127`). It then may append supplementary text and wrap
  the result in a `SpannedString`.

No LocaleSpan getter, LocaleList constructor, parcel API, or explicit cast to
CharacterStyle occurs in these three selected caller classes. That bounds
the direct app dependency; it does not replace the framework span contract.

The later span construction in the same `batc.z` method is `StyleSpan(I)`
for highlighted text ranges (`batc.smali:4585`). Other methods in `batc`
construct `UnderlineSpan()` and `ForegroundColorSpan(I)`. Their exact
constructors already exist in sealed Framework338's `framework/new-dex/`.
`atwo` and `atwu` contain no direct `android.text.style` references. This
bounded inspection establishes no additional missing adjacent span class.

The [recorded selector](maps-attractions-select.v) used the qualified315 DEX
origin and the retained build described in
[the earlier binding investigation](maps-attractions-binding337.md).
It selected only `batc`, `atwo` and `atwu` into the fresh external bundle:

`/Users/alex/.local/state/vinix/android/maps341-localespan-actual-selected-2026-10-25`

Its manifest SHA256 is
`fb2a1141a5c345c6124df0aad26cdabee7ee509c56e86f0328c570121ce52319`.
The unchanged complete checker290 verified its exact 36-file set and every
hash; sibling receipt:
`maps341-localespan-actual-selected-readback-2026-10-25.json`.
No guest input, QMP, or framework mutation was performed for this inspection.
