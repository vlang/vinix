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
needed for the standalone fixtures and synthetic entry checks. The core
modes disable optional video, C++, SQLite, GLES and text backends. The `gles`
and `cxx` profiles enable their selected backends; combined modes enable both.
The separate `probe-no-ads` mode requires a supplied application and both
backend dependency sets. These profiles are described below.

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
./v -enable-globals -nocache -gc none -cc cc -cflags -O2 \
  -path "@vlib|$VINIX_CHECK_ROOT/tests/ios|$VINIX_CHECK_ROOT/compat/ios|@vmodules" \
  -o "$VINIX_CHECK_STATE/linux-checks" \
  "$VINIX_CHECK_ROOT/tests/ios/linux-checks.v"
cd "$VINIX_CHECK_ROOT"
```

The driver validates the frozen compiler version, the C compiler's Linux
ARM64 target, and each produced ELF before execution. An x86-64 binary is
rejected instead of using the runner's non-ARM64 ABI stubs.
The host driver's optimization keeps large SDK hashing practical; it retains
V assertions and does not change the separately recorded runtime build flags.

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
| `VINIX_IOS_LINUX_READELF` | ELF dependency/export inspector for C++ modes; defaults to `readelf` |
| `VINIX_IOS_LINUX_CXX_UBSAN_ARCHIVE` | Explicit compatible ARM64 `libubsan.a`; required for sanitized C++ modes, with no implicit archive selection |

The loader prefix must contain `lib/ld-linux-aarch64.so.1`. It serves a
different purpose from the compiler sysroot. For Ubuntu cross packages
extracted below `SDK`, the compiler sysroot can be `SDK`, while the loader
prefix is `SDK/usr/aarch64-linux-gnu`. The GNU C++ builder's `--sysroot`
instead takes that latter GNU header/library prefix: it requires
`include/stdio.h` directly below it. These are different levels of the same
extracted SDK. Relocated binutils may also require their extracted **host**
shared-library directory in `LD_LIBRARY_PATH`.

On a host where GCC is killed under memory pressure, the optional low-memory
setting adds `--param=ggc-min-expand=10` and
`--param=ggc-min-heapsize=16384` to the generated-C/ABI compilation. It requires
GNU GCC and can trade compilation time for lower peak memory. The capture
records this choice; V assertions, `-O1`, debug information, ASan/UBSan and
runtime deadlines remain the same. Values other than `0` or `1` are refused.
The maintained GCC compilation also uses `-pipe` to pass assembly between
compiler stages without a large temporary assembly file. This preserves
the selected optimization, assertions and sanitizer checks.

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
"$VINIX_CHECK_STATE/linux-checks" image-initializers "$VINIX_CHECK_STATE/initializers-r1"
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
| `image-initializers` | Constructor table bounds and six actual Mach-O executions with normal and lower-segment layouts, including an executable decoy constructor |
| `build-run-ios` | Core runner build, help/inspection and execution of a generated synthetic iOS Mach-O |
| `gles` | Mesa EAGL/GLKView rendering, shader and published pixels, method discovery, ARM64 argument widths, graphics state and thread/context ownership |
| `build-run-ios-gles` | GLES-enabled Linux runner build and synthetic Mach-O entry/arguments |
| `cxx` | Adapted C++ ABI assertions in V, including conversion/layout canaries and runtime thread cleanup; native ELF C++ fixture and mandatory valid/vptr/function sanitizer controls |
| `cxx-gles` | The GLES fixture with adapted C++ linked, checking the combined runtime; does not select the separate C++ fixture |
| `build-run-ios-cxx` | C++-enabled runner build and synthetic Mach-O entry/arguments |
| `build-run-ios-cxx-gles` | Combined C++/GLES runner build and synthetic Mach-O entry/arguments |
| `probe-no-ads` | Inspect, audit and guarded launch of an explicitly supplied app with a diagnostic desktop peer; capture completion is not game success |

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

The `build-run-ios*` modes are unsanitized and produce `OUT/run-ios`. Their
synthetic ARM64 Mach-O requires no frameworks or Apple SDK. The entry checks `argc`
and `argv`, returns **37** for the ordinary invocation, and returns **99**
when the driver supplies an extra argument. These expected exits check actual
mapping, entry and argument forwarding. They establish no Fortnite result.

## GNU/Linux C++ profile

The GNU builder adapts the pinned LLVM 19.1.7 libc++, libc++abi and libunwind
sources for the runtime's Apple-facing ABI on ARM64 glibc. It requires a host
Clang C++ compiler, LLVM archiver and a GNU ARM64 header/library prefix. The
compiler's Clang resource headers must remain available. LLVM source version
19.1.7 does not require a version-19 host compiler; the selected compiler and
archiver identities are recorded in the output.

Build the maintained V command in an external directory. This frozen host
build needs `-DV_OS_EXECUTE_CAPTURE_NIX_H` and a host libarchive linker input.
A distribution's `libarchive-dev` package normally supplies the linker name;
the maintained `tarstream/filter_abi.h` supplies declarations, so a libarchive
development header is not an input. If using a private directory containing
`libarchive.so`, add `-ldflags "-L/path/to/hostlib"` and record the alias and
resolved host library separately from the ARM64 C++ dependencies.

```sh
export VINIX_CXX_STATE="$VINIX_CHECK_STATE/cxx-build"
export VINIX_CXX_SYSROOT=/path/to/arm64-cross-sdk/usr/aarch64-linux-gnu
export VINIX_CXX_COMPILER=/path/to/clang++
export VINIX_CXX_ARCHIVER=/path/to/llvm-ar
mkdir -p "$VINIX_CXX_STATE/tmp" "$VINIX_CXX_STATE/cache"

