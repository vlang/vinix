# WebView provider-package fixture delivery

The additive runner selector `--webview-package` selects the new WebView
framework, freshly coupled native library and separate signed regression.
Transfer selector `serve --webview-package-api` exposes exactly
`/webview-package-api-run` and `/webview-package.apk`. Historical selectors,
routes and pins remain unchanged, including the exact Messenger v1/v2 shared
APK exception.

The [one-Main fixture](webview-package-fixture-host.md) checks the public static
nullable PackageInfo query on the Activity thread and a bounded plain worker,
then after existing WebView construction, settings access, JavaScript changes,
one local static-data load and destruction. It restores the original JavaScript
setting and preserves an original failure through cleanup. It does not measure
visual rendering, browser-engine availability, Google module completion, Maps,
accounts or authentication.

The exact success marker is:

```text
WEBVIEW-PACKAGE-PASS public-static nullable-no-provider cold-repeat off-ui bounded-worker settings-identity javascript-preserved static-data-smoke destroyed-requery
```

Six protected inputs, eleven receipt checks, isolated identity/data/home/surface,
explicit environment, closed inherited descriptors, 180/20-second deadlines,
4 MiB log and 8,192-byte line limits, exact PASS/READY pair, drained EOF and clean
child exit remain required. Health diagnostics remain unchanged apart from
recognition and rejection of conflicting WebView package PASS markers.

Host qualification passed all five phases on the first attempt. The runner
selftest rejected 4,691 malformed, mixed-profile and failure cases. Transfer
tests preserve binary snapshots, GET-only requests, traversal and absolute
deadlines, adding exact selector/port refusals and path/hash/URL uniqueness
checks against every predecessor. ELF readback confirms static AArch64 EXEC
without INTERP or DYNAMIC segments. ART execution remains pending.

Paths below use `S=/Users/alex/.local/state/vinix/android`.

| Input | Path below S | SHA-256 |
| --- | --- | --- |
| Framework | `combined-account-webview-webview-package-framework-2026-11-03-r1/api-impl.jar` | `0e5e2632bc64ad9d548379491c59ed4e8a91d42fcfa6677b75aae4798dfeb7a9` |
| Fresh native | `current-native-build-2026-11-03-webview-package-r2/native/libvinix-android-native.so` | `e72e10edd8fed637ec0053100afe535aca7ad6a763e5cd311e712d4d2362c8c2` |
| Fixture | `webview-package-fixture-2026-11-03-r1/probe.apk` | `896cd9dbec8ccde28d3e0363c1a77ad593708c3ef7e73cf57001e2ae19327579` |
| ARM runner | `webview-package-api-run-2026-11-03-r1/run` | `b62f42bc279412b845884875d57f1b63a10ec31a8c9d1fcfbab69af7fcd444fa` |
| Transfer | `webview-package-api-transfer-build-2026-11-03-r1/transfer` | `de304aa553115994677d8c095921a63c502786c26083510fd6470831d223cdef` |

The signed fixture receipt hashes to
`46ec037dca28702e448d90a389e17294fa98d82637c44d6dfa68028a7534b335`.

| Check | Guard seconds | Sampled aggregate RSS bytes | Time maximum bytes |
| --- | ---: | ---: | ---: |
| Host runner compile | 1.958 | 341,934,080 | 369,885,184 |
| Runner selftest | 1.655 | 21,889,024 | 17,973,248 |
| Static ARM runner compile | 2.502 | 381,501,440 | 363,544,576 |
| Host transfer compile | 2.099 | 430,637,056 | 447,856,640 |
| Transfer selftest | 1.644 | 13,893,632 | 12,664,832 |

All guard/child exits are zero, reasons empty, cleanup complete and swaps zero.
Limits stay 600 MiB aggregate RSS, 300 seconds, 512 MiB shared growth, 1 GiB
reserve, 4 MiB output and shell file-size cap 16777216. The largest observed
growth was 44,806,144 bytes. Compilers were serialized. Both runner builds
retain the inherited local `arguments` shadowing and implicit-slice-clone
notices in their complete logs; no retry or diagnostic suppression occurred.

