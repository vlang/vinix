# Linux iOS runtime checks

The iOS compatibility runner executes ARM64 code on Linux. On a Linux ARM64
host, the checks run directly. On an x86-64 Linux host, they build the same
ARM64 runtime and execute it through `qemu-aarch64` user emulation. The real
ARM64 ABI assembly remains enabled in both cases.

This standalone profile requires a GNU/glibc ARM64 target. Native musl
execution is unsupported here; the musl Vinix guest uses the separate VM path.

This path runs the runtime assertions in the maintained fixtures. Native Apple
Foundation comparisons remain in the macOS fixture path; a Linux pass does
not establish a new native-oracle result or a Fortnite launch gate.

## Prerequisites

Use the exact frozen V source revision
`c6bb06f5c04d78f9f6d22a57c257d27e835ba40a`. Its host compiler must report
`V 0.5.2 c6bb06f`, and its directory must retain `v.mod`, `vlib` and
`thirdparty`, including the bundled mbedTLS sources. The official `0.5.2`
Linux release archive contains an older compiler; the version number alone
does not satisfy this pin.

Standalone `vlib/os/execute_capture_nix.c` and
`vlib/builtin/segfault_handler_nix.c` are optional: the stock frozen layout
includes these helpers through headers. If a prepared toolchain supplies the
`.c` helpers, they must match its frozen source and headers.

| Host | Required tools and libraries |
| --- | --- |
| Linux ARM64 | Native GNU C compiler, glibc development files, ARM64 ASan/UBSan runtimes, binutils, Git and OpenSSL |
| Linux x86-64 | Host C compiler for the V driver; GNU `aarch64-linux-gnu-gcc` and binutils; ARM64 glibc development files and ASan/UBSan runtimes; `qemu-aarch64`; Git and OpenSSL |

On Debian/Ubuntu, the cross-tool packages include
`gcc-aarch64-linux-gnu`, `binutils-aarch64-linux-gnu`,
`libc6-dev-arm64-cross`, `libasan8-arm64-cross`,
`libubsan1-arm64-cross` and `qemu-user`. The compiler's development package
and its dependency closure must also be available. Tools may be installed
normally or extracted into an external directory with appropriate paths.

No Apple SDK, Homebrew, graphical display, Vinix kernel or game bundle is
needed for these standalone checks. Optional video, C++, SQLite, GLES and
text backends are disabled in this profile.

## Build the V host driver

Choose existing source/toolchain directories and an external state directory.
Generated C, objects, executables, certificates and logs must stay outside Git.

```sh
export VINIX_CHECK_ROOT=/path/to/vinix
export VINIX_CHECK_STATE=/path/outside/vinix/ios-linux
export VINIX_IOS_TOOLCHAIN=/path/to/frozen-v-c6bb06f
mkdir -p "$VINIX_CHECK_STATE/tmp" "$VINIX_CHECK_STATE/cache" \
  "$VINIX_CHECK_STATE/vmodules"
export TMPDIR="$VINIX_CHECK_STATE/tmp"
export XDG_CACHE_HOME="$VINIX_CHECK_STATE/cache"
export VMODULES="$VINIX_CHECK_STATE/vmodules"
export V_RESOURCE_PATH="$VINIX_IOS_TOOLCHAIN"
export V_SKIP_VVMRC=1
export V_MACOS_V3_NO_FALLBACK=1

cd "$VINIX_IOS_TOOLCHAIN"
./v -gc none -cc cc \
  -path "@vlib|$VINIX_CHECK_ROOT/tests/ios|@vmodules" \
  -o "$VINIX_CHECK_STATE/linux-checks" \
  "$VINIX_CHECK_ROOT/tests/ios/linux-checks.v"
cd "$VINIX_CHECK_ROOT"
```

The driver validates the frozen compiler version, the C compiler's Linux
ARM64 target, and each produced ELF before execution. An x86-64 binary is
rejected instead of using the runner's non-ARM64 ABI stubs.

## Select tools

The usual installed-tool layout needs no overrides beyond the frozen V root.
These overrides support alternate executable names and relocated SDKs:

| Environment variable | Meaning and default |
| --- | --- |
| `VINIX_IOS_TOOLCHAIN` | Frozen V directory; otherwise the directory of `v` on PATH |
| `VINIX_IOS_LINUX_CC` | Target C compiler; `cc` on ARM64, `aarch64-linux-gnu-gcc` on x86-64 |
| `VINIX_IOS_LINUX_SYSROOT` | Optional compiler `--sysroot`; unset uses the compiler's configured layout |
| `VINIX_IOS_LINUX_GCC_LOW_MEMORY` | Set to `1` to lower GCC's collector growth thresholds for generated C; defaults to `0` |
| `VINIX_IOS_QEMU_USER` | ARM64 user emulator on x86-64; defaults to `qemu-aarch64`; `qemu-aarch64-static` may be selected explicitly |
| `VINIX_IOS_LINUX_LD_PREFIX` | QEMU target loader/library prefix; defaults to `/usr/aarch64-linux-gnu` |

The loader prefix must contain `lib/ld-linux-aarch64.so.1`. It serves a
different purpose from the compiler sysroot. For Ubuntu cross packages
extracted below `SDK`, the compiler sysroot can be `SDK`, while the loader
prefix is `SDK/usr/aarch64-linux-gnu`. Relocated binutils may also require
their extracted **host** shared-library directory in `LD_LIBRARY_PATH`.

On a host where GCC is killed under memory pressure, the optional low-memory
setting adds `--param=ggc-min-expand=10` and
`--param=ggc-min-heapsize=16384` to the generated-C/ABI compilation. It requires
GNU GCC and can trade compilation time for lower peak memory. The capture
records this choice; V assertions, `-O1`, debug information, ASan/UBSan and
runtime deadlines remain the same. Values other than `0` or `1` are refused.

