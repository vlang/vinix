# Broadcast-permission Maps media qualification

This profile installs the Java permission-aware broadcast overload, the primary
APK permission snapshot in ATLLoadedApp, and the fieldless VinixBroadcastPolicy
utility. Context keeps its existing native overload. Only Context and ATLLoadedApp
change, with one new utility: 2,110 classes become 2,111. Core is `0b00959bc`,
producer `84a791b70`; the [SDK](broadcast-permission-sdk-2026-11-02.md) and
[native](broadcast-permission-native-2026-11-02.md) reports record the fresh producers.

The overlay inherits `maps-keyguard-policy-r1`, audits all 116 complete inherited
inventories and requires exactly 119 dependency seals. It appends module 51 after
50 retained modules. The actual 44-stage ancestry reaches the original
`maps-account-r5` inode inventory. Nine files replace the JAR, DEX, DSO, current
framework/native metadata, seven-key headless input map and deployment receipt.
Exactly eight existing deployment inputs change. Only JAR and DSO change in the
headless input map. Historical bundles and their original checkers stay required;
the new metadata carries no headless fixture PASS claim.

Both changed classes are native-consumed, so this profile requires a distinct
native build coupled directly to the new SDK. It audits all 70 fresh native
copies, exactly two raw and canonical changes, and the other 68 unchanged classes.
The added utility remains outside that membership. The original native bundle is
separately audited against its original DeviceSecure SDK. Native source origins
(91), current inputs (92), exports (721), JNI and generated C remain equal.
All 58 consumed C/header values remain equal; exactly five local metadata keys
are rebased to the fresh root, while 53 external keys stay fixed. The complete
builder closure changes from 644 to 650 entries through exactly six additions and
two changes; the normalized 340-entry generator closure remains equal.

| Artifact | SHA256 |
| --- | --- |
| Prepared keyguard parent | `2732a540e40cb95b944eee58ee17c18dc5c20d4fa7909960c19a9d724c1576de` |
| New SDK manifest | `49daffbfa9dc1dcc598e453eaae3611df7702963aa5b659022545149af7132d5` |
| Fresh native manifest | `e371c8d365b78493f9f9d660ceceb1cb2b1382eaa60cae06bcbe4aad0c6c233b` |
| Fresh native DSO | `29b2631c36a4a8c802e904e936c23e090fb2de3b5019ac93548df1b15de2a8f1` |
| Qualified stager | `31b5b9569a144bc6c2ef2ca4a8c0a9eb16d931e93fa8e7eb6e189385af213f64` |
| Qualified kernel patcher | `2db080b8316a89eb8ab9b50891f2a06747b9c45e8e2bea52689e0fb1f84b8a67` |

Required checks passed: serial V/C builds, stager selftests, full
SDK/native/header/helper audits, 44 kernel receipt/profile checks, 37 FAT cases,
exact 116-root positive/refusal/full-byte tests including node 115, actual
ancestry, and post-build discovery of 284 V / 408 C stager inputs and
273 V / 405 C patcher inputs. Complete original/copy/recheck capture retained 866
inputs. The protected batch test parent existed before invocation. Independent
source/native reviews approved the scope; final sources match the retry snapshot.

The first patcher generation failed because a new mutation test shallow-copied a
map containing arrays. Its source, receipt, log and partial project remain intact.
Only that test allocation changed to the established deep-copy pattern. Fresh
generation, emitted C compilation and the entire patcher suite then passed in
`sources-r2` / `patcher-project-r2`. A guard invocation with an invalid generated
root was rejected before launching the selftest and corrected before execution.
All 30 actual guard receipts were reviewed: 29 pass, one preserved compile
failure, with complete cleanup throughout. Maximum sampled aggregate RSS was
505,380,864 bytes; detailed maximum 501,170,176 bytes, with zero swaps.

Evidence remains outside Git at
`/Users/alex/.local/state/vinix/android/maps-broadcast-permission-tools-2026-11-02-r1`
and `maps-broadcast-permission-inventory-batches-tests-2026-11-02-r1`. The
producer/source seal is
`b755b2951d12e064f648b6baa872019aba414dfe61739c65197500382d9ef67d`.
Both closed tool roots passed sealing and a separate fresh-process readback:
two roots, 11,118 entries, manifest
`71f37c11194a8ca68f078775021c00e470a20828ab2faed3e5614822caccd5b2`
at `maps-broadcast-permission-tools-sealed-2026-11-02-r1/sealed/manifest.json`.
Both seal/readback guard and child exits are zero, reasons empty and cleanup
complete under the original 64 MiB growth ceiling and 1 GiB reserve.

Original limits remain: 600 MiB RSS, 300 seconds for builds/tests, 900 seconds for
full audits, 1 GiB reserve, 512 MiB tool growth, 64 MiB seal growth and shell file
cap 16777216. Compilers were serialized and stopped before handoff. The source
base before this tool commit is `12ebe4dfe66da02e9da1c4a2b425b4be847987b8`.
Image preparation and ARM/live Maps validation belong to the parent task; this
report claims no ARM broadcast-permission, account, checkin or imagery result.
