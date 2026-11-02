# Stable physical display API

Source baseline: `824c6e2cad2f1010eb594c1eef4702448370b550`.
With the PendingIntent fix, GMS now executes IntentOperation and reaches
PhenotypeRegistrationOperation, where its call to
`DisplayManager.getStableDisplaySize()Landroid/graphics/Point;` throws
NoSuchMethodError. The admitted PendingIntent SDK lacks that method.

The provider appends exactly one public instance native method to the existing
DisplayManager. Its five existing methods, all metadata and fields are
preserved. No class, field or helper is added; Display and Point are unchanged.
The full framework builder registers the same provider, and the narrow producer
applies its pure source function over the qualified PendingIntent SDK.

This API requires the new coupled native backend. Its intended source is the
fixed guest's primary `/dev/fb0` physical pixel mode, read with
FBIOGET_VSCREENINFO, returning a fresh Point. The existing
Display.getRealSize/getRealMetrics read per-app surface dimensions, which the
native bootstrap sets from its window size; those values cannot supply stable
physical geometry. Headless services otherwise retain the old Display defaults.
No physical dimension is hardcoded and no framebuffer pixels are read or mapped
by this API contract. Unknown geometry returns an empty Point, consistent with
the [AOSP service implementation](https://android.googlesource.com/platform/frameworks/base/+/50ebd0232f1a/services/core/java/com/android/server/display/DisplayManagerService.java).
The scope is the fixed primary guest display; it makes no dynamic-mode
persistence, multi-display or Android stable-ID claim. Native implementation,
binding and behavior are qualified separately.

The focused V checker passed 33 malformed/repeated-input refusals before writes
and four negative ABI controls. It requires the original fieldless five-method
schema and rejects wrong/duplicate classes or superclasses, fields, missing or
duplicate methods, changed access, unbalanced ends and preexisting API variants.
Its output oracle accepts only the exact native-method append. API-28 assembly
and two DEX roundtrips passed across DisplayManager, Display and Point, preserving
the five old methods and both dependency classes. Independent source review
passed. These are source/ABI/assembly checks, without a native invocation or ARM
pass; the former native library cannot implement the added declaration.

Complete frozen sources, input/tool hashes, malformed cases, Smali, DEX, logs
and guard receipts are outside Git at
`/Users/alex/.local/state/vinix/android/stable-display-source-check-2026-11-02-r1`.
The input/output receipt SHA-256 is
`11d44203ba68c83b002b0d9cf216e9d625394e5068e67e38627f18bb3062e274`.
The complete SHA256SUMS digest is
`112462f7f27c9794dbb82fc925d8e64fbb9d185ceca66ebcec923bc2caf41348`.

| Artifact | SHA-256 |
| --- | --- |
| Provider | `480d73ba0e7fe5af709d3a142aa51d3b2a43c0e7f2f1224ef443d4f6ae2f1b11` |
| Full framework registration | `635c432ff8859afde60a9a0206a6eaead371937dd38a73e8c535d9e47385eb61` |
| Raw DisplayManager | `f1d4a12057ce672b7ac1ca9d92031c4d843a12819cd4d5578544eef2232efe43` |
| Canonical DisplayManager | `97198ed1a377349d0d02e991ed73ac1625daa8ed498b6bb3dfe137231d96559e` |

The source/DEX check took 7.036 seconds at 204,455,936 bytes sampled aggregate
RSS and 17,649,664 bytes observed shared-volume growth. The orchestrator compile
peaked at 313,655,296 bytes sampled aggregate RSS. Both passed their first
attempt, exited zero, reported complete cleanup and zero process swaps under
the original 600 MiB aggregate RSS, 300-second, 512 MiB growth, 1 GiB reserve,
4 MiB output and shell file-cap 16777216 limits. All source and tool pins were
rechecked after execution. No full SDK/native build or VM operation ran here.
