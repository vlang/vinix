# Resource synchronization ARM fixture

The V generator in `resourcelockfixture/` produces a standalone resourceful APK
for the native resource adapter synchronization change. Host qualification passes;
ARM execution remains pending. This fixture does not establish the cause of the
Maps crash, successful map rendering, or Google authentication.

Four workers start together and synchronize at each of 64 bounded iterations.
Two independently owned AssetManagers receive configuration changes and actual
native asset-set replacements, while two readers assert packaged resource IDs,
full/package/type/entry names, strings, integer/string/reference arrays, typed
array bags, XML, directory listings, and Java/NDK asset bytes. Replacement uses
the retained native method through JNI, avoiding the duplicate-path fast return.
Raw themes retain application-attribute apply and same-owner copy checks, plus
framework-attribute source, same-owner and cross-owner copy checks. Every present
value must be type 0x1c/data 0xff123456. Copy destinations must first lack the
tested attribute, so no-op copies fail. All handles use production JNI cleanup.

The test-only V JNI helper opens one independently owned Asset and AssetDir
before starting workers. After all workers join it checks all 21 asset bytes,
EOF, and the exact two directory names, then releases both handles. Its only
direct C manager operation is that pre-worker directory open. Concurrent manager
operations enter the production adapter. Theme cleanup deletes every allocated
handle while preserving the original JNI exception or first cleanup failure.
Worker failures report role, iteration and API stage. Startup and iteration
barriers have 10-second timeouts, overall completion has 90 seconds, and each
join has one second. Timeout diagnostics snapshot every worker; a holder with
active workers is left for process teardown rather than closed before joins.

The XML check strictly asserts the retained parser's first `next()` result is
START_DOCUMENT (0), then the second is START_TAG (2), followed by the exact
`proof` root, unnamespaced `answer="locked"` attribute, and close. Each XML
operation has a distinct diagnostic stage. No event, literal resource,
concurrency, ownership, iteration, timeout or guard assertion was relaxed.

The fixture calls the same strict `nativeThemes` serially before held handles
or workers are created. On any theme failure the test-only helper emits one
fixed-token diagnostic, at most 139 bytes, containing the exact phase, returned
cookie, expected presence, type/data, and pending-exception bit. It explicitly
flushes C output before returning false. The diagnostic prefix contains no
`-FAIL`, so it does not trigger the runner before native cleanup completes.
Negative cookies are authoritative; fields are not read after an absent lookup
or pending JNI exception. Unavailable cookies use INT32_MIN, fields use
type=-1/data=0, and setup-only expectations use -1.

