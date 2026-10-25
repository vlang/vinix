# Stateful nine-patch tint for Maps switches

Android source baseline: `b9a8d76e4` (labelled Maps routes and preview replay).
Maps314 showed moving circular switch thumbs, but their tracks and checked
colors were too faint to qualify. The exact312 NinePatchDrawable inherited
no-op tint-list/filter methods and reported `isStateful() == false`. Its
inherited draw path passed no Paint to the bitmap renderer. Its direct
`setTint(int)` also called an unbound native method.

NinePatchDrawable now resolves tint from its ColorStateList and state, keeps
a Paint per drawable, and draws through that Paint into the selected Canvas.
It supports alpha, explicit color filters, solid tint, tint-list/mode clearing
and state changes. Explicit Paint filters take precedence over tint; temporary
tint is removed after normal and exceptional draws. Shared bitmap pixels and
ownership remain unchanged. Only the existing SRC_IN backend behavior is
qualified; other blend modes, density scaling and nine-patch stretch regions
are outside this change. State changes return true when the effective tint
filter changes, rather than for every distinct state array.

The maintained sourceproof locates SwitchCompat in the actual Maps
`classes3.dex`, verifies both thumb/track tint calls and stateful gates, and
authenticates the exact312 provider gaps. This establishes the API path; it
does not establish the drawable class selected by Maps' runtime resources.
The primary [AOSP NinePatchDrawable source](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/1cdfff555f4a21f71ccc978290e2e212e2f8b168/graphics/java/android/graphics/drawable/NinePatchDrawable.java)
documents filter precedence, stateful tint and Paint alpha behavior. The
complete sourceproof is retained at
`/Users/alex/.local/state/vinix/android/nine-patch-tint-sourceproof315-qualified-2026-10-25`,
manifest SHA256
`3fc905f97a238bd3916840b8ee4ec3ac3e172117d59ed29a1049ffd16169740b`.
Independent complete readback passed all 44 files. AOSP source SHA256 is
`69660de167a635166c1ea1145c54c4eb4c824bb84b92b697b029c269c110258c`.
The Maps APK remains
`6218d72f48b184eb71f68879bce48cb9ebb2b510be7f7cff88217ea3fd592bb2`.

Framework315-v2 builds from the sealed312 source closure, changing one helper
registration and adding the tint helper. Actual assembled DEX comparison finds
only NinePatchDrawable changed; all other 2,061 classes are identical, with
none added or removed. Independent ABI review checked the emitted register
range, Canvas normalization, public bounds access and exception cleanup.
The complete bundle is
`/Users/alex/.local/state/vinix/android/nine-patch-tint315-v2-framework-build-2026-10-25`,
manifest SHA256
`630cd5f07509553f86fead29c998be2678dc5bbc94e5ab44f4706d3b213f5f56`.
Independent complete readback passed all 6,996 files. Framework JAR SHA256 is
`1e9ebbe318ae030ed22f06bc99553872fa43d820e0981d143586304560161cc6`.
The earlier incomplete working freeze at
`build/android-maps/nine-patch-tint315-framework` is preserved, was corrected
before any framework build and is not qualified evidence.

Native315 preserves all 85 sealed312 sources except for one appended draw
wrapper in the generated JNI file. Actual ELF inspection verifies exactly one
new JNI export, increasing 606 to 607. The binding selects the Canvas, passes
the drawable's Paint to the existing renderer, and restores Canvas state on
normal and pending-exception paths. Generated V/C ABI review and strict native
compilation (`-O2 -Wall -Wextra -Werror`) passed. The complete bundle is
`/Users/alex/.local/state/vinix/android/nine-patch-tint315-native-build-2026-10-25`,
manifest SHA256
`09c2c82ff7feb169733c7f77fc11683f409b2114e409fe9e70a8346c277d5aee`.
Independent complete readback passed all 2,402 files. Native library SHA256 is
`54a2fd873abd6be543b236b7c123a052e456ec7b8c823f9063751b880d9127ab`.

The V-generated fixture uses aapt2-compiled nine-patch resources and checks
default, checked and disabled colors against independent expected pixel
values. It exercises explicit filters through both Drawable and getPaint,
filter/list/mode clearing, solid tint, null-Canvas exception recovery, alpha
round trips and multiplication of source, filter and Paint alpha. Two
drawables sharing a bitmap retain separate tint and leave source pixels
unchanged. Bitmap-Canvas checks include nonzero bounds and transparent pixels
outside every edge; the final normal View draws two independently checked
84-by-60 color regions. The host PNG checker verifies CRCs, PNG filtering,
exact colors, counts and bounds. Formatting, V compilation, APK assembly and
signature verification passed, with independent production/fixture review.

Paired guest regression316 passed against the same signed APK, SHA256
`9b7e70c2efb176151d032dd9c54c3c24e9f484136189c2d4c7cf86421503c1ac`.
Both variants use the clean283 launcher and identical runtime/media inputs;
only the framework JAR and native library change from312 to315. Trace
variables are absent. The old variant fails exactly at `stateful tint reports
stateful actual=0 expected=1`, before reaching later checks. The fixed variant
passes STATEFUL, COLORS, FILTER, ALPHA, ISOLATION, CANVAS and DRAW, plus final
PASS and READY. The unchanged historical classifier records `startup_failed`
for the expected old failure and `window_observed` for the fixed variant;
semantic verdicts are recorded separately.

Independent framebuffer decoding found exactly 5,040 opaque blue pixels
(`#2471c4`) at inclusive bounds `[144,190,227,249]` and 5,040 opaque red pixels
(`#e53935`) at `[228,190,311,249]`. Retained screenshot SHA256 is
`711a917d7eb28c8f1ff2b9e1c58785a7d77c1f3dc8d5dd49fd2392fabe8dd99c`.
Both guests stopped before sealing. The complete 620-file bundle is
`/Users/alex/.local/state/vinix/android/nine-patch-tint316-fixture-2026-10-25`,
manifest SHA256
`e75336f72da4e4613b13876de58098425deadafbfb967874609d57e807197e20`.
Root independent complete readback passed all 620 files; its receipt is
`/Users/alex/.local/state/vinix/android/nine-patch-tint316-root-readback.json`.
