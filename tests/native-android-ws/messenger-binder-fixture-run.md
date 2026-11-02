# Messenger Binder fixture delivery, 2026-11-02

The additive runner selector `--messenger-binder` requires its successor
framework, retained broadcast native library and separate signed fixture.
Transfer selector `serve --messenger-binder-api` exposes exactly
`/messenger-binder-api-run` and `/messenger-binder.apk`. Historical selectors,
routes and identities remain unchanged.

The exact success marker is:

```text
MESSENGER-BINDER-PASS endpoint-identity local-proxy queued-reply token-oneway cloned-payload sending-uid parcel-copy-reset null-errors bounded-worker
```

The [fixture](messenger-binder-fixture-host.md) exercises actual process-local
Messenger Binder endpoints, Message parceling and queued request/reply delivery
on API 28. It checks cached endpoint identity/equality, local IBinder construction
and a forced proxy using unchanged framework Binder.transact. The forced wrapper
checks the IMessenger token, code, presence, oneway flag and null reply before
forwarding the live Parcel. Three real exchanges check payload fields, clone
behavior, reply Binder and sendingUid inside worker callbacks before signaling.
Main reads counters and failures after waiting, without inspecting recycled
queue-owned Messages.

Message controls cover API-28 wire order, Parcelable and nullable fields, copies,
constructor/newly obtained pool UID, malformed token/unknown transaction/null
errors and exact exception propagation. Fresh test Parcels have finally cleanup;
proxy recycling is source-audited without inspecting recycled objects. One shared
eight-second deadline begins before worker startup; cleanup quits the captured
Looper and joins for at most one second before PASS. The only six APK classes
are Main, ReadyHandlerThread, EndpointHandler, ReplyHandler, ForcedBinder and
ThrowingParcelable, all in `org.vinix.bootstrap`, with minSdk 28. There is no
platform stub, SDK override, kernel IPC, cross-process credentials, Google task
completion, GMS, Maps or authentication claim.

The runner retains six protected input identities, eleven receipt checks,
isolated identity/data/home/surface, explicit environment, closed inherited
descriptors, 180/20-second deadlines, 4 MiB log and 8,192-byte line limits, one
exact PASS/READY pair, drained EOF and clean child exit. Health diagnostics remain
unchanged. Host qualification is separate from ARM execution.

Paths below use `S=/Users/alex/.local/state/vinix/android`.

| Input | Path below S | SHA-256 |
| --- | --- | --- |
| Framework | `combined-account-webview-messenger-binder-framework-2026-11-02-r1/api-impl.jar` | `ddeeb613e7767cbfb3e2bf3818ff02f8f9ab10918f26868dba8047a2cc539129` |
| Native | `current-native-build-2026-11-02-broadcast-permission-r1/native/libvinix-android-native.so` | `29b2631c36a4a8c802e904e936c23e090fb2de3b5019ac93548df1b15de2a8f1` |
| Fixture | `messenger-binder-fixture-2026-11-02-r2/probe.apk` | `7295339e8b548f3d48091229eb31319be25bf7394a2091ebce6b26263693729a` |
| ARM runner | `messenger-binder-api-run-2026-11-02-r1/run` | `b8ed42d605b5f81d6900515cc3389a3fa6811ec813fd6bb3fd53078f0d62698c` |
| Transfer | `messenger-binder-api-transfer-build-2026-11-02-r1/transfer` | `9686d289c22bc399e7c340c846fd839d964670d80ecebea096a5806eb49693be` |

The signed r2 fixture build receipt hashes to
`cee3f0da1d4131154d88de8ccff5fdb330b998fd3522ec792a5f4eac1724d973`.
R1 fixture assembly failed on four missing long-literal L suffixes and produced
no signed APK. The failed fixture/control roots remain preserved. R2 corrected only
those test literals, without changing assertions or framework behavior; delivery
selects only its qualified signed APK.

All five delivery qualification phases passed on their first attempts. The
runner selftest rejected 3,943 malformed/mixed/failure cases. Transfer tests
retain binary snapshots, GET-only requests, traversal and absolute deadlines,
adding exact selector/port refusal and route/path/hash uniqueness checks against
all historical profiles. ELF inspection confirms static AArch64 EXEC without
INTERP or DYNAMIC segments.

