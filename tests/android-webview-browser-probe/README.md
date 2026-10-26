# Real WebKit engine probe

This diagnostic runs the installed aarch64 WebKitGTK 6.0 **2.48.1** and GTK
**4.24.1** in their own process. The fixed local document exercises DOM
JavaScript, cookies in both directions between JavaScript and WebKit's cookie
API, and a snapshot whose pixels and PNG signature are checked. It does not
implement Android WebView, use a Google account, or establish Google sign-in.

The constructor regression can run on the host without GTK or WebKit:

```sh
v -o /tmp/vinix-browser-probe tests/android-webview-browser-probe/probe.v
/tmp/vinix-browser-probe --self-test
```

It checks that the policy and JavaScript settings exist when the view is
constructed, that the same settings survive construction, and that temporary
references are released on success and rejected construction paths.

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

For an Xvfb startup fault investigation, preparation accepts an optional final
`FAULT_BUILD_DIR` from the maintained
[`android-x11-fault-probe`](../android-x11-fault-probe) builder. It copies the
complete small bundle under `OUTPUT/fault-probe` and pins every file. The guest
first runs its controlled known-fault executable with the pinned interposer,
requires its successful handler query/restoration/chaining checks and fault
register/mapping evidence, and retains `x11-known-fault.log`. Only this fixture
and Xvfb use musl's explicit `--preload` loader argument. No `LD_PRELOAD`
environment variable reaches the browser or inherited helper processes.
The original Xvfb binary is unchanged. An incomplete or changed diagnostic
bundle fails before Xvfb starts. Fault instrumentation is separate diagnostic
evidence and does not establish browser success or account authentication.

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

`patch-kernel.v FRESH_STAGE FROZEN_KERNEL_BUILD BUILD_JSON_SHA256` can replace
the kernel before the first launch. It accepts only the pinned Maps372 browser
baseline. Its `--maps-account` profile accepts the separate pinned headless r4
baseline, the six original modules in their audited order, and one appended
`maps-account.tar`. It verifies the complete frozen kernel inventory, checks
every FAT module before and after replacement, preserves configuration and
firmware, and records the selected profile. A previously launched or patched
stage is rejected. `--self-test` exercises both overlay names on real FAT images
and rejects changed Maps module ordering, missing or substituted overlays, and
an unaudited baseline module list. This operation supplies no login evidence.

The macOS host lifecycle tool starts the staged image once, records the exact
QEMU command and executable hashes, and checks PID, command, and process start
time before stopping its guest:

```sh
v -o /tmp/vinix-browser-run tests/android-webview-browser-probe/run.v
/tmp/vinix-browser-run --self-test
/tmp/vinix-browser-run start FRESH_VM_OUTPUT
/tmp/vinix-browser-run status FRESH_VM_OUTPUT
```

If an already recorded stop was interrupted, `reconcile-stop FRESH_VM_OUTPUT`
checks the matching ownership and stop receipts, confirms process disappearance,
and writes the missing receipt without sending another signal. Shutdown polling
tolerates QEMU removing its PID file while the same owned process is exiting.

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
and staged bundles with the restored result tree. `--headless`, `--account-ui`,
`--maps-account`, and `--token-cache` select their respective guest protocols. Each mode rejects
frames from every other protocol, including frames embedded in console chatter.
The Maps/GMS controller permits at most 16 MiB per file, 48 MiB of file content,
and a 72 MiB archive; the other modes retain their 8/16/32 MiB bounds. Maps/GMS
readiness records transport setup and does not prove Google authentication.
The producer excludes private Maps and broker logs from its serial export.
The token-cache mode retains the signed synthetic fixture's lifecycle receipt
and logs. Its accounts and tokens are test values; a passing fixture does not
prove Google authentication.

Direct session execution is also available when a guest filesystem transport
is already present.

If unrelated console output corrupts the transfer, retain that failed transfer
and retransmit the unchanged `/tmp/vinix-browser-probe-results.json` archive
after stopping the noisy application. `recover-export.v SERIAL_LOG FRESH_OUTPUT`
accepts only one raw archive matching the original transfer header's exact
length and SHA-256. It preserves the original serial bytes and reconstructs
framing for the ordinary strict collector; run that collector on
`FRESH_OUTPUT/serial-reconstructed.log`. Its `--self-test` rejects altered,
truncated and ambiguous retransmissions. This does not replace archive or
file validation.

