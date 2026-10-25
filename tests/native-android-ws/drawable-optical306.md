# Drawable optical insets for Maps Route Options

Source baseline: `583ed3554` (Maps hints and ripple radius). Evidence is retained
under `/Users/alex/.local/state/vinix/android/` outside Git.

Maps304 reaches Paris search and both driving and walking routes, but opening
Route Options exits the app during `SwitchCompat.onMeasure` with
`NoSuchMethodError: Drawable.getOpticalInsets()Landroid/graphics/Insets;`.
The sealed failure bundle is `maps304-2026-10-25`, manifest SHA256
`0575e5e50abb3a6d5228e6137bb99c0401c4639a934298e44e9a658f7c1458c2`.

Drawable now exposes a public, overridable `getOpticalInsets()` returning the
existing immutable `Insets.NONE`, matching the default in
[Android 11 Drawable](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android-11.0.0_r1/graphics/java/android/graphics/drawable/Drawable.java).
The result is independent of padding, bounds and drawable state. The change
adds no native state or allocations. Subclasses retain virtual dispatch.

The V-generated regression APK calls the exact base descriptor first. Its
assertions cover inherited zero edges, shared identity across instances,
independence from nonzero padding and state changes, public virtual modifiers,
overridden nonzero edges, `invoke-super`, and calculations using all four edges.
It independently rejects trace environment variables. The same signed APK
runs against old and changed frameworks with the native library held constant.

Framework306 preserves all sealed302 framework generators except the one-line
registration and the new helper. Its builder checks the consumed source
closure and compares actual disassembled DEX, requiring Drawable to be the
only changed class with no added or removed classes. Native302 is reused.

Framework build: `drawable-optical306-framework-build-2026-10-25`, manifest
SHA256 `392477ecf7d7b8d3b87fb13940b2e4f8fb3daf4229e05df7790bfbb59ab7f469`;
JAR SHA256 `e8ac1183a63e63ef10e3bbd9cbec0b77a59b5f06ce1df2e1fc2de5e917a6ebee`.
Independent complete readback passed all 6,968 regular files. Actual DEX
comparison changed only `android/graphics/drawable/Drawable.smali`, with no
added or removed classes. The unchanged native library SHA256 is
`f31fb4916ef7983aabcfb03ad0f21ffb7d84cf7cd433cd6c3568ce75def82f7e`.

Guest comparison307: `drawable-optical307-fixture-2026-10-25`, manifest SHA256
`59b99710df71f3b57e6049d941ae13a13b6e607c8446b2b6ab7868cd221c7ce3`.
The runner and independent complete readback verified all 595 regular files.
Both variants consumed the same
signed APK, SHA256
`a56e0002fbd8ddc65ae68e9d147ef1ae13fc2bd8d9c1bc2097cea78eda9cd9ea`,
and unchanged Native302 and clean283 launcher. Framework302 reproduced the
exact uncaught missing-getter exception; its raw `startup_failed` result is
the expected baseline failure. Framework306 emitted DEFAULT, DISPATCH, final
PASS and READY exactly once; its raw result is `window_observed`. Semantic
assertions and the unchanged suite's startup classifier remain separate.
The APK checked trace environment variables were absent before either call.

The consumed checked runner SHA256 is
`3f3219c28ee871ac8eb67b3dc4c6ce70bbc59c249fd8e21461fd2fff7a53ec5e`;
old serial SHA256
`cc44724da992d0089c38adafef4e755456624fb180f5128bab0b89bb28d64fe2`;
new serial SHA256
`9c44aca8ca0f408c681fda463cf4371cd6d35123f920f9a0083b1cf8a9b75f61`.

The V cleanup tool authenticated redundant Maps300/304 working copies against
their complete sealed inventories before removal. Their sealed bundles remain
complete and unchanged. Three late failed-capture receipts and the exact
original consumed cleanup source and binary are preserved in
`maps300-304-working-cleanup-2026-10-25`; supplementary typed manifest SHA256
`cde9d3a2f8682c487c57e7428c0c9babdfd1f17ef729bfbf528c2944c1aaa015`
verified all 24 entries. The final cleanup source additionally rejects
assertion-disabled production builds; that build was verified to fail before
argument handling. No cleanup was rerun after preservation.
