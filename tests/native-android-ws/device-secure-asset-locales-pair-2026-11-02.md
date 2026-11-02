# Device credential query and asset locales pair

Google Play Services failed resolving the existing native
`AssetManager.getLocales()[Ljava/lang/String;` implementation. The
[bounded caller audit](gms-phenotype-api-audit-2026-11-02.md) also identified the
next required missing API, `KeyguardManager.isDeviceSecure()Z`. This pair batches
the native locale implementation with the one Java API addition.

Provider `c41f9dbc5` adds a public Java instance query returning false because
the fixed guest has no Android keyguard credential enrollment/backend. The
[source report](device-secure-framework-2026-11-02.md) records that scope and the
preserved four legacy methods, including the separate unconditional
`isKeyguardSecure()` result. The new query supplies no authentication authority.

Producer `a96dafe07` adds `--device-secure` over the exact stable-display SDK,
manifest `44a0ad6abdf51562e770a1848f6db06c2c2de75a1160868e999c1face01136df`.
It changes one existing class, adds one method and replaces none, with no fields,
helpers or classes added. All 2,108 classes, neighboring methods/metadata and
non-DEX JAR payloads remain intact. A literal query-body/ABI oracle runs before
assembly and after complete DEX roundtrip. All historical profiles remain
unchanged. Independent read-only producer and media draft reviews passed.

| Qualified operation | Seconds | Sampled aggregate RSS bytes |
| --- | ---: | ---: |
| Producer compile | 2.341 | 356,843,520 |
| Complete producer self-tests | 0.444 | 15,417,344 |
| Complete SDK production | 59.390 | 496,107,520 |
| Focused native locale checks | 3.538 | 123,387,904 |
| Coupled native production | 32.027 | 552,648,704 |
| Complete SDK/native compatibility audit | 2.521 | 52,346,880 |

All SDK guards and children exited zero with complete cleanup. Detailed compile
RSS was 404,553,728 bytes. Production recorded zero process swaps and
181,985,280 bytes observed shared growth. Limits stayed 600 MiB aggregate RSS,
300 seconds, 1 GiB reserve, 4 MiB output and shell file cap 16777216. Tool growth
stayed 512 MiB and SDK production growth 1 GiB. No SDK producer attempt failed.

Artifacts remain under `S=/Users/alex/.local/state/vinix/android`:

| Artifact | SHA-256 |
| --- | --- |
| `combined-account-webview-device-secure-framework-2026-11-02-r1/sha256.json` | `db98d6fcd6e0c792761f39b07ceb40d5e5818b691dede6eaccd177ec0f9973f2` |
| Framework `build.json` | `dab6370d17bf7ab9f9fe48ffa32b274cd6d7f830200152949bb1c95645d34c7e` |
| Framework JAR | `43e3e2b941677cda70021ae9cd674aac6f4897af4ab4bda1d2d751b805d1f137` |
| Framework DEX | `6e9323bea9c643630eba4eceb77df1ead9c12c53f134288109817598d3232686` |
| Raw KeyguardManager | `935ea7fa6ea194eafd55a3bb9bd7fd9e445699dfb26fbc67eb9c7f423224c3ae` |
| Canonical KeyguardManager | `c21625a68268b19a02910b534dcf5f396d00523d3faab45699ecefabd6c44d46` |
| `current-native-build-2026-11-02-asset-locales-r1/sha256.json` | `f7140d2ff09d77906a2ef76884c607f64643e53cc981f16dcae90d474128f8f1` |
| Native `build.json` | `5bc91099101c53ee288dabf3567414e2a13a31ab57ade78ecbefc7196acae31f` |
| Native DSO | `c87ccc623d70b1d582cd5486a9a6316c5117091ca10113682aa07cc72c80912f` |
| Generated JNI | `d054fd51235e1893db9f5d78a747660abb69f185a803a6caa01c0dfc206d7a6c` |
| Generated C | `d96b7dd8e1e69bb22575bd7762e8e2890feaed379e8a57031aab73c27c8160c7` |

KeyguardManager is outside the native consumed set; AssetManager is already
inside it. All 70 canonical native-consumed classes remain equal. Cloning
the canonical SDK sources changes only DisplayManager's consumed raw formatting
from `f1d4a12057ce672b7ac1ca9d92031c4d843a12819cd4d5578544eef2232efe43`
to `97198ed1a377349d0d02e991ed73ac1625daa8ed498b6bb3dfe137231d96559e`.
The actual new SDK confirms that exact pair; its canonical class is unchanged.

Native source `6d3f38087` adds one locale provider and one existing-method binding.
It enumerates the real asset manager through the retained C API with flags
`false, true`, under the resource lock, and releases the C++ locale allocation
on every path. It creates fresh Java arrays/strings and cleans up local JNI
references while preserving pending Java exceptions. Focused checks cover
datasets, empty results, flags, locking, native cleanup, fresh arrays and JNI
failures, with six broken-output controls. Strict ARM shared-library production
passed on its first attempt with 91 origins, 92 current inputs, the same 70
consumed classes and 721 exports. The new JNI wrapper is appended at index 632;
the preceding 720 exports remain unchanged. Production recorded zero process
swaps and 120,655,872 bytes observed shared growth. No native attempt failed.
The mandatory complete media audit passed all 2,108 canonical classes and the
70 consumed equalities, allowing only the exact DisplayManager raw-format pair.
It verified the new source/binding/JNI/export bridge, all retained native source
bytes, complete normalized builder and generator closures, and both original
stable-SDK and new device-SDK provenance. The consumed-header inventory permits
only generated C replacement; all header bytes and dependencies remain equal.
Its guard and child exited zero with complete cleanup, zero process swaps and
28,672 bytes observed growth under unchanged 600 MiB/900-second/512 MiB-growth/
1 GiB-reserve limits. The receipt is
`S/maps-asset-locales-tools-2026-11-02-r1/framework-audit.guard.json`.

One joint seal and a separate fresh-process readback passed for ten closed
source/fixture/SDK/native roots, including the original stable native producer.
They bind 11,500 typed entries. The exact list is
`S/asset-locales-producers-sealed-2026-11-02-r1/roots.txt`; its
`sealed/manifest.json` SHA-256 is
`b6e21824e1b4a6dc8b393b27d8e09a7b6e140d2174e67fe2ac812131cf084acc`.
Seal/readback took 1.815/0.857 seconds at sampled RSS 28,295,168/22,953,984 bytes
and observed growth 4,050,944/1,236,992 bytes. Both guards and children exited
zero with complete cleanup under unchanged 600 MiB/900-second/64 MiB-growth/
1 GiB-reserve limits. Failed manifest-control bytes retained in the core source
bundle and complete predecessor evidence remain required by unchanged auditors.

Complete SDK evidence is at `S/device-secure-framework-builder-2026-11-02-r1`,
`S/device-secure-framework-production-2026-11-02-r1` and the SDK root. The build
receipt records revision `00fd6722a85d10fa4015293e2272cff9880770f2`, which contains
the producer commit, and exact source/provider/compiler/tool hashes. The
[signed fixture host result](asset-locales-fixture-host.md) is separate evidence.
Native evidence is closed at `S/asset-locales-native-controls-2026-11-02-r1`,
`S/asset-locales-native-check-2026-11-02-r1` and the coupled native root.
ARM behavior and live Maps flow remain required; this host qualification
establishes no checkin or Google authentication success.
