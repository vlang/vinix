# GMS phenotype API audit

The recorded `bnyc.a -> bpcw.a` configuration path was inspected from the exact
GMS 26.41.31 APK (`a34d6a3ccea3ceba491369517e8f12e11df3791e86fec38b1cdf693785e35707`),
against the qualified stable-display SDK JAR
`3b51a6cfe506db8e87908fdf74fcaebd585aaace383e8880a0183cd901780e52`
and its frozen native binding snapshot. Six selected classes cover bpcw,
bnyc, immediate configuration helpers and the exact FeatureInfo outline.
Retained unique class-owner inventories and immutable DEX inputs were reused;
no APK patch or broad speculative implementation was needed.

The currently observed failure is `AssetManager.getLocales()[Ljava/lang/String;`
at code offset `0x2fb`, source line 764: the method is declared native but lacks
a deployed binding. It follows `Context.getAssets()` at `0x2f7`. GMS sorts the
returned array and collects its nonempty strings. No additional AssetManager
locale, configuration or cookie API occurs in this method or its inspected
helpers. A later required call at `0x4ea` targets the absent Java method
`KeyguardManager.isDeviceSecure()Z`, after checking its service is nonnull.
These two causal gaps define the next implementation batch.

The conditional GL-extension probe is already linked. It runs when the cached
extensions string is empty or the build-change flag is true. EGL10 dispatches
to the bound EGLImpl methods for display/init/config enumeration/config
attributes/context/pbuffer/current/destroy/terminate. GLES10 inherits
`glGetString(I)String` from GLES20, which has a native binding. Other direct
framework queries inspected here, including ActivityManager configuration,
memory and low-RAM queries, SystemProperties, SharedPreferencesImpl, and the
adjacent conditional UserManager.isSystemUser query, exist as Java SDK methods.
This finding establishes linkage presence, not API or graphics correctness.

The direct FeatureInfo outline reads the absent `version:I` field, but only
while processing named feature entries. The current PackageManager returns an
empty feature array, bypassing that branch. This conditional gap is recorded
without changing feature reporting. Optional DisplayMetrics stable-density
reflection catches missing-field/access errors. OEM key2 property lookup is
behind a GMS Boolean flag and uses an existing Java method. GMS flags/proto
helpers and unrelated call paths were not recursively audited.

Complete selected Smali with offsets/source lines, exact ABI/control-flow
notes, the SDK/native read set, input/tool pins, guarded argv and detailed logs
are at
`/Users/alex/.local/state/vinix/android/gms-phenotype-native-path-audit-2026-11-02-r1`.
The audit text SHA-256 is
`5c6443f488b0eb5efe71971509b68b50cc34974ac05c05b9fec7b9d67c9d027f`;
the complete SHA256SUMS digest is
`0734cbaa72e9f251d0e45114e522d2ad85f86f488c174eac022a2e4cee34a92b`.
The retained initial self-including manifest attempt is documented in the
device-query report; corrected fresh-process checksum checks passed. All
initial input pins passed final readback. Classes6/its owner listing were
recorded in a supplemental post-extraction manifest, not the initial manifest.

All three targeted Java extractions exited zero with cleanup complete under
600 MiB aggregate RSS, 300 s, 512 MiB observed growth, 1 GiB reserve, 4 MiB
output and the existing file cap. Maximum sampled aggregate RSS was
107,249,664 bytes. This static audit does not establish successful GMS startup,
Google authentication or Maps imagery with the successor pair.
