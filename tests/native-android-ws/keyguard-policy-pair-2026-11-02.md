# Keyguard policy SDK successor

The [preceding GMS run](maps-autofill-service-runtime-2026-11-02.md) reached a
missing `DevicePolicyManager.getKeyguardDisabledFeatures(ComponentName)` query.
Core `0a6d6d564` supplies the absent-backend result zero for null and named
administrators. GMS's audited helper masks bit `0x10`, returns false for zero and
skips its separate trust-agent configuration branch. The
[focused source checks](../native-android-tools/keyguard-policy-source-check.md)
record that boundary. No policy service, enrolled administrator, trust-agent,
keyguard enforcement or authentication result is supplied.

Producer `d8b6cf50b` adds `--keyguard-policy` over the exact autofill-service SDK.
It adds one public instance method in DevicePolicyManager, replaces no methods
and adds no fields or classes. Membership remains 2,110. Raw and canonical
oracles require exactly three registers, integer zero and an integer return.
Complete class/member/metadata and non-DEX JAR comparisons preserve everything
else. The pure provider and framework registration/helper source are frozen and
rechecked. Historical profiles remain unchanged. Independent source and complete
produced-artifact reviews passed, confirming all ten prior policy methods.

| Operation | Guard seconds | Sampled RSS bytes | Detailed RSS bytes |
| --- | ---: | ---: | ---: |
| Producer compile | 1.609 | 371,900,416 | 401,768,448 |
| Complete producer self-tests | 0.269 | 15,613,952 | 14,352,384 |
| Complete SDK production | 42.816 | 500,318,208 | 487,129,088 |
| Complete SDK/native compatibility audit | 2.228 | 52,051,968 | 50,790,400 |

All four phases passed on their first attempts, with zero guard/child exits,
complete cleanup and zero swaps. Production observed 206,905,344 bytes shared
disk growth. Limits stayed 600 MiB aggregate RSS, 300 seconds for builds/tests,
900 seconds for the complete audit, 1 GiB reserve, 4 MiB output and file cap
16777216; tool/SDK growth remained 512 MiB/1 GiB.

Paths below use `S=/Users/alex/.local/state/vinix/android`. The complete SDK is
`S/combined-account-webview-keyguard-policy-framework-2026-11-02-r1`.

| Artifact | SHA-256 |
| --- | --- |
| Baseline autofill-service manifest | `df8ec5e67f683f78dd5aca9b42291f4ebcd3638342d8e3a215dbfc42d60c3533` |
| New framework manifest | `13ef4747529ec6d0d3669a3ad059e6eee82bf99b80900b835b7de2d40a007a92` |
| Framework `build.json` | `7747e2e504b5fdd4ed898c37893109aa229c868a2ed6b65d5171af1c88a11e50` |
| Framework JAR | `1ff4080bbfdc95c4c370e88b3b283f004f165f4a93c816e224d823e98f7dc4b4` |
| Framework DEX | `bfe67aa6c3fc3091d539484ecefaaf1385a58bdc04aed7a3a70bdacdf709a052` |
| Raw DevicePolicyManager | `2740ae5926de638c5becfb0f5cb1c13b7c724370514d14837004032ac0ddaa40` |
| Canonical DevicePolicyManager | `5f98acfca8319619f8c97d1d50d7ab90a68967acf438b9f532168a8eb4fc0317` |

The immutable SDK receipt records producer revision
`d8b6cf50b4700179a5c105048c9c41d5159209bd`, containing core `0a6d6d564`.
Current, frozen and committed source pins agree. Builder/provider closures
retain 271/143 entries. Complete controls remain at
`S/keyguard-policy-framework-builder-2026-11-02-r1` and
`S/keyguard-policy-framework-production-2026-11-02-r1`.

One joint seal and a separate fresh-process readback passed eight complete
closed caller, core-check, fixture/control, producer, SDK and original native
roots: 9,487 typed entries. The root list is
`S/keyguard-policy-producers-sealed-2026-11-02-r1/roots.txt`; its
`sealed/manifest.json` hashes to
`3e23a9d56853a11562afb223955f330db2107fb9dce4e1b7fa1182ad4a5a3f6a`.
Seal/readback took 1.011/0.548 seconds at sampled RSS 23,855,104/24,805,376 bytes
and observed growth 3,997,696/1,343,488 bytes, with zero guard/child exits,
complete cleanup and zero swaps under unchanged 600 MiB/900-second/64 MiB-growth/
1 GiB-reserve limits. Historical source and native provenance remain intact.

DevicePolicyManager is outside the retained native bundle's 70 consumed classes.
The unchanged locale native DSO retains SHA-256
`c87ccc623d70b1d582cd5486a9a6316c5117091ca10113682aa07cc72c80912f`,
manifest `f7140d2ff09d77906a2ef76884c607f64643e53cc981f16dcae90d474128f8f1`
and its original 2,108-class DeviceSecure SDK provenance, manifest
`db98d6fcd6e0c792761f39b07ceb40d5e5818b691dede6eaccd177ec0f9973f2`.
The complete fresh SDK/native gate passed all 70 raw and canonical equalities
with zero formatting differences. It also verifies unchanged 91 native source
origins, 92 inputs, 721 exports, generated JNI/C, complete helper closures and
58 consumed C/header inputs: generated C plus 57 headers. No native rebuild or
relink occurred. Original native provenance stays distinct from the Java SDK.

The fresh admission receipt is
`S/maps-keyguard-policy-tools-2026-11-02-r1/framework-audit.guard.json`, SHA-256
`4dc1b15ad36295661bba8f9a4ad7f0d1270b622db0c574c4f0a376177a505359`;
its complete log hashes to
`70f796712c089496a65f5734aa5241ac637060e7ffcdf5739e6280d135330b6e`.
Current and frozen admission source hash identically to
`3fe1e7ffeee0ce4dd58ea9770094e2ea9b89b1f9e3faf917f03dfee72cde4d30`.
Complete image-tool qualification and its seal are reported by the media
profile separately. This report establishes host SDK/native compatibility and
evidence retention; ARM execution, GMS stability, Google authentication and
current Maps imagery remain separate runtime checks.
