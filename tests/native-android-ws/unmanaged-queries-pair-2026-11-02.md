# Unmanaged queries SDK and retained locale native

The bounded caller audit found two required missing queries after the asset
locale call: `DevicePolicyManager.getDeviceOwner()Ljava/lang/String;` and
`UserManager.isManagedProfile()Z`. Provider `40cd4ae84` adds public Java instance
methods returning null and false for this guest, which has no Android device
owner, managed-profile enrollment or policy service. The
[source report](unmanaged-queries-source-check.md) records the caller boundary,
116 schema refusals, 16 fault controls and preservation of the 19 original
methods. Existing PackageManager component-state getter/setter limitations
remain recorded separately; this change adds only the two audited queries.

Producer `b0db8a64a` adds `--unmanaged-queries` over the exact DeviceSecure SDK,
manifest `db98d6fcd6e0c792761f39b07ceb40d5e5818b691dede6eaccd177ec0f9973f2`.
Each target gains one method, with zero replacements, fields, helpers or classes
added. All 2,108 classes, neighboring methods/metadata and non-DEX JAR payloads
remain intact. Literal null-owner/false-profile ABI and instruction oracles run
before assembly and after full DEX roundtrip. Historical profiles are unchanged.
Independent source, media and final artifact-pin reviews passed.

| Qualified operation | Seconds | Sampled aggregate RSS bytes |
| --- | ---: | ---: |
| Producer compile | 1.620 | 357,482,496 |
| Complete producer self-tests | 0.344 | 15,269,888 |
| Complete SDK production | 42.630 | 497,205,248 |
| Complete SDK/native compatibility audit | 2.910 | 64,159,744 |

Every guard and child exited zero with complete cleanup. Detailed compile RSS
was 406,536,192 bytes; production recorded zero process swaps and 418,471,936
bytes observed shared growth. Limits stayed 600 MiB aggregate RSS, 300 seconds
for builds/tests, 900 seconds for the full audit, 1 GiB reserve, 4 MiB output and
shell file cap 16777216. Tool growth stayed 512 MiB and SDK production 1 GiB.
No producer attempt failed.

Artifacts remain under `S=/Users/alex/.local/state/vinix/android`:

| Artifact | SHA-256 |
| --- | --- |
| `combined-account-webview-unmanaged-queries-framework-2026-11-02-r1/sha256.json` | `c54e83fadd83a1e74f2fc8938c5767c190d5783fba5f95fd583aa6432d8c361e` |
| Framework `build.json` | `81c6943bfcf1cc990c4dc66ebcfe11e93393ffbaf646904af1099b4d6df397cf` |
| Framework JAR | `25500d52cf7c03a2a1c82656c00284c507dbdb03cff546dbc6e5840aa45b5c1c` |
| Framework DEX | `9d3fba4639ddbf6cb987eb270efc5f090c93e1cd852abcacb84fe1d943a10608` |
| Raw DevicePolicyManager | `ca8fe29177db890e6c346e10320474e2305bacb0b66524efdcb0951a22edda22` |
| Canonical DevicePolicyManager | `acc9e1082d2ac56903fb23f73dc6121235b46b10fb3f73155d66e95534b0c285` |
| Raw UserManager | `3b22357f76edf872d8e0539017a3144999aa64f9d1b1522f0cca3eeb302e79cf` |
| Canonical UserManager | `ca127b95ac46238d8885f1aed2531e99590bd26ab24eff9b21cfa076e032db1a` |
| Retained native manifest | `f7140d2ff09d77906a2ef76884c607f64643e53cc981f16dcae90d474128f8f1` |
| Retained native DSO | `c87ccc623d70b1d582cd5486a9a6316c5117091ca10113682aa07cc72c80912f` |

Both target classes are outside the retained native consumption map. The actual
fresh audit passed every canonical SDK class and all 70 native-consumed raw and
canonical equalities, with zero raw differences. It also checked the complete
unchanged 91 native source origins, 92 current inputs, 721 exports, generated
JNI/C, helper closures and all 58 consumed C/header inputs. The library remains
`S/current-native-build-2026-11-02-asset-locales-r1`, coupled to its original
DeviceSecure SDK. No native rebuild or relink occurred. The native-reuse audit
receipt is `S/maps-unmanaged-queries-tools-2026-11-02-r1/framework-audit.guard.json`.

One joint seal and a separate fresh-process readback passed eight closed caller,
source, fixture, SDK producer and retained-native roots: 10,328 typed entries.
The exact list is `S/unmanaged-queries-producers-sealed-2026-11-02-r1/roots.txt`;
its `sealed/manifest.json` SHA-256 is
`996aad479717f070b3d9c874cc183dccd765672182aa4f8b35d1d03955925174`.
Seal/readback took 1.777/1.397 seconds at sampled RSS 24,068,096/24,592,384 bytes
and observed growth 28,585,984/2,666,496 bytes. Both guards and children exited
zero with complete cleanup under unchanged 600 MiB/900-second/64 MiB-growth/
1 GiB-reserve limits. Complete historical and rejected evidence required by the
unchanged auditors remains retained; no deletion is qualified.

Complete producer evidence remains at
`S/unmanaged-queries-framework-builder-2026-11-02-r1`,
`S/unmanaged-queries-framework-production-2026-11-02-r1` and the SDK root. The SDK
receipt records source revision `b0db8a64a773148febd68977635d21f80239fbfc` and exact
provider/tool/closure hashes. Signed ARM behavior and live Maps validation remain
required; this host qualification establishes no checkin or authentication success.
