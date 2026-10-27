# Explicit service metadata regression

Source `c58cdfba6` resolves explicit service components through the existing
`getServiceInfo` metadata loader before entering the intent-filter loop. Services
without filters can resolve, multiple filters yield one result, and a missing
explicit component cannot fall through to another action match.
`MATCH_DISABLED_COMPONENTS` (`0x200`) includes disabled components/applications
without changing their metadata. Implicit resolution and visibility stay intact.

The retained GMS APK SHA-256 is
`a34d6a3ccea3ceba491369517e8f12e11df3791e86fec38b1cdf693785e35707`.
Its `DirectBootHelperService` is disabled, unexported, not direct-boot aware and
has no filters. Normal application attachment selects `fqoz`'s explicit helper
query with flags `0x10000200`. An empty result reports locked before consulting
`UserManager`. This leads to `InvalidConfigException: not migrated with user
locked`, later masked as `A Chimera Context is required`. Correcting this startup
defect does not establish success in subsequent startup or Google login paths.

`check-service-query.v` passed against the retained protected-storage r2
framework: only the named method changes, the implicit body is preserved,
malformed/repeated inputs are rejected, and the changed class assembles.
Evidence is `/Users/alex/.local/state/vinix/android/check-service-query-r1.log`.
The combined builder self-test also passed with the exact service-query profile.

The sealed successor is at
`/Users/alex/.local/state/vinix/android/combined-account-webview-service-query-framework-2026-10-27-r1`.
Source revision: `c58cdfba6d9de55e14bdbd1cd8eee8f0fada033e`.

| Artifact | SHA-256 |
| --- | --- |
| Complete `sha256.json` | `12f21e139e2602fa9517c6df7d2fda866d366d4d5f0cce6d7e07d62bbd044559` |
| `api-impl.jar` | `74892a013cb72fdaef39852325a3fa46db217fbcd3a4f11fcba4cc7272b2a50b` |
| `classes.dex` | `c453e3b480a6dbd0295a46b2a29f5ada5f7d0f7ee8c2bc07b5b9a76355d43e5e` |

The producer verifies all 2104 classes before/after DEX roundtrip: only
`PackageManager.queryIntentServices(Intent,int)` changes, without added methods,
fields or classes; other JAR entries stay identical. It retains source closures,
tool/compiler identities and receipts. The run took 89.36 seconds and peaked at
493 MB RSS, using a 512 MB Java heap and two workers. It performed no guest run.

`service-query-fixture.v` builds a generic signed client and disabled companion.
It checks enabled/unexported services without filters, disabled service and app
inclusion, unchanged disabled metadata, multifilter single results, missing
components despite matching actions, component package selection, the retained
implicit branch and `ContextWrapper` delegation. Constructors throw if metadata
lookup instantiates services or the companion Application.

Signed APKs, input identities, manifest dumps and DEX roundtrips are at
`/Users/alex/.local/state/vinix/android/service-query-fixture-2026-10-27-r1`.
Complete inventory SHA-256:
`27050d7a8649e8ee7fe996007334a06a9ad957a4d1cf78fb4f90a43419a1200c`.
Client APK SHA-256:
`890de9d4ff410aaf5cd87a52b630ccfa7280fd3c0b2b38eee57159d525b1565d`.
Disabled companion APK SHA-256:
`e5075f571f3b8334dded40accb08257ccfdf83e8526a7b61e502d586daa66048`.

For ART execution, copy the companion into a fresh app-data directory as
`_installed_apks_/org.vinix.servicequery.disabled.apk`, then launch only the client
with `run-android CLIENT_APK -l org/vinix/servicequery/Main -w 64 -h 64`.
Use the selected runtime, an isolated fixture principal/data/home, a private
surface and a held input pipe. Require the exact `pass_marker` from `build.json`
once, without assertion, verifier or uncaught errors. ART execution and real
Google account login remain pending for this fixture bundle.
