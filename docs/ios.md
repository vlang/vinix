# iOS compatibility: first executable milestone

`run-ios` is an experimental userspace compatibility runner written in V. It
loads ARM64 iOS Mach-O instructions into a normal Vinix process, binds a small
libSystem interface and calls the executable's `LC_MAIN` entry point. The
instructions run on the guest CPU. The kernel continues to load the runner's
ELF executable; it needs no new Mach-O execution mode.

This milestone runs the original calculator **probe** in `tests/ios/calculator.c`,
compiled for `arm64-apple-ios15.0`. It does **not** run Apple's Calculator, create
a UIKit window, or support general iOS applications. The existing native desktop
calculator is independent of this runtime.

An original [Objective-C UIKit Calculator](../examples/ios-calculator/README.md)
now provides a small GUI application for the next milestone. Its build produces
an ARM64 iOS `.app` and `.ipa`, with 25 chained imports across Foundation, UIKit,
libobjc and libSystem. It is inspectable here; launching it still requires the
Objective-C/framework compatibility layer and compositor bridge.

## Build and run

Build the AArch64 Alpine development sysroot with `./build-userland-aarch64.sh`
once, then:

```sh
./build-ios-aarch64.sh
./tests/ios/build-fixture.sh
python3 tests/ios/run.py
```

The runner is `build/ios/staging/usr/bin/run-ios`. The fixture is a real,
dynamically linked iOS Mach-O executable at `build/ios/fixtures/calculator`.
The fixture's `.tbd` file describes import names only; it contains no Apple
library implementation. Its arithmetic runs in that executable, while V's
libSystem adapter implements string/integer calls and uses the host libc for
heap allocation, output and compatible memory calls.

To try it in an ordinary Vinix VM:

```sh
mkdir -p build/ios/staging/opt/ios
cp build/ios/fixtures/calculator build/ios/staging/opt/ios/
VINIX_QEMU_OVERLAY="$PWD/build/ios/staging" ./run-aarch64.sh --no-build --serial
```

In the guest:

```sh
run-ios --inspect /opt/ios/calculator
run-ios /opt/ios/calculator 7 + 5
# IOS-CALCULATOR: 12
run-ios /opt/ios/calculator 2147483647 '*' 2147483647
# IOS-CALCULATOR: 4611686014132420609
```

The staging overlay is for that boot. The runtime is not yet in the default
image or package catalog. `VINIX_IOS_BUILD_DIR`, `VINIX_AARCH64_SYSROOT`, `V`
and `LLVM_BIN` select the build inputs/output; `IOS_CLANG` and `IOS_LD` select
the fixture compiler and Mach-O linker (`clang` and `ld64.lld` by default).
The fixture needs no iOS SDK. The VM test reuses the existing ARM64 kernel and
creates disposable boot, package and persistent disks. `--no-build` reuses the
runner; `--timeout=SECONDS` controls the VM deadline.

## Supported ABI

| Area | Implemented |
| --- | --- |
| Images | Little-endian ARM64 `MH_EXECUTE`, `MH_PIE`, iOS/iOS Simulator platforms |
| Universal binaries | 32/64-bit slice tables, both byte orders; prefer ordinary ARM64 over ARM64e |
| Memory | Anonymous relocated image, zero-filled segment tails, segment permissions, sealed `SG_READ_ONLY` data, instruction cache flush |
| Entry point | `LC_MAIN`, `argc`/`argv`, empty null-terminated environment and Apple vectors, integer exit status |
| Dynamic linking | Chained pointer formats `DYLD_CHAINED_PTR_64` and `DYLD_CHAINED_PTR_64_OFFSET`, import formats 1/2/3, addends, weak unresolved symbols |
| libSystem | `_puts`, `_atoi`, `_malloc`, `_free`, `_strlen`, `_strcmp`, `_memcpy`, `_memset` |
| Inspection | Platform/version, dependencies, unsupported metadata and chained import names, including ARM64e images |

Header, command and segment ranges are checked before loading. Chained pointers
are checked against their file-backed segment and page before any memory is
rewritten. Every import is resolved before any chain is rewritten. Gaps
are inaccessible and no segment is writable and executable together. The
runner releases its mapping on return or link failure and exits after one app.

ARM64e/PAC, encrypted images, non-PIE binaries, image initializers/terminators,
Darwin TLS, custom stack sizes, legacy dyld opcodes and multiple chain starts
per page are rejected. Mach services, direct Darwin syscalls, dynamic framework
loading, Objective-C, Swift, Foundation, UIKit, SwiftUI, resources/bundles and
application lifecycle are not implemented. In particular, variadic functions
such as `_printf` cannot be forwarded to musl because their Apple ARM64 calling
convention differs. An unknown strong import fails with its library/symbol
name instead of binding a dummy function.

## Local Apple Calculator inspection

On 2026-10-05 this Mac has macOS 26.5 (25F71), command-line developer tools,
and no installed iOS Simulator runtime. The available application is:

```text
/System/Applications/Calculator.app/Contents/MacOS/Calculator
com.apple.calculator, version 12.0, build 225
CFBundleSupportedPlatforms: MacOSX
SHA-256: f11151e63f888232772e5e4319635fc847aea5419e5849d723a10281e69e5c42
```

Its universal slices are x86_64 and ARM64e. The ARM64e image targets macOS
26.5, uses chained fixups and has 2,059 chained imports. The largest dependency
groups are SwiftUI (955), Swift core (306), the private Calculate framework
(213), Foundation (184), and AppIntents (85). It also imports CalculateUI,
AppKit, SwiftData, libobjc's `_objc_msgSend`/`_objc_msgSendSuper2`, dispatch and
Swift concurrency. Matching the CPU architecture or implementing integer
arithmetic cannot satisfy those ABIs.

Reproduce the inspection with the V reader (no Apple binary is copied into
the repository):

```sh
mkdir -p build/ios
v -cc clang -gc none -path "@vlib|$PWD/compat/ios|@vmodules" \
  -o build/ios/run-ios-host compat/ios/runner
build/ios/run-ios-host --imports \
  /System/Applications/Calculator.app/Contents/MacOS/Calculator
```

To continue toward Apple's **iOS** Calculator, obtain its unencrypted ARM64
developer/simulator executable and resources, then inspect the actual import
set with `--imports`. That determines the required Objective-C/Swift runtime,
Foundation/Calculate API and UIKit or SwiftUI implementation. A Vinix UI bridge
must then render its views and deliver input through the compositor. The local
macOS app's import list is evidence about that app, not a substitute for the
missing iOS executable.

## Validation and format references

```sh
VMODULES="$PWD/compat/ios" v -cc clang test compat/ios
python3 tests/ios/run.py
```

Host tests cover malformed file/command/section/segment/chain ranges, universal
byte orders, relocation, import addends, unsupported features and libSystem
semantics. The Vinix guest executes addition, subtraction, multiplication,
division and remainder, checks zero-filled data, exercises heap/string calls,
checks error/exit propagation, selects ARM64 from a universal executable, and
rejects missing imports, ARM64e and truncated images.

The independently written parser follows Apple's public
[Mach-O load command definitions](https://github.com/apple-oss-distributions/xnu/blob/main/EXTERNAL_HEADERS/mach-o/loader.h)
and [dyld chained fixup definitions](https://github.com/apple-oss-distributions/dyld/blob/main/include/mach-o/fixup-chains.h).
No Apple implementation or proprietary app bytes are vendored.
