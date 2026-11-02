# Subscription service Maps media qualification

This profile adds a shared cached SubscriptionManager for string and typed
ContextImpl lookups, protected by an explicit monitor. Active subscription list
and info queries return null for the absent backend; phone-number lookup raises
the specified IllegalStateException. TelephonyManager adds zero phone/modem
counts and a fresh wrapper carrying the requested subscription ID. Its 24
existing methods remain unchanged. A public final, memberless SubscriptionInfo
is the sole new class. The exact scope is three changed classes, two replaced
methods, seven added methods and two private fields, growing canonical SDK
membership from 2,109 to 2,110. Core source is `bf4a357a6`; producer is `8dd3331d1`.

The six-file Java overlay inherits `maps-stats-unavailable-r1`. It audits all
110 inherited complete inventories, requires exactly 112 dependency seals and
appends module 48 after all 47 retained modules. The actual 41-stage ancestry
reaches the original `maps-account-r5` inode inventory. JAR, DEX, framework
build/inventory, headless input receipt and deployment receipt change. Five
existing deployment inputs and only the framework manifest identity change;
both the active DSO and historical headless native pin remain unchanged.

The complete fresh framework audit admits only the four named classes. All are
outside native membership. All 70 native-consumed raw and canonical classes
remain equal, with zero formatting deltas. The exact native bundle, 91 source
origins, 92 inputs, 721 exports, generated JNI, C, headers and complete helper
closures remain unchanged. The consumed inventory checks generated C and all
57 header inputs. Native provenance remains the original 2,108-class device-secure
SDK, distinct from both Java successors. Historical profiles, complete bundles
and their original auditors remain required.

| Artifact | SHA256 |
| --- | --- |
| Prepared Stats parent | `2b9878f541cf483519060f3699641b17184b012938edab52b597821e41fd88e8` |
| New SDK manifest | `958e5a7c02710a3aa78a04b499f6c6d5ca4701e1c2c8d33b7dda6f640ac561db` |
| Retained native manifest | `f7140d2ff09d77906a2ef76884c607f64643e53cc981f16dcae90d474128f8f1` |
| Retained native DSO | `c87ccc623d70b1d582cd5486a9a6316c5117091ca10113682aa07cc72c80912f` |
| Qualified stager | `9df047de46820374e488f18827cc9e810814c093e71a0dff90adabb47cd473ce` |
| Qualified kernel patcher | `a7622b96912e3ffcde60b3d8efa02a1c0c7bf9d24b40d487965ce298429d2a54` |
| Complete tool evidence manifest | `b2b3d67b4b794717d9ee5dd4855ed3fa9ab46f5a3381bd04651e15e53d1b94f1` |

Required checks passed on first attempts: fresh serial V/C builds, stager
selftests and complete SDK/native/header/helper audits, all historical and new
kernel profile/FAT selftests, exact 110-root positive/refusal/full-byte tests
including node 109, actual ancestry, and discovery of 284 V / 408 C stager inputs
and 273 V / 405 C patcher inputs. Complete original/copy/recheck capture retained
862 inputs. The protected test parent existed before invocation. All six current
sources match their compiled frozen copies. Independent initial and complete
six-path draft reviews approved. The full native audit took 3.97 seconds in the
time log. Its reuse admission preceded runner qualification, with compiler lanes
released between phases.

Complete tool evidence is outside Git at
`/Users/alex/.local/state/vinix/android/maps-subscription-service-tools-2026-11-02-r1`
and `maps-subscription-service-inventory-batches-tests-2026-11-02-r1`. Their
two-root seal and separate fresh readback passed 9,304 entries; the manifest is
`maps-subscription-service-tools-sealed-2026-11-02-r1/sealed/manifest.json`.
The separate eight-root producer seal is
`175fac12b7a3c9bcc95a600463df857ca69f3a0300faa43b15c3f4c52afeba8a`.
The source revision before this tool commit was
`5e78f8f7ee13e86acb685d0ac125a8165ffc506b`.

Every admitted guard and child exited zero with complete cleanup. Maximum
sampled aggregate RSS was 482,181,120 bytes; the compiler's recorded maximum was
482,443,264 bytes, with zero compiler swaps. Original limits remain: 600 MiB
aggregate RSS, 300 seconds for builds/tests, 900 seconds for full audits, 1 GiB
reserve, 512 MiB tool growth, 64 MiB seal growth and shell file cap 16777216.
Compilers were serialized and stopped before handoff. The parent task owns image
preparation and ARM/live Maps validation; this report claims no ARM subscription,
cache, exception, account, checkin or imagery result.
