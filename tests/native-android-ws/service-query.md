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

`service-query-run.v` is a separate root fixture controller transferred after
boot; it does not change the six-file diagnostic image overlay. It pins the
two signed APKs and corrected JAR, creates fresh target-owned data/home and a
private 64×64 surface, and uses the existing launcher for permanent UID/GID,
group and capability changes. The child receives only an explicit fixture
environment and pipe-backed stdin/stdout/stderr; inherited descriptors above
stdio are closed. No account registry, authenticator or browser channel is set.

The parent limits output to 4 MiB and lines to 8192 bytes. It waits up to 180
seconds for the exact fixture pass marker and native WS readiness once, then
closes stdin and allows 20 seconds for clean shutdown. It drains output through
EOF, rejects exception/error markers and verifies clean wait status. Failure
cleanup kills the owned process group while the direct child is still unreaped.
Only `child.log` and `receipt.json` leave the guest in checksummed atomic serial
frames prefixed `VINIX-SERVICE-QUERY-RESULTS-1`. Application data stays local.

Host checker self-test passed 23 malformed/error cases. Static AArch64 build
took 3.38 seconds and peaked at 359 MB RSS. Independent source review passed;
ART execution remains pending. Source SHA-256:
`27b31609282bd86ccb05fa1108734778662e64d3bbca5d9e862962bb2a05f7ba`.
Runner evidence is retained at
`/Users/alex/.local/state/vinix/android/service-query-run-2026-10-27-r1`.
Static runner SHA-256:
`8ef76b9e4c9f1eb0cc84780eaa0b618a3a70f317cd4f0e87824ddcdffcae8727`.

Build with the retained compiler and ARM musl compiler:

```sh
/Users/alex/code/v-tccbin-bootstrap-20261026/v -new-compiler -nocache \
  -os linux -arch arm64 -cc /opt/homebrew/bin/aarch64-linux-musl-gcc \
  -gc none -cflags -static -ldflags -static -o NEW_EXTERNAL_RUNNER \
  tests/native-android-ws/service-query-run.v
```

Transfer the pinned runner and APKs into a new root-owned directory under
`/var/lib` (0755 directory/runner, 0644 APKs). All ancestors must be root-owned,
target-traversable and not group/other writable. Provision an unused Unix
user/group in 10000..19999, for example 10117. The selected runtime must already
have the existing readonly/nosuid/nodev/`wxallowed` attachment policy; the native
launcher's `VINIX_ALLOW_WX=1` alone does not grant executable mount admission.
Then, as root, with a fresh result directory:

```sh
/var/lib/service-query-input-r1/run /opt/vinix-android-aarch64 \
  /var/lib/service-query-input-r1/client.apk \
  /var/lib/service-query-input-r1/disabled.apk \
  10117 10117 /var/lib/service-query-result-r1
```
