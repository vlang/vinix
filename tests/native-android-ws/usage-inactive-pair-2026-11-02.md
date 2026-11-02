# Disabled AppStandby query and retained native

The API-28 GMS network-scheduler path calls the missing
`UsageStatsManager.isAppInactive(String)`. Core `a2fbc6b5c` adds the public
instance query with the target's explicit disabled-AppStandby result: false
before any package lookup or validation, including null, empty and unknown
names. This classifies no AppStandby inactivity restriction; it establishes no
installation, foreground state, recent use, usage history or permission grant.
The bounded caller audit found no additional certain adjacent API. The
[source report](../native-android-tools/usage-inactive-source-check.md) records
the API-28 policy and independent source checks.

Producer `6bcc38b11` adds `--usage-inactive` over the exact Secure-settings SDK.
Its independent raw and canonical oracles require the exact public instance
boolean signature, three registers and false result. They preserve the sole
constructor and all metadata, reject argument-dependent behavior and invented
history state, and retain all 2,112 classes. Complete class/member/JAR checks
permit only this method addition, before and after full API-28 DEX assembly.
Independent source and produced-artifact review approved, including the whole
canonical tree and streamed JAR DEX. Only `classes.dex` changes inside the JAR.

| Admitted operation | Guard seconds | Sampled RSS bytes | Detailed RSS bytes |
| --- | ---: | ---: | ---: |
| Fresh producer compile | 1.699 | 377,683,968 | 409,075,712 |
| Complete producer self-tests | 0.302 | 15,532,032 | 14,401,536 |
| Complete SDK production | 44.443 | 499,286,016 | 489,160,704 |
| Complete retained-native admission | 2.549 | 51,216,384 | 55,607,296 |

Producer compile, self-tests and SDK production passed their first attempts
with zero guard/child exits, complete cleanup and zero swaps. Production
observed 304,164,864 bytes shared disk
growth. Original limits remain 600 MiB aggregate RSS, 300-second build/test,
1 GiB reserve, 4 MiB output, file cap 16777216 and 512 MiB/1 GiB tool/SDK
growth ceilings. Complete compiler, source/helper and smali-tool inputs remain
in the retained inventories; host SDK and dynamic libraries remain documented
environmental dependencies.

Paths below use `S=/Users/alex/.local/state/vinix/android`; the complete SDK is
`S/combined-account-webview-usage-inactive-framework-2026-11-02-r1`.

| Artifact | SHA-256 |
| --- | --- |
| Baseline Secure-settings SDK manifest | `0c7485f9a38c52dd6ef6ddd60c936f49d694da267ae30fccf6dea1163a21529b` |
| New SDK manifest | `bfadac214671937539a4732b3ca6be22d561c366b96a72a9de045fc362aba1fe` |
| SDK `build.json` | `ca4e6ef0b40adb682bd523ca4a3c24c7bceba3ae81667448ca38fda4f1e4beeb` |
| Framework JAR | `d7b6d8c37d5d09d200c19b429f07cf6666ed6d8cf5a1a1b4d29c0dfd27cd632b` |
| Framework DEX | `214a30cc0daaa59f2dea3395321288dc0127c14eb4bb993cc2ea920efe4744b6` |
| Raw UsageStatsManager | `2694087a4d3bf7130bdaec2b12450b89f95138ceaa5a4c0d6c4fd9f495fd75db` |
| Canonical UsageStatsManager | `069e3ac3375487f084f0cc5770c1787376ee9e36c1190b4e70beb441fb799433` |

The immutable SDK receipt records source revision
`6bcc38b1176e4738fe1dedfbfb07bd5a04aa574e`, containing core `a2fbc6b5c`.
Current, committed and frozen producer/provider/integration pins match. Complete
builder/provider source closures contain 271/143 entries. Complete controls
remain at `S/usage-inactive-framework-builder-2026-11-02-r1` and
`S/usage-inactive-framework-production-2026-11-02-r1`.