| Check | Guard seconds | Sampled aggregate RSS bytes | Time maximum bytes |
| --- | ---: | ---: | ---: |
| Host runner compile | 1.402 | 365,494,272 | 374,718,464 |
| Runner selftest | 1.217 | 21,856,256 | 17,940,480 |
| Static ARM runner compile | 1.869 | 375,980,032 | 377,339,904 |
| Host transfer compile | 1.730 | 393,428,992 | 425,967,616 |
| Transfer selftest | 1.259 | 13,025,280 | 12,206,080 |

Every guard/child exit is zero, reason empty, cleanup complete and swaps zero
under the original 600 MiB RSS, 300-second, 512 MiB shared-growth, 1 GiB reserve,
4 MiB output and shell file-size cap 16777216 limits. Compilers were serialized.
SDK manifest/build/JAR/DEX, fixture receipt/APK, native manifest/build/DSO, tool
and predecessor pins were independently rehashed before and after checks.
Frozen sources equal the checkout. Both source bases are
`283faf15e2333d86c4598c3f94700cbecaed63c3`; runner/transfer source hashes are
respectively `ee6486354dad2ad38d734985efec9ef5061c2e98d95271490f53637efc3dd490`
and `5076444c8da581121b250b347a56f5adaab149cdd9891cca4bbbbc1ac0f10369`.

Four complete tool/control roots passed sealing and separate fresh-process
readback for 35 entries. The manifest at
`S/messenger-binder-api-tools-sealed-2026-11-02-r1/manifest.json` hashes to
`4aa66b5c897995db6554f2083a45d69eeddfefcadb275668e8e4e5ce7d10bb94`.
Seal/readback guards took 50/94 ms, both guard/child exits zero and cleanup
complete under the same RSS/reserve/output/file caps and 64 MiB growth. Controls
remain in `S/messenger-binder-api-tools-seal-controls-2026-11-02-r1`.

## Guest recipe

Verify that `messenger-binder-probe`, UID/GID 10150, the dedicated runtime mount
and output path are absent. Provision and confirm the exact account:

```sh
grep -nE '(^messenger-binder-probe:|:10150:)' /etc/passwd /etc/group
/usr/sbin/addgroup -g 10150 messenger-binder-probe
/usr/sbin/adduser -D -H -u 10150 -G messenger-binder-probe -s /bin/false messenger-binder-probe
grep -nE '^messenger-binder-probe:' /etc/passwd /etc/group
grep ' /opt/messenger-binder-runtime ' /proc/self/mounts
test ! -e /var/lib/messenger-binder-r1
mkdir /opt/messenger-binder-runtime
mount -o bind /opt/vinix-android-aarch64 /opt/messenger-binder-runtime
mount -o remount,bind,ro,nosuid,nodev,strictatime,wxallowed none /opt/messenger-binder-runtime
grep ' /opt/messenger-binder-runtime ' /proc/self/mounts
mkdir -p /opt/input
```

Require read-only `nosuid,nodev,wxallowed` attachment without `noexec`. Start the
qualified host transfer with a fresh output only when the guest is ready to fetch:

```sh
S=/Users/alex/.local/state/vinix/android
"$S/messenger-binder-api-transfer-build-2026-11-02-r1/transfer" serve --messenger-binder-api "$S/messenger-binder-api-transfer-live-2026-11-02-r1" 55542
```

Download and verify both hashes before launch:

```sh
wget -O /opt/input/messenger-binder-run http://10.0.2.2:55542/messenger-binder-api-run
wget -O /opt/input/messenger-binder.apk http://10.0.2.2:55542/messenger-binder.apk
chmod 755 /opt/input/messenger-binder-run
chmod 644 /opt/input/messenger-binder.apk
sha256sum /opt/input/messenger-binder-run /opt/input/messenger-binder.apk
/opt/input/messenger-binder-run --messenger-binder /opt/messenger-binder-runtime /opt/input/messenger-binder.apk 10150 10150 /var/lib/messenger-binder-r1
```

Keep guest input idle through UART export END. Preserve the full UART and derive
one exact interval using [uart-snapshot.md](uart-snapshot.md). The unchanged
no-removal diagnostic import must retain all chunks and validate the exact six
identities, eleven checks, complete child log and clean exit; it does not extend
strict fixture-protocol qualification. Release with
`umount /opt/messenger-binder-runtime` after validation before separate GMS/Maps.
Preserve failures without weakening diagnostics.
