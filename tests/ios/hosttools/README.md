# iOS VM host tools

`notification-vm.v` builds Linux AArch64 guest executables on Linux or macOS.
The host operating system selects tools and acceleration; it does not change
the guest ABI, fixtures, result markers, RAM/CPU limits or failure checks.
Linux defaults to QEMU TCG with CPU `max`, including on an x86-64 host. Apple
Silicon retains HVF with CPU `host`. Linux ARM64 can explicitly select KVM.

Compile the driver with the frozen V 0.5.2 toolchain (`c6bb06f`) and the existing
`compat/ios` and `tests/ios` module search paths. All output and evidence must be
external to the repository. The unchanged driver modes include `data-http`,
`build-run-ios-gles` and `probe-no-ads`.

## Compile and invoke the Linux VM wrapper

Use an empty external directory for a new capture. The example paths below
must be replaced with your checkout, frozen Linux V toolchain and external
output directory. Native Clang must be on PATH for these two host executables.

```sh
export VINIX_IOS_REPO=/absolute/path/to/vinix
export VINIX_IOS_TOOLCHAIN=/external/toolchains/v-c6bb06f
export VINIX_IOS_OUT=/external/captures/ios-vm-linux
export V_RESOURCE_PATH="$VINIX_IOS_TOOLCHAIN"
export V_MACOS_V3_NO_FALLBACK=1
export V_SKIP_VVMRC=1
mkdir -p "$VINIX_IOS_OUT/tmp"
export TMPDIR="$VINIX_IOS_OUT/tmp"

cd "$VINIX_IOS_TOOLCHAIN"
"$VINIX_IOS_TOOLCHAIN/v" -enable-globals -gc none -cc clang \
  -path "@vlib|$VINIX_IOS_REPO/compat/ios|$VINIX_IOS_REPO/tests/ios|@vmodules" \
  -o "$VINIX_IOS_OUT/notification-vm" "$VINIX_IOS_REPO/tests/ios/notification-vm.v"
"$VINIX_IOS_TOOLCHAIN/v" -enable-globals -gc none -cc clang \
  -path "@vlib|$VINIX_IOS_REPO/compat/ios|$VINIX_IOS_REPO/tests/ios|@vmodules" \
  -o "$VINIX_IOS_OUT/notification-checks" "$VINIX_IOS_REPO/tests/ios/notification-checks.v"
cd "$VINIX_IOS_REPO"
```

Before running a mode, supply the prepared ARM64 musl inputs listed below.
Every build needs the musl sysroot, GCC support objects, C++ archives, video
archives and SQLite archives. Set their `VINIX_IOS_*` overrides if the listed
checkout defaults do not exist. Booting a fixture additionally needs QEMU,
firmware, a CA bundle, bsdtar, `mformat`, `mmd`, `mcopy`, the Vinix ARM64 kernel
and Limine. The HTTP fixture uses `/usr/bin/openssl` to create its local TLS
test certificate. These inputs are distinct from the glibc cross-toolchain
used by `tests/ios/linux-checks.v`.

Invoke the wrapper from the repository root. It supplies
`VINIX_IOS_CHECK_NAME=notification-center-checks`, selects the configured V
resource directory and preserves per-mode logs/status in the external output.
The VM executable must be named `notification-vm` inside that output directory.
On Linux, the wrapper guards the entire VM driver and its build/archive/QEMU
process group with a 3,600-second outer deadline and a 16 MiB output check.
The VM's existing guest timeout remains in effect. Per-mode `.log` and
`.status.txt` names are retained; separate command, elapsed-time and cleanup
receipts record the outer guard. Capture uses a regular file, so an orphan
holding stdout cannot keep a capture pipe open indefinitely.
The Linux wrapper also removes inherited V options, compiler flags, test
filters and `QEMU_*` controls, ignores `.vvmrc`, and preserves explicit
`VINIX_IOS_*` tool, SDK and game settings.

```sh
"$VINIX_IOS_OUT/notification-checks" data-http "$VINIX_IOS_OUT"
"$VINIX_IOS_OUT/notification-checks" build-run-ios-gles "$VINIX_IOS_OUT"
```

`data-http` builds its fixture and native init, then boots the fixture in Vinix.
`build-run-ios-gles` builds the GLES runner; it also needs the Mesa/GLES input
directories. A fresh `probe-no-ads` bundle needs the required support fixtures
as well as the runner and native init. The maintained `build` mode produces
that complete executable set:

```sh
"$VINIX_IOS_OUT/notification-checks" build "$VINIX_IOS_OUT"
"$VINIX_IOS_OUT/notification-checks" probe-no-ads "$VINIX_IOS_OUT"
```