Eight complete roots passed joint sealing and a separate fresh-process
readback: 7,763 typed entries covering caller audit, source checks, fixture and
controls, producer controls, SDK and the complete failed first seal attempt.
The root list is `S/usage-inactive-producers-sealed-2026-11-02-r2/roots.txt`;
its `sealed/manifest.json` hashes to
`4e8473aa32690b2afaad9ee1bb2fa4a00b460a5194c17651d16d6bcb86632eab`.
Seal/readback took 0.678/0.511 seconds, sampled 23,494,656/14,499,840 bytes RSS
and observed 3,141,632/2,035,712 bytes shared disk growth. Guards/children
exited zero with complete cleanup under unchanged 600 MiB/900-second/64 MiB
growth/1 GiB reserve limits. First seal r1 stopped after 0.566 seconds on
78,090,240 bytes observed shared growth, with guard125/child137 and complete
cleanup. Its partial manifest is unqualified; the whole failed root is retained
inside successful r2. Source/artifact bytes and limits stayed unchanged. The
complete parent Secure-settings bundle remains a required dependency.

The retained native bundle remains
`S/current-native-build-2026-11-02-broadcast-permission-r1`, with manifest
`e371c8d365b78493f9f9d660ceceb1cb2b1382eaa60cae06bcbe4aad0c6c233b`
and DSO `29b2631c36a4a8c802e904e936c23e090fb2de3b5019ac93548df1b15de2a8f1`.
Its original broadcast-SDK provenance remains
`49daffbfa9dc1dcc598e453eaae3611df7702963aa5b659022545149af7132d5`.
No native rebuild or relink occurs for this Java-only addition. The complete
original broadcast/native bundles remain required at their twelve-root seal,
`b755b2951d12e064f648b6baa872019aba414dfe61739c65197500382d9ef67d`.

The full retained-native admission passes all 70 canonical equalities. Exactly
two raw formatting pairs come from the canonical clone; the remaining 68 raw
classes stay equal. The query class is outside generated membership. Complete
ContextImpl preservation also protects its manual native theme/resource/
loaded-app field and method references; UserManager and StatusBarManager remain
unchanged. No native implementation, binding or provenance changes.

| Consumed class | Original raw SHA-256 | Successor raw SHA-256 |
| --- | --- | --- |
| Context | `3819dd399a1ac9e8fba32ada045cc250f670f4fa012d765126ded7d1acbba0e8` | `60fdbab8aef10711d65afa9a0ddf5e64369ae21e0f9010291288109ebc305ab5` |
| ATLLoadedApp | `3e133e9cf9a3a2271bfef87917f2060c14b40a550dfb6f760c5b4278580b729f` | `6e8d9800711ae17e8b8a86de267590c2bb702d7d6fe8db870c57e6a599e5b0bd` |

The gate verifies the original 91-origin/92-input native source map, 721 exports,
generated JNI/C, all 58 consumed C/header inputs and complete 650/340-entry
builder/generator helper closures. The retained bundle remains coupled to its
original broadcast SDK. Admission guard/child exits are zero, cleanup is
complete, swaps are zero and observed shared growth is 20,480 bytes, under
unchanged 600 MiB/900-second/512 MiB growth/1 GiB reserve limits.

Actual admission evidence is
`S/maps-usage-inactive-tools-2026-11-02-r1/framework-audit.guard.json`, SHA-256
`781d433791d64d0db9999d3d160a25bc90cca983ae833680d23319d80d4c07c9`;
its complete log hashes to
`49ca1ed6c51c90e0bad5ddf6ec9c3c8191d23a1f5a358a35b642dfa8cd772e40`.
Current and frozen admission source both hash to
`117ad6fb90425b471b448716b9e7dd0db098c88027839951a50a104540e9af33`.
Complete media-tool qualification is reported separately. ARM execution, GMS
stability, authentication and current map imagery remain separate runtime
checks.