cd "$VINIX_CHECK_ROOT"
env V_RESOURCE_PATH="$VINIX_IOS_TOOLCHAIN" V_SKIP_VVMRC=1 \
  V_MACOS_V3_NO_FALLBACK=1 V_CACHE_ROOT="$VINIX_CXX_STATE/cache" \
  TMPDIR="$VINIX_CXX_STATE/tmp" \
  "$VINIX_IOS_TOOLCHAIN/v" -gc none -cc cc \
  -cflags '-O2 -DV_OS_EXECUTE_CAPTURE_NIX_H' \
  -path "$VINIX_CHECK_ROOT/build-support/ios|$VINIX_CHECK_ROOT/build-support|$VINIX_CHECK_ROOT/tools|@vlib" \
  -o "$VINIX_CXX_STATE/ios-build-gnu" "$VINIX_CHECK_ROOT/build-support/ios/main.v"

"$VINIX_CXX_STATE/ios-build-gnu" build-cxx --target aarch64-linux-gnu \
  --output "$VINIX_CXX_STATE/asan" --sources "$VINIX_CXX_STATE/sources" \
  --sysroot "$VINIX_CXX_SYSROOT" --compiler "$VINIX_CXX_COMPILER" \
  --archiver "$VINIX_CXX_ARCHIVER" --sanitizers
"$VINIX_CXX_STATE/ios-build-gnu" build-cxx --target aarch64-linux-gnu \
  --output "$VINIX_CXX_STATE/runtime" --sources "$VINIX_CXX_STATE/sources" \
  --sysroot "$VINIX_CXX_SYSROOT" --compiler "$VINIX_CXX_COMPILER" \
  --archiver "$VINIX_CXX_ARCHIVER"
