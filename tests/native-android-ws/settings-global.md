# Settings.Global integer writes

The native Maps trace VM r2 reached a concrete Play Services linkage failure:
`Settings$Global.putInt(ContentResolver,String,int)` was missing. The captured
exception is in
`/Users/alex/.local/state/vinix/android/maps-native-onboarding-trace-vm-r2/broker-failure-types-01.png`.

The sealed broadcast-result framework's Global class has ten methods and two
fields, with no write APIs. Its `NameValueTable` parent provides only a
constructor. `ContentResolver.insert` already delegates to a registered
provider and returns null when the authority has no provider. There is no
default settings provider in `ContentProvider.createContentProviders`.

The narrow transform appends only `Global.putInt`, preserving every existing
method and field. It converts the integer with `Integer.toString`, inserts a
`ContentValues` containing the two String entries `name` and `value` at
`Global.CONTENT_URI`, and returns whether the provider returned a URI. Missing
providers and `SQLException` return false; permission and argument exceptions
remain visible. Provider persistence, duplicate replacement and permission
checks stay with the provider. This change adds no process-local settings store
and does not change the existing placeholder getters.

The conversion, table-entry shape and database-error boundary follow the
[AOSP Settings implementation](https://android.googlesource.com/platform/frameworks/base/+/d542705/core/java/android/provider/Settings.java).
The [Global API contract](https://developer.android.com/reference/android/provider/Settings.Global#putInt(android.content.ContentResolver,%20java.lang.String,%20int))
requires string storage and a false result for database failure. Unlike the
AOSP helper's optimistic insert return, this runtime explicitly checks null:
its resolver uses null to report an absent provider.

## Host validation

The tested source snapshot was prepared from repository base
`118ae87db450bd922dade893d08c4bddcd7c52d4`; the implementation and fixture are
committed with this report. Exact tested copies remain in the bundle's `source`
directory. Input is the sealed framework at
`/Users/alex/.local/state/vinix/android/combined-account-webview-broadcast-result-framework-2026-10-27-r1/smali`.

Passed checks:

- Exact append-only transform, preserved ten methods/two fields, rejection of
  already transformed or incompatible input, and single-class DEX assembly.
- Fresh standalone signed APK with only `Main` and `SettingsResolver`; separate
  APK signature verification and byte-identical DEX disassembly/reassembly.
- The fixture tests API linkage, virtual insert delivery, exact URI and two
  actual String values, zero, negative one, integer extremes, repeated keys,
  null insertion result, `SQLException`, `SecurityException` identity and the
  real absent-provider path. Its terminal marker is `SETTINGS-GLOBAL-PASS`.

The retained compiler is
`/Users/alex/code/v-tccbin-bootstrap-20261026/v`, SHA-256
`0cc6c1d34c1811a818e4ae89853116861a4b067d4251af257851a7714f0d11fe`,
with its own adjacent V root and explicit `VROOT`, `V` and
`VINIX_V_COMPILER`. Host commands ran under `bounded-command-r3` with a 1 GiB
aggregate RSS limit, 1 GiB disk reserve and 512 MiB growth budget. Checker
compilation peaked at 191,086,592 bytes RSS; fixture compilation at 347,406,336;
checker/assembly at 90,701,824; and signed APK generation at 115,539,968. All
four `/usr/bin/time -l` records report zero swaps. Every guard receipt reports
exit zero and complete cleanup.

The complete host bundle, including tested sources, executables, APK, signing
inputs, roundtrip files and original command logs/receipts, is retained at
`/Users/alex/.local/state/vinix/android/settings-global-checks-2026-10-27-r1`.
Its external archive is the same path with `.tar.gz`, SHA-256
`3fc42f839165c6e2b7d4940cceb4f62ea5388e721136956c2c18535bd6b93908`.
The APK is `apk/probe.apk`, SHA-256
`c3e912e4e05c2af28d6d64d1fcb46874136a6164f7e2e19cc5ba1b62d950fedd`.

ART execution, the next Play Services startup, Maps navigation and Google
account authentication remain pending. Host assembly does not prove those
runtime outcomes or settings persistence.
