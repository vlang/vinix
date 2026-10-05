# iOS compatibility: Objective-C UIKit calculator

`run-ios` loads ordinary ARM64 iOS Mach-O executables in a Vinix userspace
process. The [Objective-C UIKit calculator](../examples/ios-calculator/README.md)
now runs unchanged in a desktop window. Its original ARM64 methods perform the
arithmetic and receive UIKit target/action messages. V implements the required
Objective-C, Foundation and UIKit subset; a small assembly trampoline preserves
integer, floating-point and structure arguments during message dispatch.

The UIKit view tree is rendered by Vinix's existing desktop compositor using
the standalone application protocol. The kernel loads the runner's static ELF
and needs no Mach-O or Darwin syscall changes. This supports this calculator's
API set; general iOS applications and Apple's own Calculator remain outside
the implemented subset. The existing native Vinix calculator is a separate app.

## Build and run

Build the AArch64 Alpine development sysroot with `./build-userland-aarch64.sh`
once, then:

```sh
./build-ios-aarch64.sh
./build-desktop-aarch64.sh
./run-desktop-aarch64.sh --no-build
# Open "iOS Calculator" from the desktop or Start menu.
```

The iOS builder produces the static runner, `vinix-ios-calculator` launcher,
`Calculator.app` and `Calculator.ipa` under `build/ios/`. The desktop builder
includes the runner and bundle when `build/ios/staging` exists; `VINIX_IOS_STAGING`
selects another staging directory. The launcher passes the installed Mach-O to
the runtime at `/usr/share/vinix/ios/Calculator.app/Calculator`.

`VINIX_IOS_BUILD_DIR`, `VINIX_AARCH64_SYSROOT`, `V` and `LLVM_BIN` select runner
build inputs/output. `IOS_CLANG`, `IOS_LD`, `IOS_SDK` and
`VINIX_IOS_CALCULATOR_BUILD_DIR` configure the app builder. An iOS SDK is optional:
the minimal declarations and linker import stubs contain no Apple implementation.
The tested build uses those declarations, Clang and `ld64.lld`.

`run-ios --inspect BINARY` reports metadata; `--imports` lists imports. The C
Mach-O probe still works with `run-ios /opt/ios/calculator 7 + 5` after staging it.
UIKit apps require the desktop's `VINIX_REQUEST_FD`/`VINIX_RESPONSE_FD` pipe pair;
executing a GUI app directly from a shell does not create a window. Set
`VINIX_IOS_TRACE=1` for UILabel update diagnostics.

## Supported ABI

| Area | Implemented |
| --- | --- |
| Images | Little-endian ARM64 `MH_EXECUTE`, `MH_PIE`, iOS/iOS Simulator platforms |
| Universal binaries | 32/64-bit slice tables, both byte orders; prefer ordinary ARM64 over ARM64e |
| Memory | Anonymous relocated image, zero-filled segment tails, segment permissions, sealed `SG_READ_ONLY` data, instruction cache flush |
| Entry point | `LC_MAIN`, `argc`/`argv`, empty null-terminated environment and Apple vectors, integer exit status |
| Dynamic linking | Chained pointer formats `DYLD_CHAINED_PTR_64` and `DYLD_CHAINED_PTR_64_OFFSET`, import formats 1/2/3, addends, weak unresolved symbols |
| libSystem | `_puts`, `_atoi`, `_malloc`, `_free`, `_strlen`, `_strcmp`, `_memcpy`, `_memset`, `_strtod`; Darwin ARM64 `snprintf("%.12g", double)` adapter |
| Objective-C | Class/metaclass registration, superclass dispatch, absolute/relative method lists, checked metadata, nonfragile ivar adjustment, native method execution, nil returns, allocation/new, retain/release/strong stores, autorelease pools and ARC destructors |
| Foundation | NSObject allocation/initialization; heap NSString objects created from UTF-8 |
| UIKit | UIApplicationMain/delegate launch, UIWindow, UIScreen, UIViewController, UIView, UILabel, UIButton target/action, opaque UIColor, UIFont size, CALayer corner radius |
| Desktop | VAPP v10 view/button/label serialization, resize and layout callbacks, button actions, ASCII calculator keyboard input, window close and object teardown |
| Inspection | Platform/version, dependencies, unsupported metadata and chained import names, including ARM64e images |

Header, command and segment ranges are checked before loading. Chained pointers
are checked against their file-backed segment and page before any memory is
rewritten. Every import is resolved before any chain is rewritten. Gaps
are inaccessible and no segment is writable and executable together. The
runner releases its mapping on return or link failure and exits after one app.

ARM64e/PAC, encrypted images, non-PIE binaries, image initializers/terminators,
Darwin TLS, custom stack sizes, legacy dyld opcodes and multiple chain starts
per page are rejected. Objective-C categories, +load/+initialize, exceptions,
weak references, blocks and Swift metadata are unsupported. Mach services,
direct Darwin syscalls, dynamic framework loading, Swift/SwiftUI, general
Foundation/UIKit APIs, scenes, nibs and bundle resource loading are not
implemented. View trees have bounded depth and at most 64 children per view;
the current action bridge handles controls in the root content view.

Unknown strong imports and unknown methods fail with a specific diagnostic.
General Darwin variadic calls such as `_printf` cannot be forwarded to musl.
Only the calculator's `snprintf` double format has a calling-convention adapter.
UIKit typography/fit-to-width is approximate and UIKit accessibility labels
are accepted but not exposed through a Vinix accessibility service.

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
v -enable-globals -cc clang -gc none -path "@vlib|$PWD/compat/ios|@vmodules" \
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
VMODULES="$PWD/compat/ios" v -enable-globals -cc clang test compat/ios
./tests/ios/run-objc-calculator.sh
python3 tests/ios/uikit.py # after building build/ios/run-ios-host above
python3 tests/ios/run.py
python3 tests/ios/desktop.py --desktop build/vinix-desktop
```

Host tests cover malformed file/command/section/segment/chain ranges, universal
byte orders, relocation, import addends, unsupported features and libSystem
semantics. The Vinix guest executes addition, subtraction, multiplication,
division and remainder, checks zero-filled data, exercises heap/string calls,
checks error/exit propagation, selects ARM64 from a universal executable, and
rejects missing imports, ARM64e and truncated images. Both the host protocol
client and Vinix guest exercise the unchanged UIKit Mach-O through all 27
calculator cases, resize, keyboard input, 1,000 update cycles and complete ARC
object teardown. ASan/UBSan checks the host runtime as well as the model.
The desktop test boots a minimal isolated image, clicks 7, +, 5, = through QEMU's
virtual pointer, checks the resulting UILabel update and saves
`build/ios/calculator.ppm`. It needs a desktop binary built with the new launcher.
The VM tests reuse the kernel and use disposable boot/package/persistent disks;
`run.py --no-build` reuses the runner, and `--timeout=SECONDS` sets the deadline.

The independently written parser follows Apple's public
[Mach-O load command definitions](https://github.com/apple-oss-distributions/xnu/blob/main/EXTERNAL_HEADERS/mach-o/loader.h)
and [dyld chained fixup definitions](https://github.com/apple-oss-distributions/dyld/blob/main/include/mach-o/fixup-chains.h).
No Apple implementation or proprietary app bytes are vendored.

The runtime follows the published [Objective-C metadata layout](https://github.com/apple-oss-distributions/objc4/blob/main/runtime/objc-runtime-new.h)
and [Apple ARM64 calling conventions](https://developer.apple.com/documentation/xcode/writing-arm64-code-for-apple-platforms).
Framework behavior here is independently implemented in V, without copying
Apple runtime or framework implementations.
