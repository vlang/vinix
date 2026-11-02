# Keyguard-policy Maps media qualification

This profile adds DevicePolicyManager's disabled-keyguard-features query. It
returns zero because no backing policy service exists. All ten existing methods
remain. The scope is one added method in one class, with no replacements, fields
or class additions; canonical membership stays 2,110. The zero feature mask skips
the audited GMS trust-agent branch. Missing trust-agent APIs and PersistableBundle
remain outside this implementation. Core is `0a6d6d564`, producer `d8b6cf50b`,
fixture `775607ca3`, delivery `9397257d7` and
[SDK/native pair](keyguard-policy-pair-2026-11-02.md) `0e4b72c43`.

The six-file Java overlay inherits `maps-autofill-service-r1`, audits all 114
inherited complete inventories and requires exactly 116 dependency seals. It
appends module 50 after all 49 retained modules. The actual 43-stage ancestry
reaches the original `maps-account-r5` inode inventory. JAR, DEX, framework
build/inventory, headless input receipt and deployment receipt change. Five
existing deployment inputs and only the framework manifest identity change.
Both active DSO and historical headless native pin remain unchanged.

The complete fresh framework audit admits only DevicePolicyManager. It is outside
native membership: all 70 native-consumed raw and canonical classes remain equal,
with zero formatting deltas. The exact native bundle, 91 source origins, 92
inputs, 721 exports, generated JNI, C, headers and complete helper closures stay
unchanged. The consumed inventory checks generated C and all 57 header inputs.
Native provenance remains the original 2,108-class device-secure SDK. Historical
profiles, complete bundles and their original auditors remain required.

| Artifact | SHA256 |
| --- | --- |
| Prepared autofill parent | `07771e1494d1ef834246c2d9c5f919af1c39043c75086af9e3a218e8e2fc8661` |
| New SDK manifest | `13ef4747529ec6d0d3669a3ad059e6eee82bf99b80900b835b7de2d40a007a92` |
| Retained native manifest | `f7140d2ff09d77906a2ef76884c607f64643e53cc981f16dcae90d474128f8f1` |
| Retained native DSO | `c87ccc623d70b1d582cd5486a9a6316c5117091ca10113682aa07cc72c80912f` |
| Qualified stager | `d6140e55c9363687029b928f916cd54d4e2ede95d1fbc34dae5a101363a6d731` |
| Qualified kernel patcher | `655dbc176ec97cb9c1f2843f792817ecc213cda31ebce3e0ff4187868377c0d3` |

Required checks passed on first attempts: fresh serial V/C builds, stager
selftests, complete SDK/native/header/helper audits, all historical and new
kernel profile/FAT selftests, exact 114-root positive/refusal/full-byte tests
including node 113, actual ancestry, and discovery of 284 V / 408 C stager inputs
and 273 V / 405 C patcher inputs. Complete original/copy/recheck capture retained
862 inputs. The protected test parent existed before invocation. Current sources
match their frozen compiled copies. Independent source contract review approved.
The full native audit took 2.19 seconds with zero raw differences. No compiler or
Java process overlapped the owned VM or another task-owned compilation lane.

Complete tool evidence remains outside Git at
`/Users/alex/.local/state/vinix/android/maps-keyguard-policy-tools-2026-11-02-r1`
and `maps-keyguard-policy-inventory-batches-tests-2026-11-02-r1`. The separate
producer/source seal is
`3e23a9d56853a11562afb223955f330db2107fb9dce4e1b7fa1182ad4a5a3f6a`.
The tool and batch roots passed sealing and a separate fresh-process readback:
two roots, 10,444 entries, manifest
`97e367f92ac7a5fd500425d91711d81418f7af7ef13e3c7ab21d7442266a6b1e`
at `maps-keyguard-policy-tools-sealed-2026-11-02-r1/sealed/manifest.json`.
Both guard/child exits are zero, reasons empty and cleanup complete under the
unchanged 64 MiB growth cap and 1 GiB reserve. Final independent source/artifact
review confirmed all 27 pre-seal guards and time logs, source equality, real
114-root tests, 36 FAT cases and the full native proof without a discrepancy.

Every guard and child exited zero with complete cleanup. Maximum sampled
aggregate RSS was 497,041,408 bytes; the detailed maximum was 498,679,808 bytes,
with zero swaps. Original limits remain: 600 MiB RSS, 300 seconds for
builds/tests, 900 seconds for full audits, 1 GiB reserve, 512 MiB tool growth,
64 MiB seal growth and shell file cap 16777216. Compilers were serialized and
stopped before handoff. The source base before this tool commit is
`0e4b72c439b5f893e7ce55fa2b2403900a625f5a`. Image preparation and ARM/live Maps
validation belong to the parent task; this report claims no ARM keyguard-policy,
account, checkin or imagery result.
