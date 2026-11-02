# Stable display SDK and native pair

Google Play Services reached `IntentOperation.onHandleIntent` after the passed
PendingIntent ARM regression, then failed because
`DisplayManager.getStableDisplaySize()Landroid/graphics/Point;` was absent.
Provider `be5f641c9` adds exactly that public virtual native declaration. It
preserves DisplayManager's five existing methods, all fields and annotations,
and the separate Display and Point classes. The physical framebuffer query
requires the new native implementation; this SDK cannot use the previous DSO
for that method. Mutable application-window dimensions do not supply its result.

Producer `c22e7e2dd` adds `--stable-display` over the sealed PendingIntent SDK,
manifest `8717d3d489e9f86b8c96d2689c7ec6811bc7c80fbade0e35f64e9e84014f7c36`.
Exactly one existing class changes, with zero replaced methods and one added
native method. There are no new fields, helpers or classes. All 2,108 classes,
the retained PendingIntent fix, every neighboring method/field and non-DEX JAR
payload remain byte-identical. The declaration oracle rejects changed ABI flags,
arguments, register declarations, executable instructions and duplicate methods
before assembly and after complete DEX roundtrip. All historical producer
profiles, including PendingIntent, remain unchanged.
Independent read-only producer review passed.

| Qualified operation | Seconds | Sampled aggregate RSS bytes |
| --- | ---: | ---: |
| Producer compile | 1.573 | 359,841,792 |
| Complete producer self-tests | 0.379 | 1,294,336 |
| Complete SDK production | 43.204 | 497,909,760 |
| Final focused native checks | 1.749 | 117,637,120 |
| Coupled native production, r2 | 22.059 | 568,688,640 |
| Complete SDK/native compatibility audit | 2.537 | 53,854,208 |

Every admitted guard and child exited zero with complete cleanup. Detailed maximum RSS
was 381,124,608 bytes for compilation and 14,155,776 bytes for the short self-test;
SDK production recorded zero process swaps and 183,312,384 bytes observed shared
growth. Original limits stayed 600 MiB aggregate RSS, 300 seconds, 1 GiB reserve,
4 MiB output and shell file cap 16777216. Tool growth stayed 512 MiB and SDK/native
production growth 1 GiB. The full compatibility audit retained its 900-second
limit. No SDK producer attempt failed.

Artifacts remain under `S=/Users/alex/.local/state/vinix/android`:

| Artifact | SHA-256 |
| --- | --- |
| `combined-account-webview-stable-display-framework-2026-11-02-r1/sha256.json` | `44a0ad6abdf51562e770a1848f6db06c2c2de75a1160868e999c1face01136df` |
| Framework `build.json` | `6c7ce8d04bf10b9433b3e8eaa37a950c8d1a064111e6ff2a45e1fec28d47179c` |
| Framework JAR | `3b51a6cfe506db8e87908fdf74fcaebd585aaace383e8880a0183cd901780e52` |
| Framework DEX | `207e71a5bc37a6c6aae59a436f70a9a07380adcba0d061c4e4502430e160f179` |
| Changed raw DisplayManager | `f1d4a12057ce672b7ac1ca9d92031c4d843a12819cd4d5578544eef2232efe43` |
| Changed canonical DisplayManager | `97198ed1a377349d0d02e991ed73ac1625daa8ed498b6bb3dfe137231d96559e` |
| `current-native-build-2026-11-02-stable-display-r2/sha256.json` | `ebda45390f21abd3d45a6e51b9ea2bce22b9ce11b3e1eb19ea49927ff7e72daa` |
| Native `build.json` | `4a8f8e707bdc428d3d6bac3736a37712838a3d8a323e8e424d8ed34beb0f3119` |
| Native DSO | `364f76761b57da6e0674d9a0c20f85e2589e5b8705d22aac6e6c3a9b82f8fcae` |
| Generated JNI | `d0b1eec6e60036e5d231d6ade0450ceeb71fb2fdcb95b2057ba111c2c6a3d19f` |
| Generated C | `881a321444643dda277089d591a27e110536f89c4f40f16e54196c62f7f9efba` |

