# Keyguard policy fixture delivery, 2026-11-02

The additive runner selector `--keyguard-policy` requires the successor
framework, retained native pair and signed fixture. Transfer selector
`serve --keyguard-policy-api` exposes exactly `/keyguard-policy-api-run` and
`/keyguard-policy.apk`. Historical profiles, routes and pins remain unchanged.

The exact success marker is:

```text
KEYGUARD-POLICY-PASS cached-manager public-instance zero-flags null-admin component-preservation trust-mask dormant-config unmanaged-controls
```

The fixture uses real cached DevicePolicyManager clients with null and actual
ComponentName arguments. It checks the public instance integer query, zero mask,
component preservation, and the called `0x10` guard returning false before the
retained unresolved trust-agent configuration reference. Existing unmanaged
owner/profile/admin and device-credential controls remain exercised. There is no
backing policy service, fake administrator, trust configuration or platform APK
stub. The generic runner retains six protected input identities, eleven receipt
checks, isolated identity/data/home/surface, explicit environment, closed inherited
descriptors, 180/20-second deadlines, 4 MiB log and 8,192-byte line limits, one
exact PASS/READY pair, drained EOF and clean child exit. Health diagnostics remain
unchanged. Host qualification does not establish ARM, GMS, Maps or authentication.

Paths below use `S=/Users/alex/.local/state/vinix/android`.

| Input | Path below S | SHA-256 |
| --- | --- | --- |
| Framework | `combined-account-webview-keyguard-policy-framework-2026-11-02-r1/api-impl.jar` | `1ff4080bbfdc95c4c370e88b3b283f004f165f4a93c816e224d823e98f7dc4b4` |
| Native | `current-native-build-2026-11-02-asset-locales-r1/native/libvinix-android-native.so` | `c87ccc623d70b1d582cd5486a9a6316c5117091ca10113682aa07cc72c80912f` |
| Fixture | `keyguard-policy-fixture-2026-11-02-r1/probe.apk` | `e02a832fa82b6531fe8928d119e6113bc1abfe94c722e020f4ede1b4179f0454` |
| ARM runner | `keyguard-policy-api-run-2026-11-02-r1/run` | `35177750c4935e36001810f24281377e0c83a609677b45476a518ce4639027b4` |
| Transfer | `keyguard-policy-api-transfer-build-2026-11-02-r1/transfer` | `0b4ff7204cebee209909168f0a0e4e6ba2c8e2be8a58905bb4e2e0d033251ec8` |

The fixture build receipt hashes to
`0fd31a84498ecacb324fb58ff5900ddce95d4783a189133d18f0739494c916b4`.
All five qualification phases passed on their first attempts. The runner
selftest rejected 3,093 malformed/mixed/failure cases. Transfer tests retain
historical binary snapshots, GET-only requests, traversal and absolute deadlines,
adding exact selector/port refusal and route/path/hash uniqueness checks. ELF
inspection confirms static AArch64 EXEC without INTERP or DYNAMIC segments.

| Check | Guard seconds | Sampled aggregate RSS bytes | Time maximum bytes |
| --- | ---: | ---: | ---: |
| Host runner compile | 1.383 | 356,532,224 | 365,494,272 |
| Runner selftest | 1.049 | 21,954,560 | 17,907,712 |
| Static ARM runner compile | 1.831 | 375,717,888 | 370,196,480 |
| Host transfer compile | 1.637 | 382,140,416 | 407,289,856 |
| Transfer selftest | 1.068 | 10,731,520 | 10,682,368 |

Every guard/child exit is zero, reason empty, cleanup complete and swaps zero
under the original 600 MiB RSS, 300-second, 512 MiB shared-growth, 1 GiB reserve,
4 MiB output and shell file-size cap 16777216 limits. Compilers were serialized.
SDK manifest/build/JAR/DEX, fixture receipt/APK, native, tool and predecessor pins
were independently rehashed before and after qualification. Frozen sources equal
the checkout. Runner source base is `d8b6cf50b4700179a5c105048c9c41d5159209bd`;
transfer source base is `775607ca3d6bb69bbd88a4d80bc7d245cb191fbd`.
Their source hashes are respectively
`7a2f0068f8da7f6b046091bf1940f6c739c70706f18eee8d60d43fe3f487e909`
and `c63a2d9ffffb12b0e3594eb7e5076455029d933db29eff309b4dc93d61eafe5c`.

Four complete tool/control roots passed sealing and separate fresh-process
readback for 35 entries. The manifest at
`S/keyguard-policy-api-tools-sealed-2026-11-02-r1/manifest.json` hashes to
`8fcd2489ba0535a03cd51ac57b88c24350a9a2f4bb6eb37d6de7e6eedffdcc5f`.
Seal/readback guards took 53/540 ms, both guard/child exits zero and cleanup
complete under the same RSS/reserve/output/file caps and 64 MiB growth. Controls
remain in `S/keyguard-policy-api-tools-seal-controls-2026-11-02-r1`.
Independent source, final artifact and report reviews approved the exact pins,
marker, unchanged health policy, static ELF, guards, source copies and recipe.

## Guest recipe

Verify that `keyguard-policy-probe`, UID/GID 10145, the dedicated runtime mount
and output path are absent. Provision and confirm the exact account:

```sh
grep -nE '(^keyguard-policy-probe:|:10145:)' /etc/passwd /etc/group
/usr/sbin/addgroup -g 10145 keyguard-policy-probe
/usr/sbin/adduser -D -H -u 10145 -G keyguard-policy-probe -s /bin/false keyguard-policy-probe
grep -nE '^keyguard-policy-probe:' /etc/passwd /etc/group
grep ' /opt/keyguard-policy-runtime ' /proc/self/mounts
test ! -e /var/lib/keyguard-policy-r1
mkdir /opt/keyguard-policy-runtime
mount -o bind /opt/vinix-android-aarch64 /opt/keyguard-policy-runtime
mount -o remount,bind,ro,nosuid,nodev,strictatime,wxallowed none /opt/keyguard-policy-runtime
grep ' /opt/keyguard-policy-runtime ' /proc/self/mounts
mkdir -p /opt/input
```

Require read-only `nosuid,nodev,wxallowed` attachment without `noexec`. Start the
qualified host transfer with a fresh output only when the guest is ready to fetch:

```sh
S=/Users/alex/.local/state/vinix/android
"$S/keyguard-policy-api-transfer-build-2026-11-02-r1/transfer" serve --keyguard-policy-api "$S/keyguard-policy-api-transfer-live-2026-11-02-r1" 55537
```

Download and verify both hashes before launch:

```sh
wget -O /opt/input/keyguard-policy-run http://10.0.2.2:55537/keyguard-policy-api-run
wget -O /opt/input/keyguard-policy.apk http://10.0.2.2:55537/keyguard-policy.apk
chmod 755 /opt/input/keyguard-policy-run
chmod 644 /opt/input/keyguard-policy.apk
sha256sum /opt/input/keyguard-policy-run /opt/input/keyguard-policy.apk
/opt/input/keyguard-policy-run --keyguard-policy /opt/keyguard-policy-runtime /opt/input/keyguard-policy.apk 10145 10145 /var/lib/keyguard-policy-r1
```

Keep guest input idle through UART export END. Preserve the full UART and derive
one exact interval using [uart-snapshot.md](uart-snapshot.md). The unchanged
no-removal diagnostic import must retain all chunks and validate the exact six
identities, eleven checks, complete child log and clean exit; it does not extend
strict fixture-protocol qualification. Release with
`umount /opt/keyguard-policy-runtime` after validation before separate GMS/Maps.
Preserve failures without weakening diagnostics.
