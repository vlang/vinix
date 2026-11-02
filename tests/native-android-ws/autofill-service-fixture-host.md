# Autofill service query fixture host qualification

The fixture exercises `AutofillManager.getAutofillServiceComponentName()` through
real typed service lookups in Activity, application and Activity contexts, with
three cycles per context. Each lookup must return the platform manager class and
each component query must return null for the absent backend. Reflection requires
a public instance method returning the real `ComponentName` class. An invoked
GMS-like caller takes the null-to-false branch before its retained component
package-name continuation; its `RuntimeException` catch does not catch a missing
API's `NoSuchMethodError`.

Controls retain the existing null string-service lookup, all four inactive
notifications, callback registration/unregistration, and a subsequent null query.
Ordinary `AutofillValue` text, toggle, list and 64-bit date values remain positive
controls. The APK contains only `org.vinix.bootstrap.Main`; it supplies no platform
class or autofill provider. The current manager has no `isEnabled` or
`hasEnabledAutofillServices` API, so this fixture makes no claim about those APIs,
provider availability, Google Play Services or authentication. ARM execution is
still required.

The V builder and production pass succeeded on their first attempts under the
unchanged 600 MiB aggregate RSS, 300-second, 512 MiB observed-growth, 1 GiB reserve,
4 MiB output and file-size 16777216 limits. Compile guard elapsed 1.251 seconds,
sampled RSS 309,346,304 bytes and detailed maximum 358,154,240 bytes. Production
elapsed 5.850 seconds, sampled RSS 87,998,464 bytes and detailed maximum 93,487,104
bytes. Both guard/child exits are zero, cleanup is complete and swaps are zero.
No compiler or Java process remained at handoff.

API-28 assembly, two disassemblies around a reassembly, canonical class equality,
source-reference assertions, exact single-class membership, v3 APK signature and
signed-DEX extraction passed. Production and signed-extracted DEX match; the
canonical roundtrip DEX has its separate identity. Every recorded source/tool
input was rehashed after production. Current sources match the frozen copies.
Independent source and generated-artifact reviews passed.

Paths below use `S=/Users/alex/.local/state/vinix/android`.

| Artifact | SHA-256 |
| --- | --- |
| `S/autofill-service-fixture-2026-11-02-r1/probe.apk` | `e9e3e6ce83e99f439550d494438fb3d245d67d74be3f915dcecf83b7c452e360` |
| Build receipt | `2e2041b34354fcb6ac7e0e8105b1e54eb23caa3c585df482a0135ce5f2ba1359` |
| Production / signed-extracted DEX | `2451ef7de0a40421afc36a7c129adb209d0d5189af54eae7e9131866d4b6dd03` |
| Canonical roundtrip DEX | `d591cf14c113f1c088ea06f112390cae01c16ccd506470c1ba7ddbd0e751d043` |
| Both canonical Main classes | `351499f6739caac81ef0a8c0b2620e60ef7bcd0884dfd17fba9305515a5403ef` |

Complete artifact and input closure is retained in the fixture directory; guard
receipts and logs are in `S/autofill-service-fixture-controls-2026-11-02-r1`.
The build records source revision `eff7b719af19bf402391bd62428ef46a11b637d6`.
Its exact success marker is:

```text
AUTOFILL-SERVICE-PASS typed-manager string-null component-null public-instance null-branch notifications typed-values
```