```sh
/opt/vinix-browser-probe/bin/browser-session /opt/vinix-android-aarch64 /opt/vinix-browser-probe/runtime /tmp/vinix-browser-probe-results
```

The output directory must be fresh. The launcher creates a private authenticated
Xvfb display with TCP disabled, verifies both accepted and rejected X11 cookies,
uses software rendering, and bounds the browser process with an outer watchdog.
For this CPU-rendered local fixture only, Xvfb starts with `-extension GLX`.
The retained startup fault evidence showed the base Mesa/LLVM runtime loading
the original guest's older DRI/LLVM stack. Disabling GLX prevents that server
extension from loading a separate DRI driver. The launcher also sends an
authenticated X11 `QueryExtension` request and requires GLX to be absent before
starting the browser; `session.json` records the policy and the checked result.
This diagnostic setting does not qualify accelerated rendering or account use.
The loader searches `usr/lib/libproxy` under both pinned runtime roots, with
the base runtime first, so libproxy's backend resolves inside the relocated
runtime. The preparation receipt pins `usr/lib/libproxy/libpxbackend-1.0.so`;
the session rejects an unpinned, missing or changed backend and records its
path/hash and the full library search path in `session.json`. This addresses
the separate missing-backend message from the r8 diagnostic; it does not
establish that the surfaceless EGL failure is resolved.
Each added search directory and its parents within the runtime must be owned
by root without group/world writes. The session and helper trampoline reject
linked or unpinned backend entries and recheck their hashes before launch.
The launcher also selects WebKit's Skia CPU image buffers with
`WEBKIT_SKIA_ENABLE_CPU_RENDERING=1` and disables compositing before WebKit
initializes with `WEBKIT_DISABLE_COMPOSITING_MODE=1`. GTK's separate
`GSK_RENDERER=cairo` setting does not control Skia image buffers. These switches
are implemented by the exact installed release's
[WebProcess initialization](https://github.com/WebKit/WebKit/blob/webkitgtk-2.48.1/Source/WebKit/WebProcess/glib/WebProcessGLib.cpp)
and [hardware acceleration manager](https://github.com/WebKit/WebKit/blob/webkitgtk-2.48.1/Source/WebKit/UIProcess/gtk/HardwareAccelerationManager.cpp).
It separately disables DMA-BUF transport with `WEBKIT_DISABLE_DMABUF_RENDERER=1`,
which the release's
[DMA-BUF backing store](https://github.com/WebKit/WebKit/blob/webkitgtk-2.48.1/Source/WebKit/UIProcess/gtk/AcceleratedBackingStoreDMABuf.cpp)
checks before probing EGL transport capabilities. This setting was already
present in the r8 launcher; recording and testing it does not resolve that
run's surfaceless EGL initialization failure.
The probe now creates `WebKitSettings`, selects the GTK4 `NEVER` hardware policy,
then passes those settings through the view's public `settings` construct
property. The exact release's
[WebKitWebView construction](https://github.com/WebKit/WebKit/blob/webkitgtk-2.48.1/Source/WebKit/UIProcess/API/glib/WebKitWebView.cpp)
copies the settings into its initial page configuration. Applying the policy
only after `webkit_web_view_new()` leaves that initial configuration exposed
to the default policy. This change tests that ordering hypothesis; a real
guest pass is still required. The probe checks the accepted policy before and
after construction and logs `cpu-settings=preconstructed policy=never`.
The FFI uses GLib 2.90.0's nonvariadic
[`g_object_new_with_properties`](https://github.com/GNOME/glib/blob/2.90.0/gobject/gobject.h)
and initializes/releases its public
[`GValue`](https://github.com/GNOME/glib/blob/2.90.0/gobject/gvalue.h)
through GLib APIs. The self-test checks the 64-bit structure size and data offset.
The inherited force-compositing override is removed. The launcher sets
`WEBKIT_INJECTED_BUNDLE_PATH` to the relocated runtime's pinned
`usr/lib/webkitgtk-6.0/injected-bundle` directory, as supported by
[WebKitWebContext](https://github.com/WebKit/WebKit/blob/webkitgtk-2.48.1/Source/WebKit/UIProcess/API/glib/WebKitWebContext.cpp).
Preparation records the bundle's SHA-256; the session rejects an absent,
unpinned, or changed bundle. `session.json` records the selected renderer,
compositing and DMA-BUF policies, bundle directory, and checked bundle hash. These settings
exercise the local document's CPU path; they do not establish WebGL support.
Results and the real snapshot are written beneath the output directory. A
successful browser phase prints `BROWSER-PROBE PASS`; the launcher separately
reports whether setup, execution, and cleanup succeeded.

This credential-free, fixed local-document diagnostic explicitly disables the
installed release's namespace sandbox and records the setting. It must not be
used for an account session.

Xvfb and release WebKit have compiled-in helper paths. When those paths are absent,
the launcher creates exclusive, temporary guest-only aliases to its verified static trampoline at
`/usr/bin/xkbcomp` and `/usr/libexec/webkitgtk-6.0/WebKit{Web,Network,GPU}Process`.
It refuses existing WebKit helpers. The original Maps372 image already contains
`xkbcomp`; `guest-helpers.lock.json` pins its exact bytes and original musl
interpreter. The session verifies and reuses those files in place, checks their
hashes again after the probe, and records preservation separately from alias
cleanup. Any other existing file or symlink fails closed. Absent helpers use the
trampoline and explicit base musl loader. Cleanup removes only aliases created
by this session. Run this only in an isolated diagnostic guest.

`inspect-helper.v BOOT_IMG MODULE.tar...` streams the original boot modules and
reports the fixed helper and interpreter hashes and ELF properties without
extracting a whole module. Pass all modules in their boot order when auditing
the committed existing-helper pins.

Preserve the complete external result bundle with checksums under the
repository's [test artifact policy](../../docs/test-artifacts.md). Keep generated
PNG files, binaries, caches, inventories, and raw logs out of Git.

`seal.v` binds complete external roots in place without copying disk images.
Build it on macOS with `v -prod -o /tmp/vinix-browser-seal tests/android-webview-browser-probe/seal.v` and run its
`--self-test`. After stopping the guest and collecting the export, run
`/tmp/vinix-browser-seal seal FRESH_SEAL_DIR STOPPED_VM_DIR BUILD_DIR RESULTS_DIR`
with any additional complete fixture/tool directories or individual external
tool files. It requires matching ownership,
stop, and disappearance receipts and an absent guest PID. It freezes its own
source and binary and prints the manifest hash. Later use
`/tmp/vinix-browser-seal check SEAL_DIR MANIFEST_SHA256` to detect added, missing,
or changed entries across every retained root. Symlinks are recorded without
following them; sockets and other special entries fail closed. Keep the roots
at their recorded paths and preserve the full trees.

When one stopped VM's UART contains several independent protocol phases, use
`serial-range.v` to preserve the full capture and select explicit bytes for a
single strict collector invocation:

```sh
v -o /tmp/vinix-serial-range tests/android-webview-browser-probe/serial-range.v
/tmp/vinix-serial-range --self-test
/tmp/vinix-serial-range /absolute/canonical/uart.log START END /absolute/canonical/fresh-range
/tmp/vinix-serial-range --check /absolute/canonical/fresh-range
```

`START` is inclusive and `END` exclusive, both canonical decimal byte offsets.
The range must start at byte zero or after LF, and end immediately after LF;
a partial final line is rejected. The source must be a stable, single-link
regular file of at most 256 MiB. Two complete reads, matching SHA-256 hashes,
and descriptor/path metadata checks reject observed changes and replacement.
Input and output parents must exist without symlinks; output must be fresh and
outside the checkout. Each bundle contains the complete `serial-original.log`,
the byte-exact `serial-range.log`, and `range.json` with both byte counts and
SHA-256 hashes plus the explicit offsets. `--check` verifies all retained bytes
against the receipt and the exact original range, without requiring the live
source. Preserve and seal the full bundle; its self-contained hashes do not
authenticate a replacement of the entire bundle. Pass only `serial-range.log`
to the appropriate unchanged strict protocol collector. Selection does not
establish that any protocol, browser, or account test passed.