The probe additionally requires your existing Fortnite app/Frameworks and
preserved probe initramfs, selected with `VINIX_IOS_APP_BUNDLE` and
`VINIX_IOS_PROBE_INITRAMFS` when their defaults are absent. Full cooked content
and storyboard overlays retain their existing explicit controls. Ads remain
skipped in `probe-no-ads`. The VM wrapper accepts an existing external output
directory for these successive build/probe modes; preserve a completed capture
before rerunning a mode whose replay state would be replaced. The Linux guard
refuses an existing per-mode log; archive and clear that mode's old outer
receipts before an intentional rerun, or use a new external capture directory.

On Linux, the `url-request-host`, `data-http-host`, `storekit-purchase-host` and
`build-run-ios` wrapper modes use the separate Linux runtime-check path and
require a fresh output directory of their own. Other native Apple oracle
modes remain unavailable on Linux. A fresh Fortnite checkpoint must report
its observed launch gates and separately state whether a frame, menu, login
or gameplay was verified.

## Host selection

| Environment variable | Selection |
| --- | --- |
| `VINIX_IOS_TOOLCHAIN` | Directory containing the frozen host `v` and `vlib` |
| `VINIX_IOS_CLANG` | Clang executable for the musl AArch64 build |
| `VINIX_IOS_LD` | ELF `ld.lld` executable; defaults to Clang's sibling, then PATH |
| `VINIX_IOS_QEMU` | `qemu-system-aarch64` executable |
| `VINIX_IOS_ACCEL` | `tcg`, or `kvm` on Linux ARM64, or `hvf` on macOS ARM64 |
| `VINIX_IOS_FIRMWARE_CODE` | Read-only AArch64 virt pflash code image, exactly 64 MiB |
| `VINIX_IOS_FIRMWARE_VARS` | Optional 64 MiB variable template copied privately for each run |
| `VINIX_IOS_CA_BUNDLE` | Readable PEM CA bundle copied into the guest trust-store path |
| `VINIX_IOS_BSDTAR` | Libarchive `bsdtar`, required for streaming archive overlays |
| `VINIX_IOS_KERNEL` | Existing ARM64 ELF kernel; its path is recorded before boot |
| `VINIX_IOS_LIMINE` | Existing `BOOTAA64.EFI` bootloader |

Unset macOS tool choices retain the Homebrew and system BSD tar defaults.
Linux finds Clang, lld, QEMU and bsdtar on PATH. Firmware discovery checks
`/usr/share/AAVMF/AAVMF_CODE.fd` and
`/usr/share/qemu/edk2-aarch64-code.fd`; otherwise supply the explicit path.
A matching packaged Linux vars template is used when available. The historical
macOS default remains a fresh blank 64 MiB variable store. Neither the selected
firmware nor its template is modified. The private vars copy is set to mode
`0600`, including when its packaged template is read-only. QEMU's full argument
vector is recorded, with commas escaped inside drive file names.
Explicit invalid tool and input overrides fail instead of falling back.

The CA-bundle default is `/etc/ssl/certs/ca-certificates.crt` on Linux and
`/etc/ssl/cert.pem` on macOS. An explicit override must name a readable regular
file containing PEM certificates. The guest still reads `/etc/ssl/cert.pem`
and performs the same TLS certificate and trust checks.

## Existing cross-build and game inputs

The defaults below preserve the historical prepared-checkout layout. Overrides
allow a Linux host to keep equivalent inputs in external directories; they do
not download or manufacture missing inputs.

| Environment variable | Default below repository root |
| --- | --- |
| `VINIX_IOS_SYSROOT` | `build/ios/fortnite/date-encoding-checks/sdk` |
| `VINIX_IOS_GCC_LIB` | `build/useralloc-pipe/static-desktop-v5/sysroot/usr/lib/gcc/aarch64-alpine-linux-musl/14.2.0` |
| `VINIX_IOS_MESA_SYSROOT` | The selected musl sysroot |
| `VINIX_IOS_CXX_DIR` | `build/ios/cxx` |
| `VINIX_IOS_VIDEO_DIR` | `build/ios/fortnite/video-decode-deps` |
| `VINIX_IOS_SQLITE_DIR` | `build/ios/sqlite` |
| `VINIX_IOS_GLES_LIBDIR` | `build/ios/fortnite/staging/usr/lib/vinix/ios-gles` |
| `VINIX_IOS_APP_BUNDLE` | `build/ios/fortnite/local/Payload/FortniteClient-IOS-Shipping.app` |
| `VINIX_IOS_PROBE_INITRAMFS` | `build/ios/fortnite/probe-initramfs.tar.gz` |

The V toolchain default remains
`build/ios/fortnite/ns-calendar-checks/toolchain`; the kernel default remains
`build/ios/fortnite/socket-kernel-arm64/bin/vinix`. Existing cooked-content,
storyboard, desktop, process-budget and guest-CPU controls are unchanged.

These host choices do not make the saved macOS checkpoint executables runnable
on Linux. Historical evidence and its complete auditor remain unchanged. A
fresh Linux capture needs its own recorded host inputs and executable tools.
Linux runtime tests also do not replace the native Apple Foundation oracle.
