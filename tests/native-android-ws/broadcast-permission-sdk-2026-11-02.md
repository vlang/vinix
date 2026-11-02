# Broadcast permission SDK successor

The [preceding GMS run](maps-keyguard-policy-runtime-2026-11-02.md) reached the
missing `Context.sendBroadcast(Intent, String)` overload. Core `0b00959bc`
filters the existing process-local dispatcher using a private immutable snapshot
from the authenticated primary APK. Null permission preserves unrestricted
delivery; unproven permissions reach neither receiver path, and null Intent
throws before the permission decision. The
[source report](../native-android-tools/broadcast-permission-source-check.md)
defines the supported requested, self-declared signature-permission subset and
the separate limits of this transport.

Producer `84a791b70` adds `--broadcast-permission` over the exact keyguard-policy
SDK. Context retains all 106 methods and adds one Java overload. ATLLoadedApp
retains its 22 methods, changing only the constructor to initialize one private
final Set immediately after assigning the package, and adds one public final
boolean query. Its register count stays six and all original constructor
instructions remain in order. The sole new class is fieldless
VinixBroadcastPolicy with two static methods: 2,110 classes become 2,111.

Independent producer oracles bind every snapshot instruction and branch target:
verified nonempty signer metadata, nonempty owner/name, requested permission,
self-owned signature base type, duplicate rejection and unmodifiable storage.
Delivery validates Intent, consults only the primary holder's private snapshot,
and denies before delegating to the unchanged one-argument native dispatcher.
All other methods, fields, class metadata and non-DEX JAR payloads remain equal.
The checks run before and after API-28 DEX assembly. Historical producer
profiles are unchanged. Independent source review approved the change.
Independent complete artifact review confirmed the three-class scope, preserved
native declarations, constructor ordering and unchanged remaining members.

| Operation | Guard seconds | Sampled RSS bytes | Detailed RSS bytes |
| --- | ---: | ---: | ---: |
| Producer compile | 1.606 | 378,322,944 | 410,877,952 |
| Complete producer self-tests | 0.701 | 15,433,728 | 14,336,000 |
| Complete SDK production | 41.726 | 498,548,736 | 481,116,160 |

All producer phases passed on their first attempts, with zero guard/child
exits, complete cleanup and zero swaps. Production observed 153,878,528 bytes
shared disk growth. Limits stayed 600 MiB aggregate RSS, 300 seconds, 1 GiB
reserve, 4 MiB output and file cap 16777216; tool/SDK growth stayed 512 MiB/1 GiB.
The complete focused source bundle also preserves its earlier rejected label
comparison and successful corrected checker; the provider did not change.

Paths below use `S=/Users/alex/.local/state/vinix/android`. The complete SDK is
`S/combined-account-webview-broadcast-permission-framework-2026-11-02-r1`.

| Artifact | SHA-256 |
| --- | --- |
| Baseline keyguard-policy manifest | `13ef4747529ec6d0d3669a3ad059e6eee82bf99b80900b835b7de2d40a007a92` |
| New SDK manifest | `49daffbfa9dc1dcc598e453eaae3611df7702963aa5b659022545149af7132d5` |
| Framework `build.json` | `6a23ffb21dce173d251dbfcaadd27a83e4b4f72fcea0b23e908798a5218d2a36` |
| Framework JAR | `9e998094f8e122c22195e0c9a8f79377dbf16cd04d321ab4d1a47650908082f9` |
| Framework DEX | `401f89971c21972cd97a6784665ebe0610eea08860f499e453507b68bbd4e1a5` |
| Raw Context | `3819dd399a1ac9e8fba32ada045cc250f670f4fa012d765126ded7d1acbba0e8` |
| Canonical Context | `60fdbab8aef10711d65afa9a0ddf5e64369ae21e0f9010291288109ebc305ab5` |
| Raw ATLLoadedApp | `3e133e9cf9a3a2271bfef87917f2060c14b40a550dfb6f760c5b4278580b729f` |
| Canonical ATLLoadedApp | `6e8d9800711ae17e8b8a86de267590c2bb702d7d6fe8db870c57e6a599e5b0bd` |
| Raw VinixBroadcastPolicy | `e031d2f31dce873931315259e64d7dd521b0cd50dd1f7b3f6a933283d965fd90` |
| Canonical VinixBroadcastPolicy | `38e186faf379d2188d8eb398aea356102badfbe676350bcf21b1d0e38847ebad` |

The immutable SDK receipt records source revision
`0b00959bc20d3dd9e6e6804b9a60393949d29a94`, containing producer `84a791b70`.
Frozen provider, framework registration and producer sources match their
committed blobs. Builder/provider source closures retain 271/143 entries.
Complete builder and production controls remain at
`S/broadcast-permission-framework-builder-2026-11-02-r1` and
`S/broadcast-permission-framework-production-2026-11-02-r1`.

One joint seal and a separate fresh-process readback passed twelve complete
closed caller, source-check, fixture/control, SDK producer, SDK, fresh native/
control and original native roots: 11,486 typed entries. It includes the failed
first fixture assembly and its controls, successful second fixture and controls,
and both focused checker attempts. No rejected evidence was replaced or omitted.
The list is `S/broadcast-permission-producers-sealed-2026-11-02-r1/roots.txt`;
its `sealed/manifest.json` hashes to
`b755b2951d12e064f648b6baa872019aba414dfe61739c65197500382d9ef67d`.
Seal/readback took 1.303/1.229 seconds at sampled RSS 20,987,904/14,499,840 bytes
and observed growth 3,129,344/1,486,848 bytes, with zero guard/child exits,
complete cleanup and zero swaps under unchanged 600 MiB/900-second/64 MiB-growth/
1 GiB-reserve limits. Both complete old/new native bundles and exact comparison
records remain sealed with their original provenance.

Context and ATLLoadedApp are native-consumed classes. A fresh native build
coupled to this SDK is required despite unchanged native method declarations.
The [sealed fresh native qualification record](/Users/alex/.local/state/vinix/android/broadcast-permission-native-controls-2026-11-02-r1/result.md)
records new manifest
`e371c8d365b78493f9f9d660ceceb1cb2b1382eaa60cae06bcbe4aad0c6c233b`
and DSO `29b2631c36a4a8c802e904e936c23e090fb2de3b5019ac93548df1b15de2a8f1`,
retaining all 70 consumed classes with exactly Context/ATLLoadedApp raw changes.
Its record hashes to `bf5ddf7123445303d5f7411c1fab86ef466876a4249ed0717b78d199ea45a264`.
The original native bundle remains unchanged; no older provenance was relabeled.
Complete media admission, ARM execution and live GMS/Maps remain separate steps.
This SDK report establishes no authentication or current imagery result.
