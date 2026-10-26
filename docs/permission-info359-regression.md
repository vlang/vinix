# Permission metadata lookup regression359

Fix `2390bacfe4323edd84d04e0ed110977fadc75753` replaces the unconditional null
`PackageManager.getPermissionInfo(String, int)` stub with lookup of parsed
permission declarations. System declarations are searched first, followed by
installed packages using the existing metadata-loading and visibility policy.
Matches use the declared permission name, independent of its package prefix.
Permission trees and requested-only names do not count as concrete permission
declarations. Every result is a defensive `PermissionInfo` copy; `GET_META_DATA`
copies the Bundle when present, and other lookups clear metadata. Unknown names
throw a fresh `NameNotFoundException(name)`.

## Observed caller and contract

[Maps358](maps358-fortified-loader-replay.md) failed after native index
initialization with a null `PermissionInfo.protectionLevel` access. The retained
Google Play Services APK is SHA-256
`a34d6a3ccea3ceba491369517e8f12e11df3791e86fec38b1cdf693785e35707`,
matching the actual replay input. Its `classes2.dex` is
`a9f2ff847667cb5df29120366b0ca502668902d9f420c73831ac8063caaaa4c1`.
Disassembly shows `cqza.f()` querying `android.permission.READ_CONTACTS` through
`dhlp.b()` and `dhlp.a()`. The latter catches only `NameNotFoundException` around
the lookup, then reads `protectionLevel` outside that catch. A missing-name
exception logs the unknown permission and returns denied; the null stub instead
causes the observed NPE. This fix supplies metadata and does not grant permission.

