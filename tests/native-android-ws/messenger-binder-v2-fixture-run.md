# Messenger Binder v2 fixture delivery, 2026-11-02

The additive runner selector `--messenger-binder-v2` selects the ComponentName
parcel successor framework with the retained native library and the exact same
signed six-class Messenger fixture. Transfer selector
`serve --messenger-binder-v2-api` exposes `/messenger-binder-v2-api-run` and
`/messenger-binder-v2.apk`. All v1 selectors, pins, routes and failed ARM evidence
remain unchanged.

The signed r2 fixture APK remains
`S/messenger-binder-fixture-2026-11-02-r2/probe.apk`, SHA-256
`7295339e8b548f3d48091229eb31319be25bf7394a2091ebce6b26263693729a`.
Its success marker is deliberately unchanged:

```text
MESSENGER-BINDER-PASS endpoint-identity local-proxy queued-reply token-oneway cloned-payload sending-uid parcel-copy-reset null-errors bounded-worker
```

The v1 ARM attempt stopped before the Messenger protocol assertions because
ComponentName inherited a no-op Parcelable writer and lacked CREATOR. V2 changes
the framework used by the unchanged [fixture](messenger-binder-fixture-host.md),
which exercises in-process endpoint identity, queued local/proxy request/reply,
payload clones, sending UID, API-28 Message parcel/copy/reset controls, null/error
handling and bounded worker cleanup. Neither a shared marker nor this delivery
profile establishes that v1 passed. No fixture assertion or signed APK changes.

The v2 transfer tests permit exactly one shared source path/hash pair: the
`/messenger-binder-v2.apk` route deliberately aliases the signed APK behind
`/messenger-binder.apk`. Both routes remain distinct. The new runner and every
other asset pair must retain distinct paths and hashes; all historical tests
remain unchanged. Runtime profile identity still requires the exact successor
JAR and retained native pair before execution.

Six protected inputs, eleven receipt checks, isolated identity/data/home/surface,
explicit environment, closed inherited descriptors, 180/20-second deadlines,
4 MiB log and 8,192-byte line limits, exact PASS/READY pair, drained EOF and clean
child exit remain required. Health diagnostics are unchanged. There is no kernel
IPC, cross-process credentials, Google task completion, GMS, Maps or
authentication claim. Host qualification and ARM execution remain separate.

Paths use `S=/Users/alex/.local/state/vinix/android`.

| Input | Path below S | SHA-256 |
| --- | --- | --- |
| Framework | `combined-account-webview-component-parcel-framework-2026-11-02-r1/api-impl.jar` | `329a45c23bd981b67733f36cde2828b2d890597a384acf1e0ce30f8f8fb582f4` |
| Native | `current-native-build-2026-11-02-broadcast-permission-r1/native/libvinix-android-native.so` | `29b2631c36a4a8c802e904e936c23e090fb2de3b5019ac93548df1b15de2a8f1` |
| Unchanged fixture | `messenger-binder-fixture-2026-11-02-r2/probe.apk` | `7295339e8b548f3d48091229eb31319be25bf7394a2091ebce6b26263693729a` |
| ARM runner | `messenger-binder-v2-api-run-2026-11-02-r1/run` | `077e2a7ad387594f3dcb6caa7eac3762c9e884370283436479e6f56758a5ab88` |
| Transfer | `messenger-binder-v2-api-transfer-build-2026-11-02-r1/transfer` | `d1bd8f60bca335a2e1267dfb364db9eae526f7918553e16f1aa530e0578373de` |

The unchanged signed fixture build receipt hashes to
`cee3f0da1d4131154d88de8ccff5fdb330b998fd3522ec792a5f4eac1724d973`.
All five delivery qualification phases passed on their first attempts. The
runner selftest rejected 4,121 malformed/mixed/failure cases. Transfer tests
retain binary snapshots, GET-only requests, traversal, absolute deadlines and
all historical checks, adding exact V2 selector/port refusals and the narrowly
scoped shared-APK identity checks above. ELF inspection confirms static AArch64
EXEC without INTERP or DYNAMIC segments.

| Check | Guard seconds | Sampled aggregate RSS bytes | Time maximum bytes |
| --- | ---: | ---: | ---: |
| Host runner compile | 1.421 | 357,335,040 | 374,112,256 |
| Runner selftest | 1.399 | 21,037,056 | 17,940,480 |
| Static ARM runner compile | 1.881 | 377,618,432 | 370,376,704 |
| Host transfer compile | 1.753 | 396,197,888 | 429,342,720 |
| Transfer selftest | 1.336 | 14,057,472 | 12,828,672 |

