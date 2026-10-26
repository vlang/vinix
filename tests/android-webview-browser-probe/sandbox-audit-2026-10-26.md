# Production WebKit sandbox audit — 2026-10-26

The frozen guest cannot run WebKitGTK 2.48.1's production bubblewrap sandbox.
The earliest definite incompatibility found inside bubblewrap is its mandatory
read of `/proc/sys/kernel/overflowuid`: the frozen procfs does not provide it
or `overflowgid`. This is a static source audit, not an observed guest failure
or a completed syscall qualification. No guest was started, no credentials
were entered, and Google login remains unverified.

The complete frozen kernel build is retained at
`/Users/alex/.local/state/vinix/android/unix-recvmsg-kernel-aarch64-2026-10-26-r3`.
Its source revision is `ee0d3b6ff3d2586a0e5f35a27042643afaa298f3`.
Keep that entire original bundle; the following pins identify its receipts
and input inventory and do not replace them:

| File | SHA-256 |
| --- | --- |
| `build.json` | `29360df6915a356b021db5d868ec02e2ba51dfe32ab2b63e16368e1adf2bd4d0` |
| `sha256.json` | `576a4c277b00e39734e0038b6952bdc3c5c279581b2d73721f830e6cafacd2ea` |
| `input-pins.json` | `08427b6565d208460b723bfcdcbfdbdb9ef56f044ba8b75b5b295f69eac8a10d` |
| `source/kernel/bin/vinix` | `ac90558eac4f2ea6b74c72c3f519370e98e9f88b0a5384aa82cc386bdd1876ce` |

Primary sources are the official
[WebKit `webkitgtk-2.48.1` launcher](https://github.com/WebKit/WebKit/blob/webkitgtk-2.48.1/Source/WebKit/UIProcess/Launcher/glib/BubblewrapLauncher.cpp)
and [bubblewrap `v0.13.0`](https://github.com/containers/bubblewrap/blob/v0.13.0/bubblewrap.c).
The staged production `usr/bin/bwrap` reports version 0.13.0. Its SHA-256 is
`4e0d83cbb4946d0c3a444091386c90c8f1c72615058ae8996e4122fa50388b38`,
under `maps-account-browser-deployment-2026-10-26-r1/package-runtime` in the
same external state directory. The audit compares upstream versioned source
with the kernel; it does not establish binary/source equivalence for every
distribution patch.

The downloaded primary files, URL/tag/hash metadata and V downloader copy are
retained at
`/Users/alex/.local/state/vinix/android/webkit-bwrap-audit-2026-10-26-r2`.
Its complete five-file inventory is `sha256.json`, SHA-256
`dd10b176dfab081df7bc4aa038bd671178c3f72337f253e2adc26be4cf990473`.
`BubblewrapLauncher.cpp` hashes to
`7a20312e8aafb7883c83f4d3913e34a1fb91cd58c7e6320cec45864954d4d1f8`;
`bubblewrap.c` hashes to
`534295b804fa3f5ddeb3ae275ce5a2113d468c72ec0a74fdad6003e0a67ee4ef`.

The blockers occur in this order in the audited source paths:

1. `bubblewrap.c:2935` calls `read_overflowids()` before argument parsing and
   namespace creation. At line 2803 it opens `overflowuid` and exits on failure.
   The frozen kernel's `fs/procfs.v:330` constructs `/proc/sys/kernel` without
   either overflow ID file; neither name occurs anywhere in its source.
   Earlier `PR_SET_NO_NEW_PRIVS` and capability queries have kernel handlers.
   WebKit's pre-spawn sealed memfd path also has implementations in
   `fs/vfs.v:2964` and `fs/tmpfs.v:134`; this is not full behavioral validation.
2. After those files exist with correct semantics, nonroot bubblewrap
   implicitly requests `CLONE_NEWUSER` (`bubblewrap.c:2973`). The production
   engine requires an application UID in 10000–19999
   (`build-support/android/webviewengine/main.v:28`, file revision
   `88a28c24edd5253bbb1aee43a32cd56c18fc3e1a`). The browser launcher constructs
   `DISPLAY=:N` and `GDK_BACKEND=x11`
   (`build-support/android/browserlaunch/session.c.v:209`, file revision
   `fb40158df5dc59659a5f31863be638c309c9c6bb`). WebKit therefore also requests
   `--unshare-net` for the WebProcess (`BubblewrapLauncher.cpp:671–694,831`).
   Frozen `userland/clone_arm64.v:132` rejects both flags with `EINVAL`, using
   `proc/container.v:35`, before changing process state.
3. Accepting those flags would not implement the sandbox. Frozen
   `fs/procfs.v:961–996` documents missing user mapping and rejects writes to
   `uid_map`, `gid_map` and `setgroups` with `EPERM`. Network namespace identity
   does not isolate networking (`proc/container.v:7–13`). Bubblewrap requires
   usable mappings and isolated loopback state (`bubblewrap.c:3249,3268`).

There is no supported production escape path in these inputs. Setuid
bubblewrap is explicitly rejected (`bubblewrap.c:799`). Running the engine as
root violates its UID contract and still leaves the local-X11 network
namespace requirement. WebKit's remote-X11 exception does not match the
private local display. Production rejects the sandbox-disable environment
variable (`webviewengine/main.v:50`). Preserve the kernel's unsupported-flag
guards until actual namespace isolation, mapping permissions and teardown
semantics are implemented and tested. Adding overflow ID files alone would
only expose the next failure.

Reproduce the primary-source bundle with the committed V tool, using a new
external directory; it checks HTTP status and fixed content digests before
retaining each file:

```sh
v -o /tmp/sandbox-sources tests/android-webview-browser-probe/sandbox-sources.v
/tmp/sandbox-sources fetch /ABSOLUTE/NEW/STATE/DIRECTORY
/tmp/sandbox-sources verify /ABSOLUTE/NEW/STATE/DIRECTORY
```

Validation: fresh download and verification passed. A modified `bubblewrap.c`
was rejected with `source checksum mismatch`; fetching over the original
bundle was rejected. No kernel or production browser behavior was changed.