## Run checks

Run the driver from the Vinix repository root. Each output's parent must
already exist; the output directory itself must be fresh. Existing paths and
paths that resolve into the repository through symlinks are refused.

```sh
"$VINIX_CHECK_STATE/linux-checks" url-request "$VINIX_CHECK_STATE/request-r1"
"$VINIX_CHECK_STATE/linux-checks" data-http "$VINIX_CHECK_STATE/http-r1"
"$VINIX_CHECK_STATE/linux-checks" storekit-purchase "$VINIX_CHECK_STATE/storekit-r1"
"$VINIX_CHECK_STATE/linux-checks" netdb-scope "$VINIX_CHECK_STATE/netdb-r1"
"$VINIX_CHECK_STATE/linux-checks" reachability "$VINIX_CHECK_STATE/reachability-r1"
"$VINIX_CHECK_STATE/linux-checks" network-path "$VINIX_CHECK_STATE/network-path-r1"
"$VINIX_CHECK_STATE/linux-checks" build-run-ios "$VINIX_CHECK_STATE/runner-r1"
```

| Mode | Verification |
| --- | --- |
| `url-request` | Request policy, copies, headers, method spelling and rejection controls |
| `data-http` | Full runtime HTTP/TLS fixture, including disabled-cookie policy and callback/ownership checks |
| `storekit-purchase` | StoreKit capability/queue/observer checks and the selector-table growth race regression |
| `netdb-scope` | Linux IPv6 numeric-scope behavior and output-buffer/error semantics |
| `reachability` | Reachability callbacks, context ownership, cancellation and joined shutdown across two runtime cycles |
| `network-path` | Network-path monitors, queued/in-flight callbacks, cancellation and joined shutdown across two runtime cycles |
| `build-run-ios` | Core runner build, help/inspection and execution of a generated synthetic iOS Mach-O |

Invoke `reachability` and `network-path` through this standalone driver;
their plain names in `notification-checks` retain VM routing.

Fixture modes compile C at `-O1` with AddressSanitizer and UBSan, retaining all
V assertions, then execute once with
ordinary settings and once with `SWIFT_DETERMINISTIC_HASHING=1`. LeakSanitizer
is disabled. A zero exit without all required coverage markers is not a pass.
The HTTP fixture generates a private loopback TLS certificate and key; it does
not change the production trust store.

For child builds and fixture runs, the driver removes inherited V options,
compiler flags, test filters, backend controls and `QEMU_*` controls.
Assertions and full fixture selection remain enforced. It ignores `.vvmrc`
and uses fresh `OUT/tmp`, `OUT/cache` and `OUT/vmodules` directories for
temporary files, V caches and module lookup.

On Linux, the maintained `notification-checks` modes `url-request-host`,
`data-http-host`, `storekit-purchase-host` and `build-run-ios` route to this
implementation. Their Linux receipts identify native Foundation as unexecuted.
The macOS host comparison path retains its native assertions.

`build-run-ios` is unsanitized and produces `OUT/run-ios`. Its synthetic
ARM64 Mach-O requires no frameworks or Apple SDK. The entry checks `argc`
and `argv`, returns **37** for the ordinary invocation, and returns **99**
when the driver supplies an extra argument. These expected exits check actual
mapping, entry and argument forwarding. They establish no Fortnite result.

## Evidence and full game captures

The driver builds fixture/ABI code from its captured source copy. The output
contains the source revision/diff, copied source and driver, selected tool
hashes, target/compiler versions, generated C, objects, bundled TLS archive,
per-command logs and exit receipts, and `qualification.json`. Successful
completion writes the SHA-256 `inventory.json` before the final `result.txt`.
The inventory covers captured files and the final receipt, excluding itself.
It includes hidden files, reports traversal and hashing errors, and rejects
symlinks and entries that are neither regular files nor directories.
Retain the whole output tree, including failed attempts; a final marker alone
is not a reproducible capture.

Child execution uses a process-group guard with a 600-second command limit;
the entire nested TLS build is covered by its worker's guard. Failure,
sanitizer and coverage diagnostics remain in the external output.

Audit completed captures with the maintained checker, using the same external
environment as the driver build:

```sh
cd "$VINIX_IOS_TOOLCHAIN"
./v -gc none -cc cc -o "$VINIX_CHECK_STATE/linux-evidence-check" \
  "$VINIX_CHECK_ROOT/tests/ios/linux-evidence-check.v"
"$VINIX_CHECK_STATE/linux-evidence-check" --self-test "$VINIX_CHECK_STATE/audit-controls-r1"
"$VINIX_CHECK_STATE/linux-evidence-check" "$VINIX_CHECK_STATE/request-r1"
cd "$VINIX_CHECK_ROOT"
```

The checker verifies every recorded hash and complete file coverage, including
hidden files, and returns nonzero on a mismatch. Its self-test creates one
valid tree and 19 corruption controls in a fresh external directory; keep that
directory separate from captures. Audit only after all capture writers stop.

For the musl/GLES **Vinix guest** build and VM launch, see
[iOS VM host tools](hosttools/README.md). That path also needs the selected
kernel, firmware, bootloader, dependency SDKs and prepared guest inputs.
A Fortnite probe additionally requires the original unencrypted application,
bundled frameworks, resources and cooked content. The minimal core runner
above does not substitute for that complete runtime and input set.

Historical checkpoint binaries, sealed parents and auditors remain unchanged.
Keep their full evidence and original validation requirements; record a fresh
Linux capture separately. Source/build success, standalone runtime checks,
native Foundation comparisons and a guarded Fortnite launch are distinct
results. Report only the launch gates established by the actual game capture.
