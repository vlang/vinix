# Stable display fixture tools, 2026-11-02

The additive `--stable-display` runner profile requires its successor framework,
physical framebuffer query native library and signed fixture. The transfer
selector `serve --stable-display-api` serves exactly `/stable-display-api-run`
and `/stable-display.apk`. Historical profiles, pins and routes, including
PendingIntent, remain unchanged.

The exact success marker is:

```text
STABLE-DISPLAY-PASS physical-size window-size fresh-points mutation-isolation
```

The fixture requires independently verified physical geometry `1024×768` and
the generic runner's unchanged `64×64` application surface. It checks physical
dimensions, retained window-size APIs, fresh Point objects, mutation isolation
and cross-context queries. The generic runner retains six protected input pins,
eleven receipt checks, dedicated identity/data/home/surface, descriptor closure,
bounded lifetime, one exact PASS/READY pair, drained EOF and clean child exit.
This fixture does not establish Google Play Services or authentication behavior.

Paths below use `S=/Users/alex/.local/state/vinix/android`.

| Input | Path below S | SHA-256 |
| --- | --- | --- |
| Framework | `PENDING_FRAMEWORK_PATH` | `PENDING_FRAMEWORK_SHA` |
| Native | `PENDING_NATIVE_PATH` | `PENDING_NATIVE_SHA` |
| Signed fixture | `stable-display-fixture-2026-11-02-r1/probe.apk` | `e29dc54e644e94a5a0a4040858cdca452ee8ebc83e29052c78e4b91b55e9d13c` |

Fixture receipt `S/stable-display-fixture-2026-11-02-r1/build.json` has SHA-256
`df67d985a9fe27f6d352b083dfb47e5699a1e7590f9c85b4354e119f982c59a2`.

## Guest recipe

Start the qualified host transfer with fresh output:

```sh
S=/Users/alex/.local/state/vinix/android
"$S/stable-display-api-transfer-build-2026-11-02-r1/transfer" serve --stable-display-api "$S/stable-display-api-transfer-live-2026-11-02-r1" 55531
```

In the fresh guest root terminal, require no passwd/group match for name
`stable-display-probe` or UID/GID 10139 before provisioning. An existing exact
account may be retained only after checking its UID, primary GID and group GID.

```sh
grep -nE '(^stable-display-probe:|:10139:)' /etc/passwd /etc/group
/usr/sbin/addgroup -g 10139 stable-display-probe
/usr/sbin/adduser -D -H -u 10139 -G stable-display-probe -s /bin/false stable-display-probe
grep -nE '^stable-display-probe:' /etc/passwd /etc/group
```

Require no existing dedicated runtime mount. Bind the staged immutable runtime
to a fresh attachment and verify `ro,nosuid,nodev,wxallowed` without `noexec`.
Preserve independent desktop/framebuffer geometry evidence before launching.

```sh
grep ' /opt/stable-display-runtime ' /proc/self/mounts
mkdir /opt/stable-display-runtime
mount -o bind /opt/vinix-android-aarch64 /opt/stable-display-runtime
mount -o remount,bind,ro,nosuid,nodev,strictatime,wxallowed none /opt/stable-display-runtime
grep ' /opt/stable-display-runtime ' /proc/self/mounts
mkdir -p /opt/input
wget -O /opt/input/stable-display-run http://10.0.2.2:55531/stable-display-api-run
wget -O /opt/input/stable-display.apk http://10.0.2.2:55531/stable-display.apk
chmod 755 /opt/input/stable-display-run
chmod 644 /opt/input/stable-display.apk
/opt/input/stable-display-run --stable-display /opt/stable-display-runtime /opt/input/stable-display.apk 10139 10139 /var/lib/stable-display-r1
```

Before launch, verify fresh output `/var/lib/stable-display-r1` is absent and
downloaded runner/APK hashes match the qualified pins. Leave guest input untouched
through UART export. Preserve the complete UART and derive one exact interval
using [uart-snapshot.md](uart-snapshot.md). Strictly collect `child.log` and
`receipt.json`, requiring all eleven checks and the exact six identities. After
validation, run `umount /opt/stable-display-runtime` before the separate Maps/GMS
test. The fixture's 64×64 surface remains unchanged throughout.