```

`--target aarch64-linux-gnu` must be the first option after `build-cxx`.
Always supply an external `--output` and `--sources`; the command's default
output is inside the repository. The builder verifies the three source
archive hashes, qualifies their extracted source trees and uses a private
temporary directory for child compilation. Preserve its complete output and
source cache. Existing builder outputs can reuse verified objects, so keep
sanitized and unsanitized outputs separate.

Select the matching build with `VINIX_IOS_LINUX_CXX_ROOT`. Fixture modes
`cxx` and `cxx-gles` require the `--sanitizers` output; runner/probe modes
require the unsanitized output. The `gnu-cxx.json` manifest records source
pins, compiler and archiver paths/hashes/versions, the GNU sysroot and Clang
resource path, input tree keys, exact build/consumer/per-file flags and
instrumentation. Its artifact map covers every adapted header plus exactly
six files: `apple-gnu-abi.h`, `gnu-cxx-abi-probe.cpp`,
`gnu-cxx-sanitizer-control.cpp`, `libcxx-ios.a`, `libc++abi.a` and
`libunwind.a`. The driver rejects missing, extra or altered headers/artifacts,
symlink/special entries within that set, and a mismatched sanitizer profile.
It pins the manifest and complete selected artifact set before and after the
capture. The producer's `sysroot_headers` and `resource_headers` maps also
cover every file in the GNU `sysroot/include` and Clang resource `include`
trees. The consumer requires both complete inventories, validates them before
execution and checks them again afterward. These are pins of the consumed
header trees, not a complete compiler or dynamic-library dependency closure.
Keep the recorded compiler, sysroot and resource paths valid for fixture builds.

The ABI uses the alternate 24-byte string layout, 128-byte/8-aligned Apple
`mbstate_t` with glibc's native 8-byte prefix, native 16-byte `fpos_t`, 32-bit
ctype masks and 64-bit thread keys. The generated conversion probe is a
binding adapter compiled only into the C++ fixture. It returns observations;
the V fixture checks the complete result vector, conversion and wide-stream
values, native file positioning, surrounding canaries and the untouched
120-byte state tail. It is not linked into application runners. Existing
resolver, public function and thread-lifecycle assertions remain in V.

`--sanitizers` applies ASan and UBSan to libc++ and libc++abi, with one
explicit per-file exception: LLVM's `libc++abi/private_typeinfo.cpp` appends
`-fno-sanitize=vptr` because instrumenting the RTTI implementation used by
the vptr checker recursively calls that checker. ASan and the other UBSan
checks remain enabled in that file; other translation units and fixture
callers retain full `-fsanitize=address,undefined` flags. The exact per-file
flags enter the build stamp and manifest. The low-level ELF unwinder remains
uninstrumented and retains unwind tables. This is the existing libc++ source
subset, without its filesystem subdirectory; **Mach-O exception unwinding
remains unsupported**.

Sanitized `cxx` and `cxx-gles` modes additionally require an explicit
`VINIX_IOS_LINUX_CXX_UBSAN_ARCHIVE` compatible with the selected ARM64
compiler output, including its vptr and function-type checks. The driver
hashes that archive and copies only it into
`OUT/payload/cxx-sanitizer/libubsan.a`; it does not add the external archive's
entire directory to the library search path. It records the selected input in
`cxx-sanitizer-input.json` and verifies both source and private copy again
before sealing. Linking uses `-static-libubsan` and excludes the adapted
C++ and static UBSan archive symbols from the dynamic-library namespace.
The `readelf` checks reject exported C++/exception/unwinder definitions and
direct `DT_NEEDED` dependencies on shared `libstdc++` or `libubsan`. Mesa's
own dependency closure remains separate. The reader must emit complete,
populated dynamic and symbol tables in the recorded C locale. Empty,
malformed or truncated output cannot qualify a binary, even if the selected
reader exits successfully.

```sh
export VINIX_IOS_LINUX_CXX_ROOT="$VINIX_CXX_STATE/asan"
export VINIX_IOS_LINUX_CXX_UBSAN_ARCHIVE=/path/to/compatible-arm64-gcc/libubsan.a
"$VINIX_CHECK_STATE/linux-checks" cxx "$VINIX_CHECK_STATE/cxx-r1"
export VINIX_IOS_LINUX_GLES_ROOT=/path/to/arm64-gnu-mesa-sdk
"$VINIX_CHECK_STATE/linux-checks" cxx-gles "$VINIX_CHECK_STATE/cxx-gles-r1"
export VINIX_IOS_LINUX_CXX_ROOT="$VINIX_CXX_STATE/runtime"
"$VINIX_CHECK_STATE/linux-checks" build-run-ios-cxx "$VINIX_CHECK_STATE/cxx-runner-r1"
"$VINIX_CHECK_STATE/linux-checks" build-run-ios-cxx-gles "$VINIX_CHECK_STATE/cxx-gles-runner-r1"
```

The `cxx` mode additionally executes the native ELF C++ fixture once using
the recorded consumer flags and adapted archives. The repository's
`tests/ios/cxx-extended.cpp` reference file remains unchanged. The maintained
V function `cxx_native_fixture_source` generates
`OUT/payload/cxx-native-fixture.cpp`, correcting exactly two constructor-helper
destinations: their already default-constructed strings become aligned raw
storage with one RAII destruction after successful `__init`. Cleanup also
runs when a later comparison returns early. LLVM 19's ASan container
annotations exposed the original invalid fixture setup. This adaptation
changes no production string code, performs no explicit unpoisoning and adds
no sanitizer suppression.

Every original `CHECK` comparison and the later fixture code remain intact.
The V unit check verifies their preservation and rejects changed or duplicate
replacement anchors. `cxx-native-source-inputs.json` records the original and
generated input hashes, and both sources stay in the capture.

The mode also compiles the generated sanitizer control with full caller checks.
The valid virtual/function calls must produce their marker and exit **37**;
separate invalid-vptr and wrong-function-type invocations must each exit
**1** with their specific UBSan diagnostic. The V driver enforces these
outcomes, including rejecting an unrelated ASan failure. These controls are
mandatory in `cxx`; `cxx-gles` still selects the GLES fixture. The V runtime
fixture runs in the ordinary/deterministic pair.
These checks do not establish unwinding from an actual Mach-O application.

## GNU/Linux GLES profile

`gles`, `cxx-gles`, `build-run-ios-gles`, `build-run-ios-cxx-gles` and
`probe-no-ads` require `VINIX_IOS_LINUX_GLES_ROOT`. Select a GNU/glibc ARM64
dependency tree with the Debian/Ubuntu multiarch layout:

| Relative path below that root | Required input |
| --- | --- |
| `usr/include/EGL`, `usr/include/GLES2`, `usr/include/GLES3`, `usr/include/KHR` | EGL and GLES headers |
| `usr/lib/aarch64-linux-gnu/libEGL.so` and `libEGL.so.1` | EGL link and runtime aliases |
| `usr/lib/aarch64-linux-gnu/libGLESv2.so` and `libGLESv2.so.2` | GLES link and runtime aliases |
| `usr/lib/aarch64-linux-gnu/libEGL_mesa.so.0` | Mesa GLVND provider |
| `usr/lib/aarch64-linux-gnu/libz.so.1` | zlib used by the existing GLES symbol bridge |
| `usr/lib/aarch64-linux-gnu/dri/swrast_dri.so` | Mesa software driver with softpipe and ES3 support |

The dependency closure of those libraries must also be present. The base
compiler/loader prefix supplies glibc and compiler runtime libraries. On an
ARM64 Debian/Ubuntu host with the required packages installed, the graphics
root may be `/`. Cross builds can use a private extracted ARM64 package tree;
host-architecture graphics libraries are rejected. Relevant package families
are `libegl-dev`, `libgles-dev`, `libegl-mesa0`, `libgl1-mesa-dri` and `zlib1g`,
plus their dependencies. Musl Mesa libraries do not satisfy this GNU profile.
Graphics roots and cross loader prefixes cannot contain `:` or `,`, which
are delimiters in the loader search path and QEMU environment arguments.

```sh
export VINIX_IOS_LINUX_GLES_ROOT=/path/to/arm64-gnu-mesa-sdk
"$VINIX_CHECK_STATE/linux-checks" gles "$VINIX_CHECK_STATE/gles-r1"
"$VINIX_CHECK_STATE/linux-checks" build-run-ios-gles "$VINIX_CHECK_STATE/gles-runner-r1"
```

The fixture uses surfaceless EGL and explicitly selects Mesa softpipe software
rendering. It requires an actual ES3 renderer and checks shader results,
framebuffer pixels, exported VSF1 XRGB pixels and vertical orientation. It
also covers pixel-pack/read-framebuffer restoration, resize and drawable
recreation, weak delegates, context replacement, per-thread current contexts,
last-reference TLS destruction and two complete runtime lifetimes. Requested
API2 contexts are checked with pbuffer pixels; ES2 GLKView publication is not
qualified by this fixture.

GLES capability queries now expose the implemented methods and their argument
types. Scalar/object `NSMethodSignature` queries are exercised. The CGRect
initializer is checked through raw method metadata and actual ARM64 HFA
dispatch; the existing restriction on aggregate `NSMethodSignature` and
`NSInvocation` values remains.

The driver clears inherited Mesa capability, shader and rasterization
overrides, emits a private GLVND vendor JSON, and keeps target library paths
out of host compiler processes. When QEMU is used, its explicit `-E` argument
sets the target loader path. `gles-environment.json` records the selected
settings. `gles-inputs.json` pins the selected headers, library entries and
software driver, including resolved aliases; these inputs are compared again
before the capture is accepted. Preserve the complete graphics SDK with the
capture. Packaged Mesa libraries themselves are not sanitizer-instrumented;
the runtime and V fixture are built with ASan/UBSan.

The `gles` output includes small PPM images in `payload/frames`, written from
the actual published surfaces. The `build-run-ios-gles` output includes
`run-ios`, its synthetic Mach-O and complete commands/receipts. A standalone
invocation of that runner needs the same recorded target library and GLVND
environment. C++ is enabled only in the combined C++ modes; video, SQLite
and text remain disabled in all these profiles.
The renderer provides no Metal device and this fixture establishes no
Fortnite frame or game launch gate.

## Linux HTTP system trust

The GNU/glibc runtime selects the first existing system CA bundle from these
paths, in order:

1. `/etc/ssl/cert.pem`
2. `/etc/ssl/certs/ca-certificates.crt`
3. `/etc/pki/tls/certs/ca-bundle.crt`
4. `/etc/ssl/ca-bundle.pem`
5. `/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem`

Only a missing path permits fallback. A broken symlink, unreadable or
non-regular target stops selection; parsing a malformed selected bundle also
fails. Environment variables cannot replace production trust. The existing
macOS and musl Vinix profiles retain `/etc/ssl/cert.pem`.

The Linux `data-http` fixture exercises public data/session TLS rejection
against a private loopback server and records the selected system bundle in
`OUT/payload/system-trust/bundle.pem`, with its original path and SHA-256 in
`source.txt`. `VINIX_IOS_HTTP_TRUST_EVIDENCE` is a fixture output destination,
set by the driver; it is not a trust-store override. Both runtime passes must
agree on the recorded system input. This is separate from the fixture's
generated loopback certificate/key and does not install trust or contact
game services.

## Guarded application probe

`probe-no-ads` requires the original full app directory and its actual main
executable, plus the unsanitized GNU C++ and GLES profiles. Supply both app
controls explicitly; the driver does not infer missing inputs:

```sh
export VINIX_IOS_APP_BUNDLE=/path/to/original/FortniteClient-IOS-Shipping.app
export VINIX_IOS_APP_EXECUTABLE=FortniteClient-IOS-Shipping
export VINIX_IOS_LINUX_CXX_ROOT="$VINIX_CXX_STATE/runtime"
export VINIX_IOS_LINUX_GLES_ROOT=/path/to/arm64-gnu-mesa-sdk
export VINIX_IOS_LINUX_PROBE_SECONDS=600
"$VINIX_CHECK_STATE/linux-checks" probe-no-ads "$VINIX_CHECK_STATE/game-probe-r1"
```

The executable must be a direct child of the supplied bundle, either as a
basename or an absolute path. It must be a supported, unencrypted ARM64
Mach-O executable. A regular, parseable `Info.plist` must name that same
`CFBundleExecutable`. These checks precede dependency builds and capture
creation. Bundled frameworks, resources and cooked content stay in their
original relative locations. The probe creates no dummy content or
`.uproject`, and does not copy or restage the game assets.
The capture destination is checked before directory creation and must be
outside the supplied app, including when an output-parent symlink points
into that app. Mach-O run-path strings are released exactly once during
input validation.

The input inventory streams SHA-256 over every regular file, including hidden
files, and records directories, modes and sizes. Descriptor-based traversal
rejects symlinks in the root, its ancestors or the tree, and rejects special
entries. The complete tree is compared before and after inspection, strict
import audit and launch. Missing imports remain diagnostic evidence and do
not suppress the explicit `--probe-no-ads` attempt; a failed inspection does.
Ads remain skipped. Preserve the original game input separately: an inventory
records identity but does not contain its assets.

The captured driver supplies a diagnostic VAPP v10 desktop peer so UIKit can
complete its protocol handshake. It records window trees and image-node
counts, then closes the session; it supplies no compositor or input device.
`VINIX_IOS_LINUX_PROBE_SECONDS` accepts 1..1800 seconds and defaults to 600.
That is the outer process-group limit for each inspect, audit and application
wrapper command. The peer's initial startup allowance derives from it, so a
slow initializer sequence is not cut off by the historical 30-second first
reply limit. Subsequent replies remain limited to 30 seconds and the diagnostic
session to 10 seconds, all within the outer application limit. The historical
peer default is unchanged for callers that do not set a startup allowance.
The guard retains its 16 MiB output cap and descendant cleanup. This GNU
path applies no guest memory cgroup and makes no 2 GiB memory-budget claim.

`OUT/application-probe` contains the before/after app inventories, runtime
profile and tool identities, inspect/audit receipts, wrapper commands/logs,
desktop task/observation and `probe-result.json`. The wrapper's exit receipt
is distinct from `application.status.txt`, which comes from the reaped app's
wait status. A wrapper failure cannot establish an app status. App failure
can be a complete diagnostic capture; guard or input-integrity failure
rejects the capture. Successful capture sealing writes **`COMPLETE`**, with
the observed app status, rather than a game `PASS`.

The profile includes C++ and GLES but still lacks video, text and SQLite
backends; Metal device creation returns nil. A synthetic entry or GLES test
image does not establish a Fortnite frame, menu, login or gameplay. Record
launch gates only from the actual supplied game's captured behavior.

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

Build and fixture child execution uses a process-group guard with a
600-second command limit; the entire nested TLS build is covered by its
worker's guard. Application probe commands use the explicit limit described
above. Failure, sanitizer and coverage diagnostics remain in the external
output.

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
