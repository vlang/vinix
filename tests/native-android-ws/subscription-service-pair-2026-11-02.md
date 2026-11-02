# Subscription wrapper SDK and retained locale native

GMS `cjvx.a` requires a nonnull subscription wrapper, and its audited direct
consumer needs absent-backend queries and no-modem telephony wrappers. Provider
`bf4a357a6` supplies one cached SubscriptionManager per ContextImpl through both
lookup forms, using an explicit monitor and catchall release. Information/list
queries return null; the Android 13 phone-number query throws the exact
unavailable-service IllegalStateException. Phone/modem counts are zero and the
subscription factory creates a fresh wrapper carrying the requested ID. The
[source report](../native-android-tools/subscription-service-source-check.md)
records the AOSP/caller boundary, 116 refusals, 22 output controls and stable
four-class DEX roundtrips. No subscriptions, modem, records, record getters,
listeners, permission grant or default-ID behavior are supplied.

Producer `8dd3331d1` adds `--subscription-service` over the exact Stats SDK,
manifest `f0bdf43e99a7ada2b8ec52dde5e8da45ebf6162cd2b8a9a0b32bfc55bfa12106`.
Only ContextImpl, SubscriptionManager and TelephonyManager change: two lookup
replacements, seven method additions and two private fields. The sole new class
is public final, memberless SubscriptionInfo: 2,109 classes become 2,110.
Raw and canonical oracles enforce every added instruction, cache guard,
monitor/catch span, null result, exception and fresh ID-carrying wrapper. They
preserve all fallback instructions, constructors, 24 old TelephonyManager
methods, neighboring metadata and non-DEX JAR payloads. Historical producer
profiles remain unchanged. Two independent producer source reviews passed.

| Qualified operation | Seconds | Sampled aggregate RSS bytes |
| --- | ---: | ---: |
| Producer compile | 1.697 | 376,487,936 |
| Complete producer self-tests | 0.333 | 1,294,336 |
| Complete SDK production | 45.798 | 492,503,040 |
| Complete SDK/native compatibility audit | 4.025 | 50,970,624 |

Every producer guard and child exited zero with complete cleanup. Detailed
compile/self-test/production RSS was 393,478,144/14,303,232/490,815,488 bytes;
production recorded zero swaps and 614,199,296 bytes observed shared growth.
No SDK producer attempt failed. Limits stayed 600 MiB aggregate RSS, 300 seconds
for builds/tests, 900 seconds for full audits, 1 GiB reserve, 4 MiB output and
shell file cap 16777216. Tool growth stayed 512 MiB and SDK production 1 GiB.

Artifacts remain under `S=/Users/alex/.local/state/vinix/android`:

| Artifact | SHA-256 |
| --- | --- |
| `combined-account-webview-subscription-service-framework-2026-11-02-r1/sha256.json` | `958e5a7c02710a3aa78a04b499f6c6d5ca4701e1c2c8d33b7dda6f640ac561db` |
| Framework `build.json` | `0b929b5dc6710bfcb60eda8ac264b720087cd9905db9642bf0d74f260506e037` |
| Framework JAR | `72c57e05b4458d8c62f82cd29fe70065318303af6b741bf1726337ce922c60ef` |
| Framework DEX | `a835055a2dd11e0e54f22a4f45334769b959cc110cf8f221bb470c36cbc50119` |
| Raw ContextImpl | `5c33f4eec29bf3d74be2a7a26aaeca5a6a66436421ae8c5e4246f567faf37797` |
| Canonical ContextImpl | `30058b3a10b57ccc91dd60d30a6730683817af5cf74e61e6375077f1b08aa336` |
| Raw SubscriptionManager | `e784bb1629d896ccf0717abc0755418a6b02cbbd51ab6f08c933c8ee1210ae78` |
| Canonical SubscriptionManager | `fab61ef567fd8608efc6f7b51441cd67a41a9f3b907ae1d0bc35bd26a98d552e` |
| Raw TelephonyManager | `0ea28a17a93161e560fe13a2ef90cf8c7d778fe978d82837f85642c5d2cf6d51` |
| Canonical TelephonyManager | `34e83c28d18a95880cb9c07221cdc20952ea9a802c63dd8cda071fa2234146a5` |
| Raw/canonical SubscriptionInfo | `6925d83267931e7bd2499bcc6057f869a2839ecc6dac0b8ef96a6c979ee4b978` |
| Retained native manifest | `f7140d2ff09d77906a2ef76884c607f64643e53cc981f16dcae90d474128f8f1` |
| Retained native DSO | `c87ccc623d70b1d582cd5486a9a6316c5117091ca10113682aa07cc72c80912f` |

All four targets are outside the retained native consumption map. The fresh
full audit passed the entire canonical SDK delta and all 70 consumed raw and
canonical equalities, with zero raw differences. It checked unchanged 91 native
origins, 92 current inputs, 721 exports, generated JNI/C, helper closures and all
58 consumed C/header inputs. Detailed audit RSS was 51,232,768 bytes. The DSO
remains at `S/current-native-build-2026-11-02-asset-locales-r1`, coupled to its
original 2,108-class DeviceSecure SDK. No native rebuild or relink occurred. The
fresh receipt is
`S/maps-subscription-service-tools-2026-11-02-r1/framework-audit.guard.json`.

One joint seal and a separate fresh-process readback passed eight closed caller,
source, fixture, producer, SDK and retained-native roots: 9,563 typed entries.
The list is `S/subscription-service-producers-sealed-2026-11-02-r1/roots.txt`;
its `sealed/manifest.json` SHA-256 is
`175fac12b7a3c9bcc95a600463df857ca69f3a0300faa43b15c3f4c52afeba8a`.
Seal/readback took 1.734/1.203 seconds at sampled RSS 24,051,712/24,018,944 bytes
and observed growth 13,647,872/7,979,008 bytes. Both guards and children exited
zero with complete cleanup under unchanged 600 MiB/900-second/64 MiB-growth/
1 GiB-reserve limits. Complete historical and rejected evidence remains
retained, including the core checker compile and whitespace-oracle attempts.

The immutable SDK receipt records integration revision
`1d2a2ec4ddd1e0e9d9563a3d90a4a5af75d29944`: core committed after production while
reporting finished off-lane. Its recorded provider
`770cdcac247adcdd734af33a4bf5d99a678460758bac0385df14f5da11d42add` and framework
`83a6706f6c31fa1c78db346f05d0e4222c09dcd06e794260b9e53fbc4e15d1c4`
hashes were independently checked against the committed blobs in `bf4a357a6` and
match exactly. The receipt's original revision and artifact pins are preserved.
Complete evidence remains at `S/subscription-service-framework-builder-2026-11-02-r1`,
`S/subscription-service-framework-production-2026-11-02-r1` and the SDK root.
This host qualification establishes no ARM, GMS startup, Google authentication
or current imagery result.
