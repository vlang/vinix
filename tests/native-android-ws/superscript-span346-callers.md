# Maps345 SuperscriptSpan caller contract

Investigation baseline: `8c4b711aecfddfe939eb345b348115bce84cc681`.
Actual Maps APK SHA256:
`6218d72f48b184eb71f68879bce48cb9ebb2b510be7f7cff88217ea3fd592bb2`.
This is an app dependency analysis, not qualification of Framework346.

Maps345 fails with `NoClassDefFoundError: SuperscriptSpan` at
`serial.log:232231`: `ashh.<clinit>:61` → `ashh.a:1` → `atze.a:758` →
`bgzb.h:13`. The log is under
`/Users/alex/.local/state/vinix/android/maps345-2026-10-25/results/attempt345/google-maps/`.
The following JNI warning says an exception was thrown while printing the
stack trace; the APK exits with code1. The first retained class failure is
the SuperscriptSpan resolution in the static initializer.

The actual `ashh.<clinit>` performs these operations:

1. Construct a SpannableStringBuilder and append the literal `"*"`.
2. Construct `android.text.style.SuperscriptSpan` with `<init>()V`
   (`ashh.smali:145`, `:149`).
3. Apply it over `[0, builder.length())`, which is `[0,1)`, with flags `0x21`
   through `SpannableStringBuilder.setSpan(Object,III)V` (`ashh.smali:166`).
4. Copy the builder into a SpannableString and store it in static field
   `ashh.f` (`ashh.smali:175`, `:180`).

This is the only `android.text.style` reference in the selected `ashh`,
`atze` and `bgzb` classes. No SubscriptSpan, other span constructor,
SuperscriptSpan getter, direct paint-update call or parcel API occurs there.
That bounds the direct app dependency; a provider still needs its framework
span contract.

`atze.a` calls `ashh.a` while constructing a `bhcn` UI description
(`atze.smali:1581`). Class initialization occurs before that call returns,
regardless of whether this UI later displays the static marker. The marker
is separately passed as a CharSequence to `besn.da` in `ashh.c`
(`ashh.smali:714`). This failure therefore establishes a missing class
during UI construction, without establishing a rendered superscript defect.

The [recorded selector](maps-attractions-select.v) and its
[retained build/origin](maps-attractions-binding337.md) selected exactly
`ashh`, `atze` and `bgzb` into the fresh external bundle:

`/Users/alex/.local/state/vinix/android/superscript-span346-actual-selected-2026-10-25`

Manifest SHA256:
`cf490ae280efff09723420aeb0d5a5fee41b130a354d98b4ab062984a6e47cfa`.
The unchanged complete checker290 verified the exact 36-file set and every
hash. Sibling receipt:
`superscript-span346-actual-selected-readback-2026-10-25.json`.
No framework mutation, guest input or QMP was used for this inspection.