Every guard/child exit is zero, reason empty, cleanup complete and swaps zero
under the original 600 MiB RSS, 300-second, 512 MiB shared-growth, 1 GiB reserve,
4 MiB output and shell file-size cap 16777216 limits. Compilers were serialized.
SDK manifest/build/JAR/DEX, reused fixture receipt/APK, native manifest/build/DSO,
tool and predecessor pins were independently rehashed before and after checks.
Frozen sources equal the checkout. Both source bases are
`38a56c93ad5d97e2261c792736ea7864b2d05567`; runner/transfer source hashes are
respectively `8422b0890c6069a90e08bd8a7709b8dce8f6a37f57e723dd546ae0f2d8c3932d`
and `7690d084c163fce4c895c6d05a58cd7cf943e2864f44a57db3d2984d63bc5ff7`.

Four complete tool/control roots passed sealing and separate fresh-process
readback for 35 entries. The manifest at
`S/messenger-binder-v2-api-tools-sealed-2026-11-02-r1/manifest.json` hashes to
`fd458957bfcabb12bc779dc5e0d0a3f8747e0118ef0459ccb148f37973acb922`.
Seal/readback guards took 47/637 ms, both guard/child exits zero and cleanup
complete under the same RSS/reserve/output/file caps and 64 MiB growth. Controls
remain in `S/messenger-binder-v2-api-tools-seal-controls-2026-11-02-r1`.

## Guest recipe

The unchanged signed fixture requires UID/GID 10150. Reuse that numeric identity
only in the fresh v2 VM cloned from the closed prepared parent, before the v1
account was provisioned. Verify that UID/GID 10150 and `messenger-binder-v2-probe`
are absent; do not reuse the failed v1 live VM or its data. V2 has separate runtime,
inputs and output paths.

```sh
grep -nE '(^messenger-binder-v2-probe:|:10150:)' /etc/passwd /etc/group
/usr/sbin/addgroup -g 10150 messenger-binder-v2-probe
/usr/sbin/adduser -D -H -u 10150 -G messenger-binder-v2-probe -s /bin/false messenger-binder-v2-probe
grep -nE '^messenger-binder-v2-probe:' /etc/passwd /etc/group
grep ' /opt/messenger-binder-v2-runtime ' /proc/self/mounts
test ! -e /var/lib/messenger-binder-v2-r1
mkdir /opt/messenger-binder-v2-runtime
mount -o bind /opt/vinix-android-aarch64 /opt/messenger-binder-v2-runtime
mount -o remount,bind,ro,nosuid,nodev,strictatime,wxallowed none /opt/messenger-binder-v2-runtime
grep ' /opt/messenger-binder-v2-runtime ' /proc/self/mounts
mkdir -p /opt/input
```

Require read-only `nosuid,nodev,wxallowed` attachment without `noexec`. Start the
qualified host transfer only when the guest is ready to fetch:

```sh
S=/Users/alex/.local/state/vinix/android
"$S/messenger-binder-v2-api-transfer-build-2026-11-02-r1/transfer" serve --messenger-binder-v2-api "$S/messenger-binder-v2-api-transfer-live-2026-11-02-r1" 55543
```

Download and verify both hashes before launch:

```sh
wget -O /opt/input/messenger-binder-v2-run http://10.0.2.2:55543/messenger-binder-v2-api-run
wget -O /opt/input/messenger-binder-v2.apk http://10.0.2.2:55543/messenger-binder-v2.apk
chmod 755 /opt/input/messenger-binder-v2-run
chmod 644 /opt/input/messenger-binder-v2.apk
sha256sum /opt/input/messenger-binder-v2-run /opt/input/messenger-binder-v2.apk
/opt/input/messenger-binder-v2-run --messenger-binder-v2 /opt/messenger-binder-v2-runtime /opt/input/messenger-binder-v2.apk 10150 10150 /var/lib/messenger-binder-v2-r1
```

Keep guest input idle through UART export END. Preserve the full UART and derive
one exact interval using [uart-snapshot.md](uart-snapshot.md). The unchanged
no-removal diagnostic import must retain every chunk and validate all six input
identities, eleven checks, full child log and clean exit; it does not extend
strict fixture-protocol qualification. Release with
`umount /opt/messenger-binder-v2-runtime` after validation before separate GMS/Maps.
Preserve failures without weakening diagnostics.
