# Real WebKit engine probe

This diagnostic runs the installed aarch64 WebKitGTK 6.0 **2.48.1** and GTK
**4.24.1** in their own process. The fixed local document exercises DOM
JavaScript, cookies in both directions between JavaScript and WebKit's cookie
API, and a snapshot whose pixels and PNG signature are checked. It does not
implement Android WebView, use a Google account, or establish Google sign-in.

From the repository root, build the V host preparation tool:

```sh
v -path '@vlib|build-support' -o /tmp/vinix-browser-prepare tests/android-webview-browser-probe/prepare.v
/tmp/vinix-browser-prepare --self-test
/tmp/vinix-browser-prepare OUTPUT BASE_RUNTIME BASE_APK_CACHE ADDON_APK_CACHE /absolute/path/to/v
```

Use a fresh external `OUTPUT` directory. `BASE_RUNTIME` is the existing staged
`opt/vinix-android-aarch64` directory. `BASE_APK_CACHE` contains the original
archives from `build-support/android/packages.lock.json`; preparation checks all
their hashes and package identities. The 15 additions in this directory's lock
contain Xvfb, its missing dependencies, and core fonts. Missing addon archives
are fetched over HTTPS, with a fixed total compressed budget below 5.6 MB and
exact SHA-256/size checks. Existing cache entries must pass the same checks.

Preparation checks the installed manifest's package list against the pinned
base lock and resolves addon requirements from the archives' actual `.PKGINFO`
names, virtual providers, SONAME providers, and exact version constraints. It
rejects unsupported constraints. It extracts into `OUTPUT/runtime`, rejects
traversal and payload collisions, relocates contained absolute symlinks, and
does not execute package scripts. Original APK signatures are not
cryptographically verified by this diagnostic.

The host requires libarchive (used by the existing V `tarstream` compression
reader) and `/opt/homebrew/bin/aarch64-linux-musl-gcc`. Preparation builds a
dynamic `bin/browser-probe` and static `bin/browser-session` and
`bin/browser-guest`, retains the exact source copies (including the host
collector), and records commands, hashes, compiler pins, and selected base
runtime references in `build.json` and `addon-files.json`.

Stage the complete prepared bundle into an isolated aarch64 Vinix guest, while
preserving executable modes and symlinks. Keep the base runtime under
`/opt/vinix-android-aarch64`. The maintained host stager clones existing APFS
boot media, preserves the original modules and configuration, and appends the
bundle under `/opt/vinix-browser-probe`:

```sh
v -path '@vlib|build-support|build-support/android' -o /tmp/vinix-browser-stage tests/android-webview-browser-probe/stage.v
/tmp/vinix-browser-stage --self-test
/tmp/vinix-browser-stage BASE_BOOT_IMG BASE_EFIVARS_FD OUTPUT FRESH_VM_OUTPUT
```

The stager does not launch QEMU. Its receipt records the original module hashes,
the exact overlay additions, readback checks, and the resulting boot image hash.
An optional final `AUTHORITY_FIXTURE_DIR` argument adds that complete, separately
inventoried fixture under `/opt/vinix-account-authority-fixture`. Its execution
is independent of the browser test. The guest runner pins the selected fixture
binary; pass its complete frozen build directory, including `module/`.

The macOS host lifecycle tool starts the staged image once, records the exact
QEMU command and executable hashes, and checks PID, command, and process start
time before stopping its guest:

```sh
v -o /tmp/vinix-browser-run tests/android-webview-browser-probe/run.v
/tmp/vinix-browser-run --self-test
/tmp/vinix-browser-run start FRESH_VM_OUTPUT
/tmp/vinix-browser-run status FRESH_VM_OUTPUT
```

It requires this checkout's QEMU build and Homebrew firmware at the paths in
`run.v`, refuses another running aarch64 guest, and writes `serial.log`,
`network.pcap`, and a QMP socket within the staged directory. Use the existing
QMP tooling to open the guest terminal and enter:

```sh
/opt/vinix-browser-probe/bin/browser-guest
```

This runs the optional authority fixture with a separate receipt and a bounded
browser session. It exports the complete result tree, including failure logs
and the real PNG, in numbered, checksummed frames through `/dev/console`. The
aarch64 console mirrors these writes to the UART, so QEMU's existing
`-serial file:...` log captures the export even when the command is entered in a
GUI terminal. No boot startup file or existing module is changed. Restore that
export on the host with the maintained collector:

```sh
v -o /tmp/vinix-browser-collect tests/android-webview-browser-probe/collect.v
/tmp/vinix-browser-collect SERIAL_LOG FRESH_EXTERNAL_RESULTS
```

After the export's `END` frame has arrived, stop the owned guest with
`/tmp/vinix-browser-run stop FRESH_VM_OUTPUT`. Retain its launch, ownership,
stop, and disappearance receipts with the evidence.

The collector requires a complete, contiguous export and checks the archive's
size and SHA-256, strict paths, inode types, and every regular file's content
hash before restoring the fresh destination. Keep the serial log and prepared
and staged bundles with the restored result tree. Direct session execution is
also available when a guest filesystem transport is already present:

```sh
/opt/vinix-browser-probe/bin/browser-session /opt/vinix-android-aarch64 /opt/vinix-browser-probe/runtime /tmp/vinix-browser-probe-results
```

The output directory must be fresh. The launcher creates a private authenticated
Xvfb display with TCP disabled, verifies both accepted and rejected X11 cookies,
uses software rendering, and bounds the browser process with an outer watchdog.
Results and the real snapshot are written beneath the output directory. A
successful browser phase prints `BROWSER-PROBE PASS`; the launcher separately
reports whether setup, execution, and cleanup succeeded.

This credential-free, fixed local-document diagnostic explicitly disables the
installed release's namespace sandbox and records the setting. It must not be
used for an account session.

Xvfb and release WebKit have compiled-in helper paths. The launcher uses
exclusive, temporary guest-only aliases to its verified static trampoline at
`/usr/bin/xkbcomp` and `/usr/libexec/webkitgtk-6.0/WebKit{Web,Network,GPU}Process`.
It refuses an existing helper, invokes the pinned helper through the explicit
base musl loader, records alias creation/removal, and removes only its exact
aliases during cleanup. Run this only in an isolated diagnostic guest. It never
installs these aliases on the host.

Preserve the complete external result bundle with checksums under the
repository's [test artifact policy](../../docs/test-artifacts.md). Keep generated
PNG files, binaries, caches, inventories, and raw logs out of Git.
