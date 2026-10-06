# iOS compatibility: Objective-C UIKit applications

`run-ios` loads ordinary ARM64 iOS Mach-O executables in a Vinix userspace
process. The [Objective-C UIKit calculator](../examples/ios-calculator/README.md)
now runs unchanged in a desktop window. Its original ARM64 methods perform the
arithmetic and receive UIKit target/action messages. V implements the required
Objective-C, Foundation and UIKit subset; a small assembly trampoline preserves
integer, floating-point and structure arguments during message dispatch.

[Austin Zheng's iOS-2048](../examples/ios-2048/README.md) also runs from a pinned
upstream build. Its original Objective-C sources compile without changes. The
runner loads its launch storyboard source, presents the game controller and
executes native swipe callbacks, tile merges, scoring and queued moves.

The UIKit view tree is rendered by Vinix's existing desktop compositor using
the standalone application protocol. The kernel loads the runner's ELF
and needs no Mach-O or Darwin syscall changes. This supports the implemented apps'
API set; general iOS applications and Apple's own Calculator remain outside
the implemented subset. The existing native Vinix calculator is a separate app.

## Build and run

Build the AArch64 Alpine development sysroot with `./scripts/build-userland-aarch64.sh`
once, then:

```sh
./scripts/build-ios-aarch64.sh
./scripts/build-desktop-aarch64.sh
./scripts/run-desktop-aarch64.sh --no-build
# Open "iOS Calculator" from the desktop or Start menu.
```

The iOS builder produces the static runner, `vinix-ios-calculator` launcher,
`Calculator.app` and `Calculator.ipa` under `build/ios/`. The desktop builder
includes the runner and bundle when `build/ios/staging` exists; `VINIX_IOS_STAGING`
selects another staging directory. The launcher passes the installed Mach-O to
the runtime at `/usr/share/vinix/ios/Calculator.app/Calculator`.

Use `./scripts/build-ios-aarch64.sh --with-2048` to download, build and stage iOS-2048
as well. Open **iOS 2048**, then **Play Game**. Drag to swipe, or use arrow keys
or WASD. The `vinix-ios-2048` launcher loads
`/usr/share/vinix/ios/NumberTileGame.app/NumberTileGame`. Its bundle and IPA are
under `build/ios/2048`; the app's guide records the source revision and license.

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
| Dynamic linking | Chained pointer formats `DYLD_CHAINED_PTR_64` and `DYLD_CHAINED_PTR_64_OFFSET`, import formats 1/2/3; legacy rebase/bind/lazy/weak streams, export-trie lookup, signed addends and tagged RTTI pointers; checked lazy function slots resolve on first call through register-preserving ARM64 thunks; built-in library `dlopen`/`dlsym`/`dlerror` |
| Image lifecycle | Superclass-first Objective-C `+load`, category attachment and category `+load` before C++ image constructors; checked `LC_ROUTINES_64`, initializer pointers/offsets, terminators and reverse-order `__cxa_atexit`/`__cxa_finalize` callbacks |
| Thread-local storage | Darwin TLV descriptors, initialized and zero-filled templates, lazy per-thread allocation and pthread-key cleanup; register-preserving ARM64 thunk |
| C++ (optional) | `--with-cxx` builds LLVM libc++ with Apple ARM64 string, 128-byte `mbstate_t`, 32-bit ctype masks and eight-byte TLS keys; native strings, streams, regex, shared ownership, mutexes, recursive mutexes, condition waits and concurrent once callbacks tested in Vinix |
| libSystem | Memory/string/conversion/math subset; Darwin 152-byte `FILE` objects over native libc streams; ARM64 printf/scanf/asprintf and `va_list` adapters; checked formatting/copies; CPU/page-size queries, clocks, calendar time, locale categories, stack guards and ASCII rune tables; translated open/mmap flags, shared-memory aliases and 144-byte stat records; pthread and `dispatch_once` adapters |
| Objective-C | Class/metaclass registration, superclass dispatch, checked absolute/relative method lists, nonfragile ivar adjustment, native methods, reentrant once-per-class `+initialize`, nil returns, allocation/new/class, ARC ownership, native `dealloc` and Objective-C++ ivar constructors/destructors, zeroing weak references and copied block properties |
| Foundation | UTF-8 and UTF-16 constant NSString, UTF-16 length, concatenation, integer/object formatting; NSNumber, NSData, file-reading NSFileHandle, main NSBundle, document paths, immutable binary/XML property lists; collections, fast enumeration, timers, synchronous notification observers, operation queue configuration and file-backed standard user defaults |
| UIKit | UIApplicationMain with its principal class/application/delegate objects, single manifest window-scene connection, UIWindow, UIScreen, UIViewController presentation, nested UIView ownership/removal, UILabel, UIButton target/action, opaque UIColor, UIFont size, CALayer corner radius, single-touch swipe recognizers and simple alerts |
| Resources | Binary/XML Info.plist and bounded source storyboard subset (view/button/label, frame, color and actions), initial controller loading |
| Desktop | VAPP v10 nested view/button/label serialization, resize/layout, unique control actions, keyboard/swipe input, timer polling, window close and object teardown |
| Inspection | Platform/version, dependencies, unsupported metadata, chained and legacy symbol-table import names, including ARM64e images |

Header, command and segment ranges are checked before loading. Chained pointers
are checked against their file-backed segment and page before any memory is
rewritten. Chained and data imports are resolved before relocation. Legacy lazy
function imports must occupy `S_LAZY_SYMBOL_POINTERS`, with no addend; missing
weak imports remain null. Only those function slots may defer resolution. Gaps
are inaccessible and no segment is writable and executable together. The
runner releases its mapping on return or link failure and exits after one app.

ARM64e/PAC, encrypted images, non-PIE binaries, custom stack sizes, threaded dyld
binding opcodes, TLS pointer/initializer sections and multiple chain starts
per page are rejected. Objective-C exceptions and Swift metadata are unsupported.
Blocks support object/block captures, but not
`__block` by-reference captures. The runtime and weak tables are single-threaded.
Mach services,
direct Darwin syscalls, dynamic framework loading, Swift/SwiftUI, general
Foundation/UIKit APIs, multiple scenes, compiled nibs/storyboards and Auto Layout are not
implemented. View trees have bounded depth and at most 64 children per view.
UIView animations execute their blocks/completions synchronously; only their
final states are drawn, without sliding/pop interpolation or layer transforms.

Unknown strong imports and unknown methods fail with a specific diagnostic.
Darwin varargs are converted explicitly to the host ABI; `long double` formats
remain unsupported. Dynamic loading exposes built-in compatibility libraries;
external Mach-O dylibs are not loaded. Non-default thread attributes and some
Darwin flags/errno values still require translation. Property lists support
strings, signed integers, reals, booleans, arrays, dictionaries and data, with
size, nesting and object-count limits; dates, UID objects and mutable plist
options are unsupported. The scene bridge connects one window delegate from
`Info.plist`; foreground/background transitions and additional scene APIs remain
unfinished. Framework class descriptors and constants do not imply that their
graphics, audio, sensor or media methods are implemented.
Operation queues expose their name and concurrency settings; operation scheduling
is unsupported. CoreLocation implements the weak delegate property; location
services and authorization are unsupported.
User defaults use an atomically replaced per-bundle plist under
`Documents/Library/Preferences`; `VINIX_IOS_DOCUMENTS` selects the document root.
App groups, custom preference suites and security-scoped bookmarks are unsupported.
UIKit typography/fit-to-width is approximate and UIKit accessibility labels
are accepted but not exposed through a Vinix accessibility service.

## Native OpenGL ES and CoreText

`./scripts/build-ios-aarch64.sh --with-gles` additionally builds `run-ios-gles`.
It uses the ARM64 Mesa and FreeType libraries from `build-aarch64-x11/sysroot`
(build them with `./scripts/build-x11-aarch64.sh`), falling back to the userland
sysroot for dependencies. The dynamic runner uses a private musl interpreter,
software DRI driver and dependency closure in `/usr/lib/vinix/ios-gles`; the
existing desktop's graphics libraries and interpreter are preserved.

V implements `EAGLContext`, thread-local current-context ownership and `GLKView`.
The view allocates real Mesa RGBA8 framebuffers, depth/stencil attachments and
resizes its drawable. Native iOS drawing callbacks compile and run GLES shaders.
Readback preserves GL packing/framebuffer state, converts pixels to XRGB8888 and
publishes the desktop's existing VSF1 shared surfaces. A claimed compositor buffer
is never overwritten; resize and ordinary ARC teardown remove surface files.

`CADisplayLink` and queued main-thread blocks execute on the desktop event loop.
Scene activation/resignation and termination callbacks reach native app methods.
One desktop left pointer becomes a stable `UITouch` through began/moved/ended
callbacks, with `NSSet` enumeration, `UIEvent.allTouches`, timestamps and native
`CGPoint` returns. Existing calculator actions and 2048 swipes remain supported.

The CoreText subset registers bundled fonts, resolves PostScript and family
names, selects actual bold/italic faces, measures glyph advances/kerning and
rasterizes clipped premultiplied RGBA glyphs with FreeType. It uses independently
written V layout/compositing code and small C accessors for FreeType's structs.
UTF-8/ASCII strings, attributed strings, dictionary literals and the required
CoreFoundation ownership/collection calls are implemented. Complex text shaping,
font fallback, color emoji, general CoreGraphics drawing and multisampled GLK
drawables remain unsupported.

The optional runner also exposes tested native zlib entry points. An iOS fixture
checks its 112-byte stream layout and callbacks into original Mach-O allocator
functions. ARM64 native nonlocal jumps fit inside Darwin's opaque 192-byte buffer;
guarded iOS tests check both jump variants and the zero-to-one return convention.
Signal-mask restoration through jumps is not provided by the musl implementation.
Atomic reference counts, synchronized weak/block ownership and per-thread
autorelease pools allow Foundation work on native app threads. Tests race eight
threads against weak loads/deallocation and verify thread-exit pool cleanup.

```sh
python3 tests/ios/run.py --with-cxx --with-gles --with-2048
```

These tests execute original ARM64 iOS instructions inside Vinix, checking shader
pixels, 64 drawable resizes, depth/stencil state, EAGL thread cleanup, display-link
timing/pause, nested main-queue blocks, native touch callbacks, shared-buffer
ownership, real font pixels and zlib. Mesa's disk shader cache is disabled by
default unless explicitly configured. No Apple framework or font implementation
is copied into the runner.

## Official PPSSPP iOS binary

[PPSSPP](https://www.ppsspp.org/download/) is a substantial open-source PSP
emulator with a publicly downloadable iOS IPA. The pinned
[official 1.20.4 release](https://github.com/hrydgard/ppsspp/releases/tag/v1.20.4)
requires no App Store authentication. Its executable and resources are downloaded
into the ignored build directory, without modifying or vendoring app code:

```sh
python3 examples/ios-ppsspp/download.py
v -enable-globals -cc clang -gc none \
  -cflags '-fsanitize=address,undefined' -ldflags '-fsanitize=address,undefined' \
  -path "@vlib|$PWD/compat/ios|@vmodules" \
  -o build/ios/run-ios-ppsspp-host compat/ios/runner
build/ios/run-ios-ppsspp-host --imports \
  build/ios/ppsspp/unpacked/Payload/PPSSPP.app/PPSSPP

# Inspect and attempt the identical executable in a real Vinix ARM64 guest:
./scripts/build-ios-aarch64.sh --with-cxx
python3 tests/ios/run.py --no-build --with-cxx --with-ppsspp
```

The downloader verifies the release's 31,124,277-byte IPA against the publisher's
SHA-256, checks extraction paths and verifies the unpacked executable:

```text
IPA:        822c7042311ff47710c9148c8edb5aab649cf85ce6ba96b9e8190feb91f45a51
Executable: 7c9456c3cdee44dc48eefde5454bffa7e0965a32aa32858a181a06fbffeacf6c
Bundle:     org.ppsspp.ppsspp, version 1.20.4, minimum iOS 11.0
```

The 2026-10-06 probe found an unencrypted ordinary ARM64 Mach-O, 27 dependencies
and 767 imports. The import names match LLVM's independent symbol-table listing.
The largest groups are:

| Dependency | Imports |
| --- | ---: |
| libSystem | 304 |
| libc++ | 187 |
| OpenGL ES | 99 |
| UIKit | 29 |
| Objective-C runtime | 26 |

**The unchanged PPSSPP release binary renders its main menu and responds to
Settings clicks on Vinix, with sound disabled.** With the optional runtime, it runs
`SceneDelegate +load`, its native C++ constructors and `main`, reads its actual
entitlement data, reaches `UIApplicationMain`, registers notification observers,
and enters the scene delegate declared in its binary `Info.plist`. Its own code
then starts the worker/UPnP threads, registers its VFS asset/document paths,
reads configuration files, constructs its native view controller, and enters
`viewDidLoad`, including camera/location/motion helper setup. It creates a real
Mesa OpenGL ES context, enters its native emulation/rendering thread, registers
all five bundled fonts and decodes its assets through native zlib. Its original
code draws the splash screen, main menu and Graphics settings into a 390×680
framebuffer. Mouse clicks reach its original UIKit touch handlers.
Darwin private JIT probes fail normally; no successful entitlement or ptrace
operation is fabricated.

Build and stage the desktop launcher, then open **iOS PPSSPP**:

```sh
./scripts/build-ios-aarch64.sh --with-ppsspp
./scripts/build-desktop-aarch64.sh
./scripts/run-desktop-aarch64.sh --no-build
```

The build option enables C++/GLES, downloads the verified release and stages the
whole bundle without rewriting its executable. The launcher initializes an
ordinary `ppsspp.ini` with `[Sound] Enable=False` only when no preferences exist.
Documents/preferences live under the active desktop user's
`.local/share/vinix/ppsspp/Documents`; `VINIX_IOS_DOCUMENTS` selects another path.
The desktop supplies the private Mesa library/driver paths and pointer events.

For apps with persistent native C++ workers, `VINIX_IOS_EXIT_ON_CLOSE=1` sends
scene resignation and termination notifications, unlinks shared surfaces and
ends the process when its window closes. This is the PPSSPP launcher's mode:
returning from `UIApplicationMain` would otherwise prematurely run its global
thread destructors. Normal calculator/2048 teardown continues to check ARC.

Reproduce the native menu/Settings test and capture its actual pixels:

```sh
python3 tests/ios/run.py --no-build --with-cxx --with-gles --with-2048 \
  --with-ppsspp --ppsspp-muted --timeout 300 > build/ios/ppsspp-guest.log 2>&1
python3 tests/ios/frame.py build/ios/ppsspp-guest.log build/ios/ppsspp-settings.png
```

The test uses the installed launcher with fresh preferences, runs beyond the
splash transition, clicks Settings through native UIKit, checks detailed changing
pixels and verifies exit status zero and shared-surface removal. It emits
`iOS PASS: upstream PPSSPP native framebuffer and process lifecycle (muted)`.

Audio is still unsupported. With sound enabled the actual binary stops at
`AVAudioSession setCategory:error:`; the unmuted probe checks that precise
failure. Without `--with-gles`, the static probe still checks the unsupported
`EAGLContext initWithAPI:` call. Both intentionally report
`iOS BLOCKED: upstream PPSSPP unsupported API reached at runtime`.

Binaries without chained fixups previously reported no imports. `--imports` reads
bounded `LC_SYMTAB`/`nlist_64` records, filters defined/debug/local/common symbols,
resolves library ordinals and preserves weak-reference flags.

The legacy loader now validates all **50,782 relocation writes** in this exact
PPSSPP binary, including lazy slots, weak coalescing, backwards address advances
and tagged RTTI names. Initializers, terminators and Darwin TLS also execute in
Vinix: a native iOS fixture checks initialized/zero-filled TLS across eight
threads and runs a registered destructor after returning from `main`.

The optional C++ build provides all 187 C++ symbols imported by PPSSPP. It uses
pinned, SHA-256-verified LLVM/Alpine sources and archives, without copying Apple
library implementations. The following regression executes native iOS C++
constructors, string growth/erase, streams, regex, shared ownership, eight-thread
mutex/condition synchronization and concurrent once callbacks. Additional native
Mach-O fixtures cover lazy unsupported imports, Darwin FILE/varargs/stat/mmap
layouts, superclass/category load order, reentrant class initialization,
Objective-C++ ivar lifetime, UTF-16 strings, notification removal/weak filtering,
weak GameController notification constants, scene connection, and preferences
across separate process executions. XML plist tests preserve whitespace and
mixed text/CDATA order:

```sh
python3 tests/ios/run.py --with-cxx --with-2048 --with-ppsspp
# Independently validate PPSSPP's actual linker streams without executing it:
VINIX_IOS_PPSSPP_BINARY="$PWD/build/ios/ppsspp/unpacked/Payload/PPSSPP.app/PPSSPP" \
  v -enable-globals -gc none test compat/ios/macho
VINIX_IOS_PPSSPP_PLIST="$PWD/build/ios/ppsspp/unpacked/Payload/PPSSPP.app/Info.plist" \
  v -cc clang -gc none test compat/ios/plist
```

`./scripts/build-ios-aarch64.sh --with-cxx` enables this library in the runner.
The C++ fixture uses Apple's public C++ headers from `IOS_SDK` or the available
command-line-tools SDK, compiles for **arm64-apple-ios15.0**, and links only the
repository's import stubs. The library is rebuilt for Vinix with musl. C++
exception unwinding through Mach-O frames remains unsupported; this is a tested
C++ subset, not a complete ABI. The stdio and scene fixtures also run under
ASan/UBSan on the ARM64 host.

PSP game emulation has not been verified. Remaining work includes audio/device
services, additional Foundation/Darwin APIs, keyboard and multiple-touch input,
and broader rendering coverage. Metal and the bundled MoltenVK dylib remain
unsupported; the tested backend is OpenGL. Unsupported calls still diagnose the
actual API reached rather than silently pretending to implement it.

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
# Upstream iOS-2048, including original model tests and real guest swipes:
./tests/ios/build-2048-model.sh # after building the app
build/ios/run-ios-host build/ios/2048/model-tests
python3 tests/ios/game2048.py
python3 tests/ios/run.py --with-2048
python3 tests/ios/desktop.py --app 2048 --desktop build/vinix-desktop
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
