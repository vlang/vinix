# Fixed overflow identity policy

The kernel exposes `/proc/sys/kernel/overflowuid` and `overflowgid` as regular
files initially mode `0444`, each containing `65534\n`. They describe a fixed
fallback identity policy; writes and truncation are unsupported even through a
descriptor opened by root. This does not implement mutable Linux sysctls, user
namespaces, UID/GID maps or network namespaces.

Bubblewrap 0.13.0 reads these paths before namespace setup. Their absence was the
first definite failure found in the WebKitGTK 2.48.1 sandbox path; user and network
namespace isolation remains required afterward. See the
[sandbox audit](../android-webview-browser-probe/sandbox-audit-2026-10-26.md).

Prepare the native V fixture separately from booting it. Both state directories
must be fresh absolute paths. The runner pins the fixture, helper source hashes,
native executable and kernel; it rejects a changed prepared executable or fixture.

```sh
./build-support/run-v-tool.sh tests/procfs-overflow/run.v --arch aarch64 \
  --state-dir /absolute/state/prepare --prepare-only
./build-support/run-v-tool.sh tests/procfs-overflow/run.v --arch aarch64 \
  --state-dir /absolute/state/run --prepared-dir /absolute/state/prepare \
  --kernel-dir /absolute/frozen/kernel
```

Repeat with `--arch x86_64` for the other architecture. Preparation uses
`aarch64-linux-musl-gcc` or `x86_64-linux-musl-gcc`; override the executable with
`CC_AARCH64` or `CC_AMD64`. Firmware follows the shared `guesthost` harness
conventions. Generated C, binaries, ISO,
serial logs and receipts remain in the supplied external state directories.

For an uncommitted kernel candidate, the existing isolated kernel builder accepts
an optional final patch argument. It copies and hashes the patch, applies it in a
fresh detached worktree, permits changes only to tracked kernel files, retains the
actual applied diff, and verifies the patch and source inputs after building:

```sh
./build-support/run-v-tool.sh tests/unix-recvmsg-flags/kernel-build.v \
  /absolute/repo /absolute/compiler/v /absolute/state/kernel-arm \
  BASE_COMMIT aarch64 /absolute/state/source.patch
```

Use a separate fresh output directory for `x86_64`. Kernel dependency directories
are linked from the repository, while complete retained copies and before/after
inventories detect changes. Build outputs and compiler inputs are retained by the
builder. The optional patch path leaves the existing no-patch behavior unchanged.

The guest checks exact values, mode and size, byte reads, partial pread and EOF,
shared offsets and seek origins, failed writes/pwrite/ftruncate/O_TRUNC, 200 repeated
open/read/close cycles per file and identity, and retained writable descriptors
after dropping to UID/GID10000. It also verifies that rejected user/network
namespace operations preserve namespace identities. This is a kernel regression
fixture, not evidence of a working browser sandbox or Google account login.
