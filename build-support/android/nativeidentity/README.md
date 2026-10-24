# Explicit Unix application credentials

Native APKs normally keep their launching Unix credentials. An administrator
that already has real and effective UID 0 may opt into a permanent UID/GID
change using both `VINIX_ANDROID_UID` and `VINIX_ANDROID_GID`, each in
`10000..19999`. This changes actual Unix credentials before native-library
installation or ART startup; Android and native JNI identity queries agree.
The selected IDs must already resolve to a Unix account and group through
`getpwuid` and `getgrgid`, both before and after the change. ART uses that
account database during initialization. The launcher does not create accounts.

The administrator must provision an absolute `ANDROID_APP_DATA_DIR` and
`VINIX_ANDROID_HOME` as real directories owned by the selected UID/GID, with
read, write and traversal access. The APK and `VINIX_ANDROID_ROOT` must remain
readable under those credentials, including executable runtime entry points.
The runtime root must be absolute. The launcher never changes ownership or
permissions to make an input accessible. `HOME` and XDG home paths use the
explicit application home; inherited user names and `XDG_RUNTIME_DIR` are
removed, and the process changes directory to its application data.

ART requires the launcher's `VINIX_ALLOW_WX=1` execution policy. For a process
without Unix root privileges, Vinix also requires an administrator-approved
`wxallowed` mount for the private runtime's executable loader. Provision that
mount before dropping credentials, scoped to the runtime; this launcher does
not change mount policy. Without it the kernel rejects the loader exec with
`EPERM`, even when ordinary file permissions allow execution.

The inherited stdin pipe still carries native WS input. `VINIX_SURFACE_PATH`
must be absolute, in a directory writable by the target, and either absent or
a regular nonsymlink file owned by the target UID/GID with one hard link. The
administrator must provide a compositor that can read that surface. The root
desktop can do so; this option does not provide transport across arbitrary
unprivileged desktop users. Native notifications remain authenticated against
the session broker's Unix UID, so this option does not grant access to the
original root session's notification broker.

For example, an administrator-provided V wrapper can set these values and
exec the ordinary launcher, retaining the compositor's stdin and surface path:

```text
VINIX_ANDROID_UID=10000
VINIX_ANDROID_GID=10000
ANDROID_APP_DATA_DIR=/srv/android/maps/data
VINIX_ANDROID_HOME=/srv/android/maps/home
VINIX_ANDROID_ROOT=/opt/vinix-android-aarch64
```

The desktop constructs a restricted environment for native apps and does not
automatically forward these settings. This is an explicit administrator launch
facility, not a package UID allocator, privilege service for ordinary users, or
a claim of per-package isolation. Unprivileged callers cannot select another
identity. Incomplete or empty credential settings fail instead of silently
running as root.

The drop clears supplementary groups and capability sets, changes all real,
effective and saved IDs, sets and reads back `no_new_privs`, verifies the
result and rejects a process that can regain root. Errors terminate the launcher.

After validating the administrator's identity and owned data/home inputs, the
launcher sets `RLIMIT_NICE` to soft/hard `40/40` before dropping capabilities
and IDs. This admits normal thread nice values from `-20` to `19`, following
[Android 15 init.rc, line 41](https://android.googlesource.com/platform/system/core/+/android-15.0.0_r1/rootdir/init.rc#41).
The kernel still requires matching Unix ownership for another thread's
priority; no `CAP_SYS_NICE` remains. The launcher also sets `RLIMIT_RTPRIO`
to `0/0` so inherited real-time admission is removed, and reads back both
limits after the drop. Apps cannot raise the hard limits. Launches without
explicit identity options keep their inherited scheduling limits.

Run the host configuration tests with `v test build-support/android/nativeidentity`.
The Linux/Vinix fixture in `tests/native-android-ws/identity-fixture.v` exercises
actual credential changes in child processes, including a fresh exec and
negative filesystem/identity cases. It requires root and makes only private
temporary fixtures; UID/GID 10000 must already resolve on the test system.
Generated evidence belongs outside Git.

On the ARM64 macOS build host, boot the fixture in a private clone of an existing
Vinix boot image and firmware variables file:

```sh
v -cflags -O2 run tests/native-android-ws/identity-run.v \
  /absolute/path/boot.img /absolute/path/efivars.fd \
  /absolute/path/new-identity-results
```

Run from the repository root with `aarch64-linux-musl-gcc` and `mcopy` available.
The private guest overlay provides its own fixture account and group, leaving
the host account database untouched.
`VINIX_V_COMPILER`, `VINIX_IDENTITY_QEMU` and `VINIX_IDENTITY_FIRMWARE` override
the compiler, QEMU binary and read-only firmware. The runner preserves its
private image, fixture overlay, source/binary hashes and serial log. It writes
compiler, QEMU and firmware identities plus exact argument arrays to
`execution.json` before compiling the frozen fixture.
Both runner and guest fixture reject `-prod`; assertions must remain enabled.
A passing run records `ANDROID-IDENTITY-SUITE PASS cases=18` after three successful
drop-and-exec cases and fifteen rejected configurations. The successful cases
check all normal nice values, zero-limit refusal, denied hard-limit increases,
another UID's unchanged priority, zero real-time admission, and enforcement after
lowering the hard limit. One starts with inherited real-time admission to
verify the launcher clears it. The parent also verifies that disabled identity
activation preserves both scheduling limits. FIFO must fail with `EPERM` when
implemented; an older kernel's `ENOSYS` is recorded as `fifo=unsupported-ENOSYS`
and does not establish FIFO permission enforcement. This verifies the
credential module; a real APK launch still requires the approved runtime
mount and compositor transport described above.

For an older bundle that lacks execution metadata, `--capture-metadata BUNDLE`
adds `execution-supplement.json` without changing its original inputs or
results. This records current tool identities after the run; its argument
arrays must be compared with the preserved tested runner before treating them
as the historical invocation.
