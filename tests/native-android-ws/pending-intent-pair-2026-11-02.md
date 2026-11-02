# PendingIntent SDK and retained native pair

Provider `f544e142c` repairs query-only service-token lookup and context-send
dispatch in the [GMS recovery sequence](gms-intent-operation-pending-intent-audit-2026-11-02.md).
The [focused source report](pending-intent-framework-2026-11-02.md) records the
registry identity, creator Context, explicit DEX monitor paths, fill-in behavior
and preserved local parcel capability. Its four-class source checks and signed
behavior fixture are separate evidence from this complete SDK qualification.

Producer `358db21e2` adds `--pending-intent` over the exact retained Intent SDK,
manifest `bef486d060754858d51612b9c4bb8a24f7c2fdf8f37cc3565101e24a049bf52f`.
Only `android/app/PendingIntent.smali` changes: twelve existing methods, seven
private static helpers and seven private fields. All 2,108 classes remain,
including its three unchanged capability helper classes. All other classes,
retained PendingIntent methods and fields, and non-DEX JAR payloads remain
byte-identical. Exact ABI/member/class gates run before assembly and after the
complete DEX roundtrip. Historical producer profiles and their refusal tests
remain intact. Independent read-only producer review passed.

| Qualified operation | Seconds | Sampled aggregate RSS bytes |
| --- | ---: | ---: |
| Producer compile | 1.579 | 354,713,600 |
| Complete producer self-tests | 0.289 | 15,384,576 |
| Complete SDK production | 43.423 | 493,486,080 |

All three guards and children exited zero with complete cleanup. The compiler's
detailed maximum RSS was 393,117,696 bytes; SDK production recorded zero process
swaps and 264,876,032 bytes of observed shared-volume growth. Limits stayed
600 MiB aggregate RSS, 300 seconds, 1 GiB reserve, 4 MiB output and shell file cap
16777216. Tool qualification used 512 MiB growth; SDK production used 1 GiB.
No producer attempt failed.

Artifacts remain under `S=/Users/alex/.local/state/vinix/android`:

| Artifact | SHA-256 |
| --- | --- |
| `combined-account-webview-pending-intent-framework-2026-11-02-r1/sha256.json` | `8717d3d489e9f86b8c96d2689c7ec6811bc7c80fbade0e35f64e9e84014f7c36` |
| Framework `build.json` | `28fe376e0e1bcc4106b699feab10ef232cc6e1c31a0bc9a525df567df9903a34` |
| Framework JAR | `bc82567de6d8abd6a4084c68e0e4c698df12d2c7848c7d23b6af7e5d0e6df7cc` |
| Framework DEX | `649b148986fd95d7d42789e02170b4fdb59f7974a6fc5341631e3940b8e0531d` |
| Changed raw PendingIntent | `c71a0c7525e430ec0a492c5f03f290ef753065bd378974d680e8b1db17bf08d4` |
| Changed canonical PendingIntent | `a4692e2521f22789d2f785c5aa83413ccb708eff97a5ae213664bd10f800b93e` |
| Retained native manifest | `ffe69aca16f77cacac1021b94f4825d1a23a574904614bdca57610c39fa42197` |
| Retained native DSO | `aeb5ccd643020cbb20ad5630dabff4bfd0ff8b04a5b0fbcfd1b657b3bcd91dd7` |

PendingIntent is outside the retained native build's 69-class input set. The
native root remains `S/current-native-build-2026-11-01-resource-lock-r2`, coupled
to its original Intent SDK. No native rebuild or relink is performed. The actual
complete compatibility audit passed all 2,108 canonical classes and all 69
consumed raw/canonical equalities, with zero raw differences. Native source and
header membership, generated JNI/C, helper closures and all 719 exports remain
exact. Its original complete producer evidence and historical auditors remain
required. The guarded audit took 1.353 seconds at sampled RSS 51,216,384 bytes,
with exits zero, complete cleanup and zero process swaps under unchanged
600 MiB/900-second/512 MiB-growth/1 GiB-reserve limits. Its receipt is
`S/maps-pending-intent-tools-2026-11-02-r1/framework-audit-r2.guard.json`.

The first new-profile audit rejected an inherited registration-text assumption:
the narrow SDK invokes its successor through the isolated provider main, while
the retained framework helper registers Intent extras. The reviewed correction
requires the exact extracted replacement helper, exact successor main call and
complete provider membership. The first frozen tool sources, project, executable
and rejected audit remain unchanged. The corrected stager was rebuilt and its
self-tests and complete audit passed; the SDK and native inputs did not change.

One joint seal and a separate fresh-process full readback passed for eight
closed roots: both core source checks, the signed fixture and its controls, the
producer, production controls, new SDK and retained native producer. They bind
9,992 typed entries. The exact list is
`S/pending-intent-producers-sealed-2026-11-02-r1/roots.txt`; its
`sealed/manifest.json` SHA-256 is
`a850bc0bbe1821ead8d4edfa0aa62aa47efc6ed8a08edb076b13aa47ae0c15ca`.
Seal/readback took 1.107/0.731 seconds at sampled RSS 24,363,008/24,051,712 bytes
and observed growth 3,977,216/3,649,536 bytes. Both guards and children exited
zero with complete cleanup under unchanged 600 MiB/900-second/64 MiB-growth/
1 GiB-reserve limits. The earlier source-check attempts remain complete in r1.

Complete producer evidence remains at
`S/pending-intent-framework-builder-2026-11-02-r1` and
`S/pending-intent-framework-production-2026-11-02-r1`.
Signed ARM behavior and the live Maps recovery flow remain unverified; this
qualification establishes no Google login success.