The public [PackageManager API](https://developer.android.com/reference/android/content/pm/PackageManager#getPermissionInfo(java.lang.String,%20int))
requires `NameNotFoundException` for an unknown name. The pinned
[AOSP application boundary](https://android.googlesource.com/platform/frameworks/base/+/d969cc68560bbec8d17c610b9330155ea8c65624/core/java/android/app/ApplicationPackageManager.java)
returns a nonnull service result or throws that exception. The retained353
framework manifest declares READ_CONTACTS as dangerous (`1`) and INTERNET as
normal (`0`); these are real parsed declarations rather than synthetic entries.
Selected caller evidence is retained under
`/Users/alex/.local/state/vinix/android/maps358-permission-callers-2026-10-26`.

## Regression and source validation

The committed fixture reproduces the initial READ_CONTACTS lookup and field read,
catching only `NameNotFoundException`, before any positive marker. Further stages
check system protection levels, declarations with names unrelated to the app's
package, ordinary and signature protection, fresh result objects, metadata flag
handling, independent metadata Bundles, unknown-name exception messages and
identity, and rejection of requested-only names and permission trees. The fixture
does not require a second APK; visible companion enumeration is covered by source
review rather than an ART fixture assertion.

Independent review checked parsed-package fields, declaration/tree distinction,
existing loading policy, metadata copying, Smali registers and the fixture's
failure isolation. An isolated V driver compiled successfully, generated the
modified PackageManager and both fixture classes, and assembled/disassembled them
with the retained353 Smali tools at API28. Duplicate provider application was
rejected without file mutation. This is host source/Smali validation, separate
from a complete framework build and native ART execution.

The complete 23-file host diagnostic bundle is
`/Users/alex/.local/state/vinix/android/permission-info359-source-check-2026-10-26`.
Its manifest is
`d45410e804425f611b7a7588ce5f72ad887abffb27cfd1d84b5dfc33be6aab08`.
Own and root independent readbacks with the unchanged complete-bundle checker
passed every file hash and the exact file set, both exiting 0. Their adjacent
receipts are `permission-info359-source-check-own-readback-2026-10-26.json` and
`permission-info359-source-check-root-readback-2026-10-26.json`.

| Source or artifact | SHA-256 |
| --- | --- |
| `framework_permission_info.v` | `c1899b8db95d3fca1f79e361828879c5da6a77b7a3c0d2c537483ca2fe2b67f5` |
| `startupfixture/permission_info.v` | `c9dfd9d8008f46bc8e6b98e67932595d637ca25b0c345b4919a069790295b614` |
| Qualified353 complete bundle manifest | `22bc4e713113d41a7ab56a1809293fb9f3ccb11fd8cc8c8c589fc20afd19171f` |
| Qualified353 framework JAR | `1e5467f57ac9a3a51a9f29f7c73bf4896b47dc1ea055f59d07db1e1d281cfa83` |
| Executed framework359 builder source | `e2cbbd637be4a52e758eb9f66705ee7e7a50d8c4f2709aca8e226146435c30e1` |
| Framework359 complete bundle manifest | `7a2ae7763e71f702ccc1a50b3b63cf444a0e37d8b6a800e77c80866d3ba9dccc` |
| Fixed359 framework JAR | `88fdf06964bfbd3815d824ab5ff5517887e58de3eb3eb47986d99806fbe6c2fc` |
| Independent complete build-readback receipt | `e7db2798e440011f1ef7bd632276b91fe2f19daf3a7280d95c1fff0bb4b733b1` |

## Complete framework build

The standalone builder, originally `d7d8dcb60` and corrected in
`ae652e42769dce32cdbf62f3c610bf56fa8376ec`, completed attempt4 successfully.
The sealed 14,862-file bundle is
`/Users/alex/.local/state/vinix/android/permission-info359-framework-build-attempt4-2026-10-26`.
It retains the complete qualified353 baseline. Original, clone and post-build
baseline readbacks passed. Frozen provider/helper inputs and both builder and
driver V source closures passed their before/after checks. SDK/JDK libraries
remain environmental inputs.

Complete DEX comparison retains all 2,073 classes, changes only PackageManager,
and adds or removes no classes. Only `classes.dex` changes among the three
extracted regular JAR members; ancillary members match the baseline. Duplicate
provider application again fails without mutation. The builder's complete final
readback exited 0 with every file hash and exact set matching; its adjacent
receipt is `permission-info359-framework-build-attempt4-2026-10-26-own-readback.json`.
Independent final readback also exited 0 and matched all 14,862 file hashes and
the exact set, with checker identity verified before and after. Its adjacent
receipt is `permission-info359-framework-builder-peer-readback-2026-10-26.json`.

## ART and Maps status

The same-APK ART harness is committed as `bea726cc3`. Preparation completed with
exit 0 after its unchanged 1,024 MiB gate passed. Runner and fixture-driver V
source closures matched before and after compilation; all APK packaging and
signature checks passed. Both variants use the same signed APK and Native351
runtime; only the framework JAR differs.

The actual old-framework ART action completed with outer exit 0 and
`PERMISSION-INFO-OLD-EXPECTED-RESULT-PASS`. Its raw guest result was
`startup_failed`: the app exited 1 after the exact READ_CONTACTS
`PermissionInfo.protectionLevel` null-field NPE at `PermissionInfoEntry.check`.
Serial contains one BEGIN and no positive fixture markers, reproducing the
baseline failure.

The new-framework action also completed with outer exit 0. All six positive
fixture markers appeared once in order, followed by `ANDROID-WS-READY`.
The final raw result was `window_observed` for the full 35 seconds, with
`backend_ready=true`, `process_exited=false`, QEMU alive before capture and no
failure markers. `functional_passed` remains null in that generic raw result;
the separate semantic receipt reports `expected-result-pass`. Old and new
runtime input inventories each matched before and after execution.

| ART input or result | SHA-256 |
| --- | --- |
| Signed fixture APK | `334020c1b46570f266cd3d3ef89320431f33b4284970f05a2cdbbe0d0cb685f1` |
| Checked runner | `bf0d2656c5cd5b7e7e0f463a72fbc63334fdeefe91a1b6c7e9b871e5efcae91a` |
| `old-semantic-check.json` | `c33971ef1b05dc7adf6acbb206579d970a940b5b5a7b513cc90de880bf60a074` |
| `new-semantic-check.json` | `20c0c4a7dd96f9bda618e49ba82be2423a90dd67b7521cf6d162f762baf808fe` |
| Old serial | `f39f96a42f4c552d6a52cba05632125b77557bda2501f08ac22aa8a99987cf70` |
| New serial | `9489cfbf46cf0443560682149aa70c6ad1c484687481fc73ead4937c9ada84b8` |
| Complete ART bundle manifest | `01aa44a3e5ca9281379329c185e38aa43ca148c00cb5e0edd2382946d1a43661` |
| Root ART readback receipt | `3a568c938f3b370a80be31cf4bb22b6a1470ebc49f84ec789cb3bf297b6d28c1` |
| Independent ART readback receipt | `9160b32049e5df0697b2b5cce2239bf5e72af8be72377b801635129f36fdfd3f` |

The sealed 16,081-file regression bundle is retained under
`/Users/alex/.local/state/vinix/android/permission-info359-fixture-2026-10-26`.
Sealing exited 0 after revalidating both variants; the qualification copies of
their semantic receipts retain the exact hashes above. Root and independent
complete readbacks each exited 0, matching all 16,081 file hashes and the exact
file set with the unchanged complete-bundle checker. Their adjacent receipts are
`permission-info359-fixture-root-readback-2026-10-26.json` and
`permission-info359-fixture-peer-readback-2026-10-26.json`.
Adjacent preparation and action logs are
`permission-info359-fixture-prepare-2026-10-26.log`,
`permission-info359-fixture-old-2026-10-26.log` and
`permission-info359-fixture-new-2026-10-26.log`.

[Maps360](maps360-permission-metadata-replay.md) subsequently completed its
generation and replay. The previous permission exception was absent: Maps
displayed the map and an Oasis d'Aboukir search suggestion, then exited after
92 seconds with a separate `Parcel.readBundle` class-loader failure for
`com.google.firebase.appindexing.internal.Thing`. Its raw outcome remains
`startup_failed`; collection success does not establish a working Maps session.
The separate service teardown correction was not included in that replay.
