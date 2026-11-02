# Unavailable stats SDK and retained locale native

GMS reached `fojo.e` from `westworld.InitOperation.b` and failed while resolving
`android.app.StatsManager` before its existing null-service return. The
bounded [caller/source audit](../native-android-tools/stats-service-source-check.md)
establishes that this path needs the type, then returns false when the service
is absent. Provider `806b354fd` adds a public final, memberless marker and an
explicit null result for typed lookup. String lookup already returns null. The
reflective fallback and every old ContextImpl member remain intact. No stats
backend, constructor, config API, nested exception type or service instance is
implemented. Focused checks passed 50 refusals, four controls and API-28 assembly
with stable second DEX output.

Producer `5f04ecb11` adds `--stats-unavailable` over the exact unmanaged-query SDK,
manifest `c54e83fadd83a1e74f2fc8938c5767c190d5783fba5f95fd583aa6432d8c361e`.
Only `ContextImpl.getSystemService(Class)` changes, and only the marker class is
added: 2,108 classes become 2,109. Raw and canonical checks enforce the early null
guard, all original instructions modulo label aliases, unchanged neighboring
members and metadata, and the exact memberless marker ABI. Non-DEX JAR payloads
are preserved. All historical producer profiles remain unchanged. Independent
producer and media source reviews passed.

| Qualified operation | Seconds | Sampled aggregate RSS bytes |
| --- | ---: | ---: |
| Producer compile | 1.625 | 371,605,504 |
| Complete producer self-tests | 0.493 | 10,420,224 |
| Complete SDK production | 43.382 | 500,875,264 |
| Complete SDK/native compatibility audit | 3.732 | 62,685,184 |

Every producer guard and child exited zero with complete cleanup. Detailed
compile/production RSS was 397,000,704/486,457,344 bytes; production recorded zero
process swaps and 210,464,768 bytes observed shared growth. No producer attempt
failed. Limits stayed 600 MiB aggregate RSS, 300 seconds for builds/tests,
900 seconds for full audits, 1 GiB reserve, 4 MiB output and shell file cap
16777216. Tool growth stayed 512 MiB and SDK production 1 GiB.

Artifacts remain under `S=/Users/alex/.local/state/vinix/android`:

| Artifact | SHA-256 |
| --- | --- |
| `combined-account-webview-stats-unavailable-framework-2026-11-02-r1/sha256.json` | `f0bdf43e99a7ada2b8ec52dde5e8da45ebf6162cd2b8a9a0b32bfc55bfa12106` |
| Framework `build.json` | `d36b41c937b6335b3490697adbad1e6efb10d83c71e19d34a712feded8fa1116` |
| Framework JAR | `86d1cc8dc592082aeb837fd260e36a4a0c93bbe5a23e3f22e4f97b5ba09e7ffd` |
| Framework DEX | `7c5112ceb7e43e4452dc44fbf6845e2c2ae76cedca7bd0b779e816f403c1736d` |
| Raw ContextImpl | `280a6780e86f47cf65900f494069fe63d4c157aa3aca99fd5cf89232f85db73b` |
| Canonical ContextImpl | `2a26f07469098c303063b8394385ac3fd5703c63a593447041ebced762620001` |
| Raw/canonical StatsManager | `9262bdfddc85ac312f1efe22faf9860320e190237d7a4302812ff4b0247136ce` |
| Retained native manifest | `f7140d2ff09d77906a2ef76884c607f64643e53cc981f16dcae90d474128f8f1` |
| Retained native DSO | `c87ccc623d70b1d582cd5486a9a6316c5117091ca10113682aa07cc72c80912f` |

Neither target class belongs to the retained native consumption map. The fresh
full audit passed all 2,109 canonical SDK classes and all 70 native-consumed raw
and canonical equalities, with zero raw differences. It also checked unchanged
91 native source origins, 92 current inputs, 721 exports, generated JNI/C,
helper closures and all 58 consumed C/header inputs. Detailed audit RSS was
66,912,256 bytes. The DSO remains at
`S/current-native-build-2026-11-02-asset-locales-r1`, coupled to its original
DeviceSecure SDK. No native rebuild or relink occurred. The fresh audit receipt
is `S/maps-stats-unavailable-tools-2026-11-02-r1/framework-audit.guard.json`.

One joint seal and a separate fresh-process readback passed eight closed caller,
source, fixture, producer, SDK and retained-native roots: 9,485 typed entries.
The exact list is `S/stats-unavailable-producers-sealed-2026-11-02-r1/roots.txt`;
its `sealed/manifest.json` SHA-256 is
`37228ab6f4fccd6b23bfa66e5e238b0a4aa74617ba55497611233465e501a0dc`.
Seal/readback took 1.783/1.326 seconds at sampled RSS 23,855,104/24,543,232 bytes
and observed growth 3,661,824/2,228,224 bytes. Both guards and children exited
zero with complete cleanup under unchanged 600 MiB/900-second/64 MiB-growth/
1 GiB-reserve limits. Complete historical and rejected evidence required by the
unchanged auditors remains retained, including the initial empty wrong-DEX
caller extraction.

Complete producer evidence remains at
`S/stats-unavailable-framework-builder-2026-11-02-r1`,
`S/stats-unavailable-framework-production-2026-11-02-r1` and the SDK root. The SDK
receipt records source revision `635dbaf0f347c82b4d2eb920fec2af28d0878140` and
exact provider/tool/closure hashes. This host qualification establishes no
signed ARM behavior, GMS startup or Google authentication result.
