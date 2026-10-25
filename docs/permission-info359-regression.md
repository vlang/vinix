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

| Source or baseline | SHA-256 |
| --- | --- |
| `framework_permission_info.v` | `c1899b8db95d3fca1f79e361828879c5da6a77b7a3c0d2c537483ca2fe2b67f5` |
| `startupfixture/permission_info.v` | `c9dfd9d8008f46bc8e6b98e67932595d637ca25b0c345b4919a069790295b614` |
| Qualified353 complete bundle manifest | `22bc4e713113d41a7ab56a1809293fb9f3ccb11fd8cc8c8c589fc20afd19171f` |
| Qualified353 framework JAR | `1e5467f57ac9a3a51a9f29f7c73bf4896b47dc1ea055f59d07db1e1d281cfa83` |

## Build, ART and Maps status

The standalone builder is committed as `d7d8dcb60`, with frozen compiler-root
correction `ae652e427`. The same-APK ART harness is committed as `bea726cc3` and
has compiled successfully. Compilation does not establish guest behavior.

No final framework359 JAR exists yet. Build attempts stopped before framework
work at the unchanged 768 MiB free-space gate; the last reported availability
was 631,088 KiB. The complete framework build, same-APK old/new native ART runs
and separate Maps replay remain pending. Final artifact pins, actual outcomes
and complete readback results must be recorded after execution. The completed
source/host evidence does not establish resolution of Maps' permission failure
or later service teardown in a guest.
