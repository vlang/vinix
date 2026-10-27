# Standalone onboarding API regressions

`onboarding-api-run.v` executes either the child-attachment regression or the
`Settings.Global.putInt` contract regression. Both are signed standalone APKs
with activity `org/vinix/bootstrap/Main`. The mandatory `--child-attach` or
`--settings-global` selector pins one APK, its complete terminal pass line, and
the corrected framework JAR. These fixtures do not exercise Google login or
claim SettingsProvider persistence.

The controller follows the existing service-query runner: a fresh data/home
and private 64×64 surface under a pre-provisioned UID/GID in 10000..19999,
explicit credential-free environment, and pipe-backed standard descriptors.
Descriptors above stdio are closed before exec. It permits 180 seconds for
exactly one pass and one native WS readiness marker, closes stdin, drains the
log to EOF, and requires clean exit within 20 seconds. Output is limited to
4 MiB and lines to 8192 bytes; exception and conflicting marker lines fail.
The signed APK, framework and launch inputs are rehashed after execution.

Only `child.log` and `receipt.json` are exported, using the existing
`VINIX-SERVICE-QUERY-RESULTS-1` framing accepted by the diagnostic reconstructor.
The receipt kind is `vinix-onboarding-api-runtime-v1` and its profile selects the
fixture. Application data remains in the guest. Keep the two runs' serial
captures separate.
Use [uart-snapshot.md](uart-snapshot.md) to preserve the complete growing UART
and derive one exact appended interval per fixture without rotating its sink.

`service-query-transfer.v serve --onboarding-apis FRESH_EXTERNAL_DIR PORT`
snapshots and serves exactly `/onboarding-api-run`, `/child-attach.apk`, and
`/settings-global.apk`. It preserves the existing loopback-only binding,
SHA-256 checks, GET-only request parsing, 12-request/600-second limits and
32 MiB file bound. Historical transfer profiles keep their existing pins.

The ready host transfer is
`/Users/alex/.local/state/vinix/android/onboarding-api-transfer-build-2026-10-27-r1/transfer`,
SHA-256 `9046e9b41c91a95c231ef4577725090491f081ec468e7218d9f2d00c70282b38`.
Start it with a fresh result directory:

```sh
/Users/alex/.local/state/vinix/android/onboarding-api-transfer-build-2026-10-27-r1/transfer serve --onboarding-apis /Users/alex/.local/state/vinix/android/onboarding-api-transfer-live-2026-10-27-r1 18765
```

As root in a fresh guest, provision the dedicated fixture identity before
running either APK. UID/GID 10117 is an example selected for this run; staging
does not create it. First check that neither the name nor numeric ID is used:

```sh
grep -nE '(^onboarding-probe:|:10117:)' /etc/passwd /etc/group
```

Proceed only when that check reports no matches. The guest's account tools
create both records without a home or login shell:

```sh
/usr/sbin/addgroup -g 10117 onboarding-probe
/usr/sbin/adduser -D -H -u 10117 -G onboarding-probe -s /bin/false onboarding-probe
grep -nE '^onboarding-probe:' /etc/passwd /etc/group
```

Verify that the passwd UID and primary GID, and the group GID, are all 10117.
Do not repeat provisioning if the exact account already exists. Reserve
10012/10013 for Maps/GMS and 10014 for the token fixture. Both standalone tests
can reuse the dedicated fixture identity sequentially with fresh output paths.

Before starting a fixture, apply the existing executable attachment policy to
the selected immutable runtime only. A fresh guest may not have this dedicated
mount until the Maps controller or these root setup commands create it:

```sh
mount -o bind /opt/vinix-android-aarch64 /opt/vinix-android-aarch64
mount -o remount,bind,ro,nosuid,nodev,strictatime,wxallowed none /opt/vinix-android-aarch64
grep ' /opt/vinix-android-aarch64 ' /proc/self/mounts
```

Require a dedicated runtime entry with `ro,nosuid,nodev,wxallowed` and without
`noexec` before launching. The tested guest reports `relatime` after the remount;
the required protection and execution flags are still present. This uses the
existing kernel policy on that runtime attachment, with no global exception.
If the dedicated attachment is already present and has those flags, retain it.

Download from the QEMU guest through usernet:

```sh
mkdir /var/lib/onboarding-api-input-r1
wget -O /var/lib/onboarding-api-input-r1/run http://10.0.2.2:18765/onboarding-api-run
wget -O /var/lib/onboarding-api-input-r1/child-attach.apk http://10.0.2.2:18765/child-attach.apk
wget -O /var/lib/onboarding-api-input-r1/settings-global.apk http://10.0.2.2:18765/settings-global.apk
chmod 755 /var/lib/onboarding-api-input-r1/run
chmod 644 /var/lib/onboarding-api-input-r1/child-attach.apk /var/lib/onboarding-api-input-r1/settings-global.apk
/var/lib/onboarding-api-input-r1/run --child-attach /opt/vinix-android-aarch64 /var/lib/onboarding-api-input-r1/child-attach.apk 10117 10117 /var/lib/onboarding-api-child-result-r1
# Preserve the child UART interval on the host before starting the next fixture.
/var/lib/onboarding-api-input-r1/run --settings-global /opt/vinix-android-aarch64 /var/lib/onboarding-api-input-r1/settings-global.apk 10117 10117 /var/lib/onboarding-api-settings-result-r1
```

The input directory and all ancestors must be root-owned, traversable and not
group/other writable; the Unix user/group must already exist. Use fresh output
directories. The runtime must retain the existing executable-mount policy.

The host runner selftest passed, rejecting 42 malformed, duplicate, mixed-profile,
error and incomplete-log cases. Transfer selftests passed binary multi-buffer
delivery, pin mismatch, symlink/empty/existing-output refusal, GET-only and
traversal checks, request exhaustion and absolute accept deadlines. Independent
source review found no blocker. The controller retains the service-query
failure cleanup behavior: best-effort process-group/direct-child kills followed
by `waitpid`, without a separate cleanup deadline.

Host runner, static AArch64 runner and transfer builds passed sequentially with
V compiler `0cc6c1d34c1811a818e4ae89853116861a4b067d4251af257851a7714f0d11fe`
and its adjacent library. Each command used the bounded supervisor with 1 GiB
aggregate RSS, 300 seconds, 1 GiB disk reserve and an explicitly backed 8 GiB
shared-volume growth budget. The largest sampled process-tree RSS was
359,104,512 bytes; all `/usr/bin/time -l` measurements recorded zero swaps.
Host binaries use normal GC; the static one-shot ARM runner uses `-gc none`.

The static ARM runner is
`/Users/alex/.local/state/vinix/android/onboarding-api-run-2026-10-27-r1/run`,
SHA-256 `0c8926b74244b7f505ffa6aafb6ff8a6e7beef2bd96369310a30d35d063b10b8`.
Its exact framework JAR pin is
`e7d7d590da1ae5f9eb8f9f27aae0c003a30f10f5d79effc0c63f463f958263fd`.
The APKs are those in [child-attach.md](child-attach.md) and
[settings-global.md](settings-global.md), pinned directly in the source.

Host sources, binaries, guarded command receipts and logs are preserved in
`/Users/alex/.local/state/vinix/android/onboarding-api-host-evidence-2026-10-27-r1`,
with the source revision and a sibling `.sha256` inventory/readback log. The
fixture/framework bundles retain their separate complete evidence. These host
checks and static compilation do not establish ART execution; both fixture
runs and Maps/Google login validation remain pending in the fresh guest.
