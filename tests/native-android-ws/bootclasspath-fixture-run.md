# Platform boot-classpath fixture delivery

The additive runner selector `--bootclasspath` selects the resource-loader SDK
companion, fresh boot-aware native library and signed two-class regression.
Transfer selector `serve --bootclasspath-api` exposes exactly
`/bootclasspath-api-run` and `/bootclasspath.apk`. Every historical selector,
route and pin stays unchanged, including the exact Messenger v1/v2 shared APK
exception.

The [two-class fixture](bootclasspath-fixture-host.md) checks shared platform
class identity through the real boot, system, application, isolated PathClassLoader
and isolated DexClassLoader. Each isolated loader defines its own Probe and
reflectively calls it with the real Activity Context. The Context return type and
object must retain identity. Bounded resource enumerations require each loader's
exact manifest set and order. Real system and Activity resources must resolve
android.R.string.ok with cookie one; an application string requires cookie two.
The bounded plain worker repeats platform identities, and UI smoke uses real
View/WebView/settings/static-data operations with cleanup and a native SHA-256
known-answer check. This does not establish visual rendering, browser-engine
availability, complete Google module loading, Maps, accounts or authentication.

The exact success marker is:

```text
BOOTCLASSPATH-PASS shared-platform boot-parent isolated-path-dex reflected-context framework-manifest-once cookie-one native-webview digest bounded-worker
```

Six protected inputs, eleven receipt checks, isolated identity/data/home/surface,
explicit environment, closed inherited descriptors, 180/20-second deadlines,
4 MiB log and 8,192-byte line limits, exact PASS/READY pair, drained EOF and clean
child exit remain required. Health diagnostics remain unchanged apart from
recognition and rejection of conflicting BOOTCLASSPATH-PASS markers.

Host qualification passed all five phases on the first attempt. The runner
selftest rejected 4,889 malformed, mixed-profile and failure cases. Transfer
tests preserve binary snapshots, GET-only requests, traversal and absolute
deadlines, adding exact selector/port refusals and path/hash/URL uniqueness
checks against every predecessor. ELF readback confirms static AArch64 EXEC
without INTERP or DYNAMIC segments. ARM execution remains pending.

Paths below use `S=/Users/alex/.local/state/vinix/android`.

| Input | Path below S | SHA-256 |
| --- | --- | --- |
| Framework | `combined-account-webview-framework-boot-framework-2026-11-03-r1/api-impl.jar` | `d9633112327093e55d924ad658088f8dd3d0b712d5184bddcf7307bfc51bf974` |
| Fresh native | `current-native-build-2026-11-03-framework-boot-r1/native/libvinix-android-native.so` | `f3dafa843033f7fb5245cde6007e66eb603ae0fb747fdc1824a33f731ca7088d` |
| Fixture | `bootclasspath-fixture-2026-11-03-r1/probe.apk` | `bd7384342cb18c6d9d519186f921bba9c6acfe5c0f07b75f3db16dfc650a22e4` |
| ARM runner | `bootclasspath-api-run-2026-11-03-r1/run` | `047ec4bd70628a7b7e2c81621f306a2065537cbcb8d711d25403c99a19e8a3fb` |
| Transfer | `bootclasspath-api-transfer-build-2026-11-03-r1/transfer` | `fc2673c3b4d8991744186414800e04bb4cd0323eacd469b64b6ceb2deab3ab94` |

The signed fixture receipt hashes to
`76f42d915da202f10c68c20c2bf0c16e32fb1628bda2f60a9a99f083eef72dea`.

| Check | Guard seconds | Sampled aggregate RSS bytes | Time maximum bytes |
| --- | ---: | ---: | ---: |
| Host runner compile | 2.181 | 341,917,696 | 369,688,576 |
| Runner selftest | 1.394 | 22,708,224 | 18,006,016 |
| Static ARM runner compile | 1.960 | 376,913,920 | 372,965,376 |
| Host transfer compile | 1.989 | 409,976,832 | 453,623,808 |
| Transfer selftest | 1.457 | 14,172,160 | 12,894,208 |