SDK manifest/build/JAR/DEX, native manifest/build/DSO, fixture receipt/APK and
tools were rehashed before and after qualification. Frozen sources equal the
checkout. Runner source base is `63e1e4374dbae1589ec89d979499ae79a01568ff`;
transfer source base is `510c631a3b39097e82e0b07c9d6b549f28e9919f`.
Their source hashes are respectively
`1b4a2840a77fb169ba36e8594343242c1bdd49a7ecde088b8101b792113df9b8` and
`01df24d2e68dc17573db74f19a51b9ba7e63077deef2bfab33194240cc11b552`.
Complete evidence remains in `S/webview-package-api-run-2026-11-03-r1`, matching
`run-build`, `S/webview-package-api-transfer-build-2026-11-03-r1` and matching
`transfer-controls` roots.

Those four roots passed sealing and separate fresh-process readback for 35
entries. Manifest at
`S/webview-package-api-tools-sealed-2026-11-03-r1/manifest.json` hashes to
`ede3d42e2927b21c9e032e7083cc5fd07c807f3d1534429ae7163b0e4ad199d2`.
Seal/readback took 78/235 ms, with both exits zero and complete cleanup under
the same RSS/reserve/output/file caps and 64 MiB growth. Controls remain in
`S/webview-package-api-tools-seal-controls-2026-11-03-r1`.

## Guest recipe

Verify that `webview-package-probe`, UID/GID 10153, the runtime mount and output
path are absent. Provision and confirm the exact account:

```sh
grep -nE '(^webview-package-probe:|:10153:)' /etc/passwd /etc/group
/usr/sbin/addgroup -g 10153 webview-package-probe
/usr/sbin/adduser -D -H -u 10153 -G webview-package-probe -s /bin/false webview-package-probe
grep -nE '^webview-package-probe:' /etc/passwd /etc/group
grep ' /opt/webview-package-runtime ' /proc/self/mounts
test ! -e /var/lib/webview-package-r1
mkdir /opt/webview-package-runtime
mount -o bind /opt/vinix-android-aarch64 /opt/webview-package-runtime
mount -o remount,bind,ro,nosuid,nodev,strictatime,wxallowed none /opt/webview-package-runtime
grep ' /opt/webview-package-runtime ' /proc/self/mounts
mkdir -p /opt/input
```

Require read-only `nosuid,nodev,wxallowed` attachment without `noexec`. Start the
qualified host transfer only when the guest is ready to fetch:

```sh
S=/Users/alex/.local/state/vinix/android
"$S/webview-package-api-transfer-build-2026-11-03-r1/transfer" serve --webview-package-api "$S/webview-package-api-transfer-live-2026-11-03-r1" 55546
```

Download and verify both pinned hashes before launch:

```sh
wget -O /opt/input/webview-package-run http://10.0.2.2:55546/webview-package-api-run
wget -O /opt/input/webview-package.apk http://10.0.2.2:55546/webview-package.apk
chmod 755 /opt/input/webview-package-run
chmod 644 /opt/input/webview-package.apk
sha256sum /opt/input/webview-package-run /opt/input/webview-package.apk
/opt/input/webview-package-run --webview-package /opt/webview-package-runtime /opt/input/webview-package.apk 10153 10153 /var/lib/webview-package-r1
```

Keep guest input idle through UART export END. Preserve the full UART and derive
one exact interval using [uart-snapshot.md](uart-snapshot.md). The unchanged
no-removal diagnostic import must retain every chunk and validate all six input
identities, eleven checks, full child log and clean exit; it does not extend
strict fixture-protocol qualification. Release with
`umount /opt/webview-package-runtime` after validation before separate GMS/Maps.
Preserve failures without weakening diagnostics.