R6 uses public `android:colorForeground` (0x01010030) for the cross-owner literal
color. The retained C API requires shared ApkAssets object identities to remap
application keys across owners; framework keys with literal values do not need
that map ([retained Theme::SetTo](https://gitlab.com/android_translation_layer/art_standalone/-/raw/e78bf68917bcaaf58fef3960cd88793b3b7f39cc/libandroidfw/AssetManager2.cpp)).
This still exercises cross-manager operation scopes and the resource
locks. The parentless style has exactly two items: the original application key
and the public framework key. The signed oracle asserts both exact values and
the same seven application resource IDs. Application-key copying across owners
with separately loaded ApkAssets is outside this fixture's positive claim.

Final evidence is outside Git under
`/Users/alex/.local/state/vinix/android/resource-lock-fixture-2026-11-01-r6` and
`resource-lock-fixture-controls-2026-11-01-r6` beneath the same state directory.
The build observed source revision `848b3cbf799773e60fb394d0bf93b5c4b81992fb`;
its complete generator bytes are archived and pinned in `build.json`.

| Input or artifact | SHA-256 |
| --- | --- |
| `main.v` | `8212523e74ffe4cc46dedc72bc7a03db458ee4a5adddfa68d0971ab1f7b0f1cc` |
| `sources.v` | `eb6d3c973e1367b54cc4bd3130816181195abcc26d96665d1954fde8ec04d158` |
| `resourcelockprobe/probe.v` | `c4eda6d46fd5b9129597c6db097fcd3a1233766bf309b6136d3b1247925a4a34` |
| Signed `probe.apk` | `eedcc5a40c86f2f6131121e922a7625e416f5df68671baa70cea581246c3e55e` |
| `build.json` | `3b969c0dbe6bc2830106069652e24de0ae91f4792618a1d4c03d8cb0ed1c6838` |
| Bundled `lib/arm64-v8a/libresource-lock-probe.so` | `983890fd9b7b20a31bad4f2f633157fb23f42f405fa328ce10b2aa15b5250516` |

The signed package is `org.vinix.bootstrap`, activity `.Main`, min SDK 29,
target SDK 35. Its sole success marker is:

```text
RESOURCE-LOCKS-PASS workers=4 iterations=64 ids names strings arrays bags themes same-app-copy cross-framework-copy configuration paths owned-asset owned-directory
```

Host checks cover APK v3 signing, badging, exact seven-entry signed resource
table and XML values, two canonical two-class DEX roundtrips, signed-extracted
DEX/helper/assets equality, ELF64/AArch64 JNI exports, two 4-KiB-aligned LOAD
segments, no additional DT_NEEDED libraries, retained libandroidfw exports, and
all input readbacks. Native generation uses the retained legacy compiler
`109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e`,
the original freestanding module flags, and namespaced V lifecycle symbols.
Standard NDK declarations are generated by V with the production wrapper types.
Loading follows the existing bootstrap assetprobe APK/System.loadLibrary path;
the helper is not added to the production runtime ABI.

Both final guards and children exited 0 with cleanup complete. Builder compilation
took 2.557 seconds, sampled 337,592,320 bytes RSS (time high-water 354,549,760),
and observed 12,906,496 bytes shared-volume growth. APK production took 13.444
seconds, sampled 103,596,032 bytes RSS and observed 142,327,808 bytes growth.
Both recorded zero swaps. Original limits remained 600 MiB RSS, 300 seconds,
512 MiB growth, 1 GiB reserve, 4 MiB command output, and file limit 16,777,216.

The r1 roots preserve a failed helper compile due to missing standard NDK
declarations. The r2 roots preserve a failed signed-resource checker that
incorrectly counted the next resource type header inside a style bag. The final
parser recognizes type boundaries and checks exact array/string/attribute/XML
values. Neither failed attempt is admitted as a passing build. All r1/r2
artifact and control directories remain unchanged.

The original r3 host-passing APK
`bafc5f4e708f15fdb0d2868d8b332863c7ce429f1447952867968300e58e12dd`
and build receipt
`a1cd7b14482f007d3bb189e33c499b3dd3efe4fd495f97c1d547efd1112af270`
remain immutable. Its first ARM run failed because both readers asserted the
first XML `next()` was START_TAG; it was START_DOCUMENT, as the consumed
`XmlBlock$Parser` source specifies. The later mutator barrier timeouts were
secondary. IDs, names, strings, arrays and bags preceding XML returned, but
the complete ARM fixture failed. The 10,948-byte original log is preserved at
`/Users/alex/.local/state/vinix/android/maps-resource-lock-runtime-audit-2026-11-01-r1/failed-fixture-decoded-r1/child.log`,
SHA-256 `86e0392e99b7a0c7907f20bdca2a1473ab0bd2692b691e8b0118af242b34a470`.
R4 changed only fixture XML sequencing and diagnostic labels; its native helper
was byte-identical. Its ARM retry passed the XML and preceding resource reads,
then both readers failed at iteration 0 in `raw-theme-same-and-cross-copy`;
mutator barrier timeouts were secondary. That 11,000-byte original log remains at
`/Users/alex/.local/state/vinix/android/maps-resource-lock-runtime-audit-2026-11-01-r2/failed-fixture-decoded-r1/child.log`,
SHA-256 `ce16e26c383b2066ff8d285c4ec6ff8147e426e21e4bd3e8644d1884ba6379e9`.
The r4 APK `ef4188b65ffd8fd5c2c0b4c71494b45cec3dea9038bc4d2853ae3daa726c1da1`
and build `de1210a74c5475ff29d86dcf83de0a5a88c3c375ec917e16458b317af15cb683`
remain immutable. R5 then observed the exact failure in serial preflight:
`phase=cross-B2 cookie=-1 expected_present=1 type=0xffffffff data=0x00000000 pending=0`.
The prior absent/apply/same-owner checks had returned, and no workers or held
handles had started. Its 10,069-byte original log remains at
`/Users/alex/.local/state/vinix/android/maps-resource-lock-runtime-audit-2026-11-01-r3/failed-fixture-decoded-r2/child.log`,
SHA-256 `8badf5cf8bbf558a54a6d3059cd59dde00a9e600b422036da7e84cda402d47a2`.
The r5 APK `b90fe510799ddf4d550c1915d3a730ab2db3aacbcdc95122c2862a85afdb814f`
and build `b3f15545d0fb8ef340ef9500bec19044c82a31ca93a4b55626e63f91f4822704`
preserve the failed custom-key oracle. R6 corrects that setup prerequisite only;
the production framework, native library and prepared image remain unchanged.
Concurrency, lifetime, XML, iteration, timeout and guard checks are unchanged.
