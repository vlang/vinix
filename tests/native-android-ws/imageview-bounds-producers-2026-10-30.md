# ImageView bounds framework and native producer

The narrow producer from `05fb503af` built the ImageView provider from
`52f558171` over the complete sealed platform-fragment framework. Both final
producers record source revision `52f55817144cda6c30bffcc0e03dccf2b2d09287`.
Exactly one of 2,105 classes changes: ImageView's four-argument constructor and
two maximum setters change; two getters and two private fields are added.
All other classes, retained members and non-DEX JAR entries remain unchanged.
The public constructor/getter/setter ABI is checked before and after DEX roundtrip.

Paths below are relative to `/Users/alex/.local/state/vinix/android` (`S`):

- Builder, frozen source and controls (`B`):
  `S/imageview-bounds-framework-builder-2026-10-30-r1`.
- Framework (`P`):
  `S/combined-account-webview-imageview-bounds-framework-2026-10-30-r1`.
- Native producer (`N`): `S/current-native-build-2026-10-30-imageview-bounds-r1`.
- Native controls (`C`): `S/native-imageview-bounds-build-2026-10-30-r1`.

| Artifact | SHA-256 |
| --- | --- |
| `B/tools/builder` | `b32737b32b795305571d797efabe9be2e8b5a596fc16312e852bc7fb8d9f1c81` |
| `P/sha256.json` | `95853b2f31ac34f731c8c31fc1251fd695ed6d856a8bfef0f71041efc10273e0` |
| `P/build.json` | `aa8594f4f07818e8c289fc7ce0caa96007bfa2984f9a310e895e1dd911746f4e` |
| `P/api-impl.jar` | `9cfdbeaff047b693837508c3f7676510a63c05af118e864964b4b432fb813af9` |
| `P/classes.dex` | `fb8ec08f3830293c3859ca043d9296ada34fecb3fe2cb7f11c3ed03dfa69e474` |
| `N/sha256.json` | `d7d8ac996d63b2bd8ad8f6b658a32ae23903ebb9e248297d219f46f6df8f59c8` |
| `N/build.json` | `c5d2428b0f9ac1e66e702d29957b6c5b347030fa495e4adf375bffed50310a1c` |
| `N/native/libvinix-android-native.so` | `fd38d7f8e3c0d17934617242cb95b0412a0c6ed676cb4454e5a52c8cf494dc2c` |

The source-matching native bootstrap remains
`S/native-auth-worker-build-2026-10-29-r1/tools/bootstrap`, SHA-256
`87fdd3470d639f1456eae758da4555b3f402a3adceea7793893d0c932d86d12d`.
The native builder source remains
`a468758d4957f66703836da209b901e1344a2f889b27c2df868630d97adc4d33`.
ImageView belongs to its 68 consumed classes, so a fresh coupled native producer
was built. The complete native source directory, generated JNI and bindings
remain byte-identical to the predecessor. Consumed raw sources differ in
ImageView and Activity; Activity's raw difference is its inherited canonical
formatting, with no canonical class change. The complete framework comparison
permits only ImageView's semantic delta.

| Phase | Seconds | Peak sampled aggregate RSS, bytes | Time maximum RSS, bytes |
| --- | ---: | ---: | ---: |
| Builder compile | 6.451 | 363,855,872 | 365,641,728 |
| Full framework producer | 173.766 | 503,529,472 | 491,995,136 |
| Coupled native producer | 214.282 | 629,096,448 | 395,968,512 |

The builder selftests, framework production and native production all passed,
with guard/child status zero, complete cleanup and zero time-reported swaps.
Limits stayed at 600 MiB aggregate RSS, 300 seconds and a 1 GiB disk reserve.
The native sampled peak was 49,152 bytes below the cap. Observed shared-volume
growth was 600,301,568 bytes for framework production (1 GiB allowance) and
243,466,240 bytes for native production (2 GiB allowance); these measurements
do not isolate producer writes. Compile/selftest retained a 512 MiB allowance.
No failed producer attempt or cap increase occurred.

The complete compiler/source closures, actual commands, inventories and input
rechecks remain in the closed original bundles. Host SDK and dynamic libraries
remain recorded environmental dependencies. Host production and DEX checks do
not establish ART fixture execution, map rendering or Google authentication.

All four roots and their 9,256 typed entries are bound by
`S/imageview-bounds-producers-sealed-2026-10-30-r1/sealed/manifest.json`, SHA-256
`eea737145174e4c5d2656a1369b9c49be27f956d4e5112ad560faba65adab90d`.
The complete seal/inline check and a separate fresh-process full readback passed
in 7.836/1.757 seconds, with sampled aggregate RSS 22,740,992/14,516,224 bytes,
exits 0/0, complete cleanup and zero swaps. Limits stayed at 600 MiB RSS,
900 seconds, 64 MiB observed shared-volume growth and a 1 GiB reserve.
Keep the complete original bundles unchanged; this report does not replace them.