Native source `91ca4b7bd` supplies a fresh Point from the primary framebuffer's
read-only geometry query, using its complete 160-byte ABI. It opens with
close-on-exec, closes every successfully opened descriptor, and returns an empty
fresh Point when geometry is unavailable. It reads no pixels and maps no framebuffer.
The fixed display mode is the supported stable-size scope. Focused checks cover
layout, read-only flags, failed queries, fd zero and lifetime, bounds, fresh Point
construction, JNI exceptional paths and six broken-output controls.

The native producer is coupled to this exact stable SDK. It has 90 source
origins, 91 current inputs, 70 consumed framework classes and 720 exports: the
old 69 consumed classes plus DisplayManager, and the old 719 exports plus its
single JNI entry. Strict ARM compilation and shared linking passed in r2,
recording zero process swaps and 83,697,664 bytes observed shared growth. The
complete actual media audit passed all 2,108 canonical classes, the 69 retained
raw/canonical equalities with zero raw differences, and the added consumed class.
It verified the exact native source/binding/JNI/export deltas, full normalized
builder/generator helper closures and the predecessor's original Intent SDK
provenance. Raw native headers remain unchanged. The normalized consumed-header
map admits only generated C plus three exact ioctl headers already present in
both original and new sealed reused-input maps; current and retained header
bytes were independently read and matched. Its guard and child exited zero
with complete cleanup, zero process swaps and 282,624 bytes observed growth.
The receipt is
`S/maps-stable-display-tools-2026-11-02-r1/framework-audit-r2.guard.json`.

The first coupled build failed strict ARM `-Werror` because an addressed fixed
JNI argument array made the old V compiler emit an unresolved `memdup` call.
The correction uses the established `C.alloca` argument pattern. Independent
review, final exact-source focused checks and the fresh r2 build passed without
changing SDK, compiler flags or limits. The failed r1 took 15.016 seconds,
sampled 550,633,472 bytes RSS and exited 1 with complete cleanup. Its complete
sources, generated output and receipts remain preserved alongside all earlier
checker attempts; r1 is not admitted as a native producer.

One joint seal and a separate fresh-process readback passed for thirteen closed
roots, binding 13,344 typed entries. They include the core source check, fixture
and controls, SDK builder/production/SDK, native controls, all three focused native
attempts, failed and admitted native producers, and the original retained native
producer. The exact list is
`S/stable-display-producers-sealed-2026-11-02-r1/roots.txt`; its
`sealed/manifest.json` SHA-256 is
`49f3532e8d3b9a399233abc2d6d72449e40c71909928d57721c4beaed9188c26`.
Seal/readback took 2.115/0.784 seconds at sampled RSS 28,049,408/24,035,328 bytes
and shared growth 2,695,168/1,372,160 bytes. Both guards and children exited zero
with complete cleanup under unchanged 600 MiB/900-second/64 MiB-growth/1 GiB-reserve
limits. Preserve all complete predecessor and rejected bundles required by their
unchanged auditors.

Complete sources, source closures, pinned compiler/tool copies, commands and
receipts are preserved in the SDK root and
`S/stable-display-framework-builder-2026-11-02-r1` and
`S/stable-display-framework-production-2026-11-02-r1`.
The SDK build receipt records source revision
`c22e7e2dd0978b7e2bbdffcb2e66ba15e783a833` and the exact core provider/registration
pins. Native evidence is at
`S/stable-display-native-controls-2026-11-02-r1`, the three
`S/stable-display-native-check-2026-11-02-r{1,2,3}` roots and both
`S/current-native-build-2026-11-02-stable-display-r{1,2}` roots.
Signed ARM behavior and live Maps validation remain required; this host
qualification establishes no checkin or Google authentication success.
