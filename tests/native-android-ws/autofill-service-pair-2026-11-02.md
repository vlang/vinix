# Autofill component query SDK successor

GMS's audited `ayrh.a` helper asks for the enabled autofill component and returns
false before provider operations when it is null. The preceding ARM run reached
an uncaught missing-method error at that query and GMS exited with status 10.
Core `eff7b719a` adds the public instance query returning null for this target's
absent autofill backend. The seven existing manager methods, notifications,
callbacks, metadata and AutofillValue behavior remain unchanged. The
[source checks](../native-android-tools/autofill-service-source-check.md) and
[preceding runtime](maps-subscription-service-runtime-2026-11-02.md) record those
separate boundaries. No provider, session, successful fill or authentication is
advertised.

Producer `4fb48d93d` adds only `--autofill-service` over the exact subscription
SDK. It changes one retained class, replaces no methods and adds only
`AutofillManager.getAutofillServiceComponentName()ComponentName`, with no fields
or class additions: membership stays 2,110. The raw and canonical oracles require
the exact public instance null result; complete class/member/metadata and
non-DEX JAR comparisons preserve everything else. The producer freezes and
rechecks both the pure provider and its existing autofill integration source.
Historical profiles are unchanged. Two independent source reviews passed.
An independent produced-artifact review confirmed the complete class/JAR delta,
all seven retained manager methods and matching committed/frozen source pins.

| Operation | Guard seconds | Sampled RSS bytes | Detailed RSS bytes |
| --- | ---: | ---: | ---: |
| Producer compile | 1.628 | 374,374,400 | 392,069,120 |
| Complete producer self-tests | 0.295 | 15,450,112 | 14,352,384 |
| Complete SDK production | 43.222 | 505,626,624 | 493,338,624 |
| Complete SDK/native compatibility audit | 2.154 | 70,352,896 | 69,091,328 |

All four phases passed on their first attempts, with zero guard/child exits,
complete cleanup and zero swaps. Production observed 153,972,736 bytes shared
disk growth. Limits stayed 600 MiB aggregate RSS, 300 seconds for builds/tests,
900 seconds for the full audit, 1 GiB reserve, 4 MiB output and shell file cap
16777216; tool/SDK growth remained 512 MiB/1 GiB.
Complete producer self-tests include the new null-result ABI/body/visibility,
retained member/metadata and exact class-scope refusals.

Paths below use `S=/Users/alex/.local/state/vinix/android`. The complete SDK is
`S/combined-account-webview-autofill-service-framework-2026-11-02-r1`.

| Artifact | SHA-256 |
| --- | --- |
| Baseline subscription manifest | `958e5a7c02710a3aa78a04b499f6c6d5ca4701e1c2c8d33b7dda6f640ac561db` |
| New framework manifest | `df8ec5e67f683f78dd5aca9b42291f4ebcd3638342d8e3a215dbfc42d60c3533` |
| New framework `build.json` | `f8f9e0eefdeb29126641a92620eb1c2a710b5dbad6431fe3f9fd623b8db5c4e9` |
| Framework JAR | `e2bea62dcd6f59269c36612f76b806942018700f37fbf202915cc2e74329a54a` |
| Framework DEX | `478976ee0cd5130abd4eb9433c44ded33c0e8840b2095bb674b2520efbfa1881` |
| Raw AutofillManager | `ad60ec49f52eb7071445df19d07ad8dc8113c4c299595e88b59f5f95b496aec1` |
| Canonical AutofillManager | `5cbb514cbb04e4e030f951561a179ee8d4cd2474071fb743557b3a6f8a42a130` |
| Retained native manifest | `f7140d2ff09d77906a2ef76884c607f64643e53cc981f16dcae90d474128f8f1` |
| Retained native DSO | `c87ccc623d70b1d582cd5486a9a6316c5117091ca10113682aa07cc72c80912f` |

The immutable SDK receipt records source revision
`c58ed4fc08041c4e18ed375d785d4e07a67d820e`, containing both the core and producer
commits. Its frozen sources match the committed blobs. Builder and production
controls are at `S/autofill-service-framework-builder-2026-11-02-r1` and
`S/autofill-service-framework-production-2026-11-02-r1`.

One joint seal and separate fresh-process readback passed eight complete closed
caller, core-check, fixture/control, producer, SDK and original native roots:
9,492 typed entries. The root list is
`S/autofill-service-producers-sealed-2026-11-02-r1/roots.txt`; its
`sealed/manifest.json` hashes to
`2f0e52279bbcd9553139330441dde90f839a6734423267e0f125a5a777b87be5`.
Seal/readback took 0.949/0.696 seconds at sampled RSS 17,530,880/23,937,024 bytes
and observed growth 3,870,720/1,396,736 bytes, with zero guard/child exits,
complete cleanup and zero swaps under unchanged 600 MiB/900-second/64 MiB-growth/
1 GiB-reserve limits. Historical source and native provenance remain intact.

The complete fresh SDK/native gate passed all 70 raw and canonical equalities,
with zero formatting differences. The only changed class remains outside that
consumed membership. The audit also verifies all 91 native source origins,
92 inputs, 721 exports, generated JNI/C, complete helper closures and all
58 consumed C/header inputs: generated C plus 57 headers. The retained DSO
remains coupled to its original 2,108-class DeviceSecure SDK, manifest
`db98d6fcd6e0c792761f39b07ceb40d5e5818b691dede6eaccd177ec0f9973f2`.
No native rebuild or relink occurred. The admission source and its frozen copy
have identical SHA-256 `7ab125b046d92bbd88b2d562719b00e1a0d293e7dedc760c80f437b5eed04cc9`.
Original provenance is preserved separately from the Java successor.

The fresh compatibility audit is
`S/maps-autofill-service-tools-2026-11-02-r1/framework-audit.guard.json`, SHA-256
`c4b91039a383cf696a73dc459520d7518ee2c8e843da8d7dc98ce7ff0a1e8637`;
its complete log hashes to
`8b5fe629336aba6b88002a3059e2e785392f725bf9bf9d210a7bf70384fa2cdb`.
That tools bundle's complete qualification and seal are reported separately by
the media profile. This report establishes host SDK/native compatibility and
evidence retention; ARM execution, GMS stability, Google authentication and
current Maps imagery remain separate runtime checks.