All guard/child exits are zero, reasons empty, cleanup complete and swaps zero.
Limits remain 600 MiB aggregate RSS, 300 seconds, 512 MiB shared growth, 1 GiB
reserve, 4 MiB output and shell file-size cap 16777216. Maximum observed growth
was 12,853,248 bytes. Compilers were serialized. Both runner builds retain the
inherited local `arguments` shadowing and implicit-slice-clone notices in their
complete logs. No retry or diagnostic suppression occurred.

SDK manifest/build/JAR/DEX, native manifest/build/DSO, fixture receipt/APK and
tools were rehashed before and after qualification. Frozen sources equal the
checkout. Both source bases are `a16baf6c3a361f3c27cc3368b8be2f795dedc222`.
Runner and transfer source hashes are respectively
`07a3dbd21ccc125008135cb150045975b937a21e9a6f1db33ee44d1bfad32c79` and
`92c53ed99adc8bab065609515ce3dbc406b8295bdd2b972bb53600039fa562d4`.
Complete evidence remains in `S/bootclasspath-api-run-2026-11-03-r1`, matching
`run-build`, `S/bootclasspath-api-transfer-build-2026-11-03-r1` and matching
`transfer-controls` roots.

Those four roots passed sealing and separate fresh-process readback for 35
entries. Manifest at
`S/bootclasspath-api-tools-sealed-2026-11-03-r1/manifest.json` hashes to
`de7342dd6b921e89e96d3a3ab15d3dbf911612ebb7b232fe1db4c78d4a82271d`.
Seal/readback took 106/216 ms, with both exits zero and complete cleanup under
the same RSS/reserve/output/file caps and 64 MiB growth. Controls remain in
`S/bootclasspath-api-tools-seal-controls-2026-11-03-r1`.

## Guest recipe

Verify that `bootclasspath-probe`, UID/GID 10154, the runtime mount and output
path are unused. Provision and confirm the exact account:

```sh
grep -nE '(^bootclasspath-probe:|:10154:)' /etc/passwd /etc/group
/usr/sbin/addgroup -g 10154 bootclasspath-probe
/usr/sbin/adduser -D -H -u 10154 -G bootclasspath-probe -s /bin/false bootclasspath-probe
grep -nE '^bootclasspath-probe:' /etc/passwd /etc/group
grep ' /opt/bootclasspath-runtime ' /proc/self/mounts
test ! -e /var/lib/bootclasspath-r1
mkdir /opt/bootclasspath-runtime
mount -o bind /opt/vinix-android-aarch64 /opt/bootclasspath-runtime
mount -o remount,bind,ro,nosuid,nodev,strictatime,wxallowed none /opt/bootclasspath-runtime
grep ' /opt/bootclasspath-runtime ' /proc/self/mounts
mkdir -p /opt/input
```

Require read-only `nosuid,nodev,wxallowed` attachment without `noexec`. Start the
qualified host transfer only when the guest is ready to fetch:

```sh
S=/Users/alex/.local/state/vinix/android
"$S/bootclasspath-api-transfer-build-2026-11-03-r1/transfer" serve --bootclasspath-api "$S/bootclasspath-api-transfer-live-2026-11-03-r1" 55547
```

Download and verify both pinned hashes before launch:

```sh
wget -O /opt/input/bootclasspath-run http://10.0.2.2:55547/bootclasspath-api-run
wget -O /opt/input/bootclasspath.apk http://10.0.2.2:55547/bootclasspath.apk
chmod 755 /opt/input/bootclasspath-run
chmod 644 /opt/input/bootclasspath.apk
sha256sum /opt/input/bootclasspath-run /opt/input/bootclasspath.apk
/opt/input/bootclasspath-run --bootclasspath /opt/bootclasspath-runtime /opt/input/bootclasspath.apk 10154 10154 /var/lib/bootclasspath-r1
```

Keep guest input idle through UART export END. Preserve the full UART and derive
one exact interval with [uart-snapshot.md](uart-snapshot.md). The unchanged
no-removal diagnostic import must retain every chunk and validate all six input
identities, eleven checks, full child log and clean exit; it does not extend
strict fixture-protocol qualification. Release with
`umount /opt/bootclasspath-runtime` after validation before separate GMS/Maps.
Preserve failures without weakening diagnostics.
