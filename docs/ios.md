# iOS compatibility: Objective-C UIKit applications

PS1 games use the separate native [PlayStation emulator](ps1.md).

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

`run-ios --inspect BINARY` reports metadata; `--imports` lists imports.
`--audit` checks every import against the compiled runner, prints all missing
symbols and returns status 1 when strong imports are unresolved. It does not
map or execute application code, and does not establish runnable support. The C
Mach-O probe still works with `run-ios /opt/ios/calculator 7 + 5` after staging it.
UIKit apps require the desktop's `VINIX_REQUEST_FD`/`VINIX_RESPONSE_FD` pipe pair;
executing a GUI app directly from a shell does not create a window. Set
`VINIX_IOS_TRACE=1` for UILabel update diagnostics.

## Supported ABI

| Area | Implemented |
| --- | --- |
| Images | Little-endian ARM64 `MH_EXECUTE` with `MH_PIE` and app-bundled `MH_DYLIB`, iOS/iOS Simulator platforms |
| Universal binaries | 32/64-bit slice tables, both byte orders; prefer ordinary ARM64 over ARM64e |
| Memory | Anonymous relocated image, zero-filled segment tails, segment permissions, sealed `SG_READ_ONLY` data, instruction cache flush |
| Mach VM subset | Current-task `vm_allocate`, shared `vm_remap` aliases and whole-mapping `vm_deallocate`, backed by native shared storage; fixed mappings preserve occupied addresses |
| Mach semaphore subset | Current-task, process-private FIFO/LIFO `semaphore_create`, `semaphore_destroy`, `semaphore_signal` and `semaphore_wait`, with native blocking and owned send references |
| Mach thread policy subset | Calling-thread standard/fair scheduling reaches native libc; cache-affinity hints return the measured ARM64 `KERN_NOT_SUPPORTED`; remote and unrepresentable scheduling changes are rejected |
| Signal subset | Darwin 16-byte `sigaction` and `signal`, translated native numbers/masks, one-argument handlers, `SA_RESTART`/`SA_NODEFER`, and callback draining before image unload |
| Entry point | `LC_MAIN`, `argc`/`argv`, empty null-terminated environment and Apple vectors, integer exit status |
| Dynamic linking | Chained pointer formats `DYLD_CHAINED_PTR_64` and `DYLD_CHAINED_PTR_64_OFFSET`, import formats 1/2/3; legacy rebase/bind/lazy/weak streams, export-trie lookup, signed addends and tagged RTTI pointers; app-bundled dylibs with `@executable_path`, `@loader_path` and own/executable `@rpath` lookup, shared mappings for repeated dependencies; checked lazy function slots resolve on first call through register-preserving ARM64 thunks; built-in and already-linked library `dlopen`/`dlsym`/`dlerror`, indexed mapped-image enumeration with signed slides and image/section lookup; main executable path with a checked 32-bit buffer size |
| Image lifecycle | Bound-image add/remove notifications with synchronous, reentrant registration; superclass-first Objective-C `+load`, category attachment and category `+load` before C++ image constructors; checked `LC_ROUTINES_64`, initializer pointers/offsets, terminators and reverse-order image-scoped `atexit`/`__cxa_atexit`/`__cxa_finalize` callbacks; native `exit` and immediate `_exit`/`_Exit` process termination |
| Thread-local storage | Darwin TLV descriptors, independent initialized and zero-filled templates for each image, lazy per-thread allocation and pthread-key cleanup; register-preserving ARM64 thunk |
| Swift heap subset | Aligned allocation for native ARC classes and local/generic heap contexts; synchronized strong, batch, bridge and unknown ARC, x20 deallocating destructors, checked object/class and uninitialized deallocation; owners drain before metadata/thunk retirement |
| C++ (optional) | `--with-cxx` builds LLVM libc++ with Apple ARM64 string, 128-byte `mbstate_t`, 32-bit ctype masks and eight-byte TLS keys; native strings and legacy growth/substring helpers, integer sorts, streams, regex, futures, shared/weak ownership and synchronization; V adapters for Darwin random_device and variadic abort |
| libSystem | Memory/string/conversion/math subset, repeated 4/8/16-byte pattern fills and 32-bit wide characters; Darwin 152-byte `FILE` objects over native libc streams; ARM64 printf/scanf/asprintf and `va_list` adapters; checked formatting/copies; CPU/page-size queries, clocks, calendar time, locale categories, stack guards and C/UTF-8 Unicode rune tables; translated open/mmap flags, positional reads/writes, shared-memory aliases, 144-byte stat records and native `utime` timestamps; version-4 UUIDs from native entropy; IPv4/IPv6 TCP, UDP and Unix sockets with Darwin addresses, options, flags and errors; pthread, `dispatch_once`, main/global/serial dispatch queues, delayed work and synchronous callbacks |
| Objective-C | Class/metaclass registration, superclass dispatch, checked absolute/relative method lists and type encodings, canonical selectors, method/ivar reflection, inherited method replacement and saved IMPs, dynamic class/ivar creation and disposal, checked `object_setClass`, nonfragile ivar adjustment, native methods, reentrant once-per-class `+initialize`, nil returns, allocation/new/class, caller-supplied instance construction and destruction, ARC ownership including 52 register-specific entry points, native `dealloc` and Objective-C++ ivar constructors/destructors, zeroing weak references and copied block properties |
| Foundation | UTF-8 and UTF-16 constant NSString, UTF-16 length, concatenation, integer/object formatting; NSNumber, immutable NSValue byte/type, pointer, range and geometry boxes, NSURLResponse/NSHTTPURLResponse metadata, NSData, file-reading NSFileHandle, main NSBundle, document paths, absolute file URLs with UTF-8 percent encoding, immutable binary/XML property lists; NSSet/NSMutableSet membership and algebra, collections, fast enumeration, timers, synchronous notification observers, operation queue configuration and file-backed standard user defaults |
| CoreFoundation | Owned UTF-8/ASCII strings including embedded NUL, UTF-16 ranges and partial UTF-8/ASCII conversion, arrays/dictionaries with type or NULL callbacks, dictionary add-if-absent and raw null entries, exported immutable empty dictionary, mutable data with zero-filled growth, signed integer/floating numbers, distinct Boolean IDs, equality/hash and callback tables; default allocation and absolute time |
| UIKit | UIApplicationMain with its principal class/application/delegate objects, file launch options and scene URL contexts, single manifest window-scene connection, idle-timer state and native controller gesture/home-indicator preference callbacks, UIWindow, UIScreen, UIViewController presentation, nested UIView ownership/removal, UILabel, UIButton target/action, opaque UIColor, UIFont size, CALayer corner radius, single-touch swipe recognizers, UIAlertController/UIAlertAction and legacy simple alerts; accessibility labels/hints/values/identifiers, traits and absolute frames, UIAccessibilityElement with a weak container; scaled/nested per-thread image contexts, immutable UIImage snapshots, upright PNG/JPEG decode and representation |
| Bitmap graphics | Owned RGB/gray colors with full-precision components and equality, RGB/RGBA/BGRA storage, bitmap/image dimensions and data providers, premultiplied source-over fills, clear/clip, saved state and fill color space, axis-aligned translation/scale, nearest/bilinear image drawing; independent image storage and real PNG/JPEG codecs from the V installation's existing stb library |
| AudioToolbox PCM | Same-rate, same-channel Int16/Int32/Float32/Float64 conversion between packed little-endian interleaved and planar buffers; complex input callbacks, partial output/error recovery, EOF/reset and converter ownership |
| Offline AudioUnits | GenericOutput pull rendering and mono MultiChannelMixer, graph nodes/connections and native input callbacks, stream formats, mixer volume/enable, slice limits, initialize/start/stop/uninitialize and owned render buffers |
| Resources | Binary/XML Info.plist and bounded source storyboard subset (view/button/label, frame, color and actions), initial controller loading |
| Desktop | VAPP v10 nested view/button/label serialization, resize/layout, unique control actions, keyboard/swipe input, timer polling, window close and object teardown |
| Inspection | Platform/version, dependencies, unsupported metadata, chained and legacy symbol-table import names, including ARM64e images |

Header, command and segment ranges are checked before loading. Chained pointers
are checked against their file-backed segment and page before any memory is
rewritten. Chained and data imports are resolved before relocation. Legacy lazy
function imports must occupy `S_LAZY_SYMBOL_POINTERS`, with no addend; missing
weak imports remain null. Only those function slots may defer resolution. Gaps
are inaccessible and no segment is writable and executable together. The
runner releases all image mappings on return or link failure and exits after one app.
Dependencies initialize before their dependents; callbacks unwind in reverse
registration order. Linked libraries stay mapped until process teardown.
Dependency cycles, re-exports, resolver/TLS exports and loading new libraries
from a running app are unsupported. There are at most 64 images and 1 GiB of
total reserved image space.

ARM64e/PAC, encrypted images, non-PIE binaries, custom stack sizes, threaded dyld
binding opcodes, TLS pointer/initializer sections and multiple chain starts
per page are rejected. Objective-C exceptions and general Swift metadata are
unsupported; the String metadata and value witnesses described below are available.
Blocks support object/block captures, but not
`__block` by-reference captures. ARC and weak tables are synchronized; UIKit
view operations run on the main thread. Mach IPC services,
direct Darwin syscalls, Swift/SwiftUI, general
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
CoreFoundation rejects custom allocators/callbacks and string encodings beyond
UTF-8/ASCII. Collections are limited to 65,536 entries and strings/data to 16 MiB.
PCM converters support up to eight channels; compressed codecs, sample-rate
conversion and channel remapping return an unsupported-format error. Conversion
does not provide speaker output or microphone capture. The same native fixture
checks sample values, clipping/rounding, callback errors and buffer layouts
against the installed Mac AudioToolbox and Vinix; ASAN checks short buffers,
invalid/reentrant operations and repeated image teardown.
Offline graphs support 16 nodes, 16 input buses per mixer and slices up to
16,384 frames. Native callbacks run without the registry lock; rendering pins
their unit buffers until the callback returns. Graph connections reject cycles
and graph disposal frees its units. The Mac/native fixture checks default mixer
volume, summed samples, muted inputs, silence, callback errors, cross-thread
property queries and caller/unit-owned buffers. Stereo/spatial mixer layouts,
gain automation, hardware output (`RemoteIO`) and voice processing/capture
are unsupported; hardware component discovery returns no component. GenericOutput
start/stop controls an offline unit whose caller still drives rendering.
Colors copy their CGFloat components and retain their color space; UIKit owns
its cached CGColor. Equality preserves component precision and color-space
identity instead of comparing rounded pixels. Gray paints convert to RGB;
gray bitmap storage, custom ICC/pattern/indexed spaces, non-finite components
and blend modes beyond normal source-over remain unsupported.
User defaults use an atomically replaced per-bundle plist under
`Documents/Library/Preferences`; `VINIX_IOS_DOCUMENTS` selects the document root.
`CFPreferencesAppSynchronize` flushes that same store for the current application
or its bundle identifier and reports write failures. Other domains return false.
`CFPreferencesCopyAppValue` returns an owned immutable snapshot, with registered
defaults as a fallback; unsupported application domains fail explicitly.
`CFPreferencesSetAppValue` stages copied values or removes keys; synchronization
flushes these changes through the shared standard-defaults store.
App groups, custom preference suites and security-scoped bookmarks are unsupported.
`CFRunLoopGetMain` returns a borrowed main-loop handle shared with Foundation's
`mainRunLoop`, main-thread `currentRunLoop` and `getCFRunLoop`. Workers can retrieve
the main loop; background Foundation current loops remain unsupported.
`CFStringCompare` supports zero-option literal UTF-16 ordering of valid strings,
including embedded NULs and registered image constants. Other comparison options
fail explicitly.
`CFUUIDCreate` returns an owned, distinct CFUUID object with secure version-4
bytes, accepting the null or system-default allocator. `CFUUIDCreateFromString`
returns owned values using the measured native parser, including its permissive
separator and incomplete-input handling. UUIDs compare and hash by value.
`CFUUIDCreateFromUUIDBytes` copies a by-value sixteen-byte payload into an owned
CFUUID without changing any bits. `CFUUIDCreateString` returns owned uppercase
canonical text for live CFUUID values. `CFUUIDGetUUIDBytes` returns an independent
sixteen-byte value without changing ownership. Additional CFUUID constructors
and the CFUUID-specific type-ID accessor remain unimplemented.
`NSCalendarIdentifierISO8601` exposes a shared immutable NSString pointer cell
through Foundation and CoreFoundation, with the native value `iso8601`.
Objective-C NSCalendar construction and calendar arithmetic remain unsupported.
`NSInternalInconsistencyException` exposes its native exception-name NSString
cell through Foundation and CoreFoundation, including use as an NSError domain.
`NSInvalidArgumentException` exports its distinct NSString name through both
frameworks and shares the same sealed storage lifetime.
Exception throwing and unwinding remain unsupported.
`NSLocaleCountryCode` and `kCFLocaleCountryCode` share one immutable NSString
pointer cell through Foundation and CoreFoundation, with the native value
`kCFLocaleCountryCodeKey`. Both spellings work with the existing NSLocale
`objectForKey:` and `CFLocaleGetValue` country queries.
`NSLocaleCurrencyCode` and `kCFLocaleCurrencyCode` share a distinct immutable
NSString cell with the native value `currency` in the same sealed page.
`NSLocaleCurrencySymbol` and `kCFLocaleCurrencySymbol` share a third cell with
the native NSString value `kCFLocaleCurrencySymbolKey`.
Currency-value queries remain explicitly unsupported.
`NSURLCreationDateKey` and `kCFURLCreationDateKey` expose one immutable NSString
cell through Foundation and CoreFoundation, with the native value
`NSURLCreationDateKey`. `NSURLFileSizeKey` and `kCFURLFileSizeKey` share a
distinct cell in the same sealed page, with the native value `NSURLFileSizeKey`.
`NSURLIsExcludedFromBackupKey` and `kCFURLIsExcludedFromBackupKey` share a third
cell with the native NSString value `NSURLIsExcludedFromBackupKey`.
`NSURLIsRegularFileKey` and `kCFURLIsRegularFileKey` share a fourth cell with
the native NSString value `NSURLIsRegularFileKey`.
`NSURLVolumeAvailableCapacityForImportantUsageKey` and
`kCFURLVolumeAvailableCapacityForImportantUsageKey` share a fifth cell with
the native NSString value `NSURLVolumeAvailableCapacityForImportantUsageKey`.
`NSURLVolumeAvailableCapacityKey` and `kCFURLVolumeAvailableCapacityKey` share
a sixth cell with the native NSString value `NSURLVolumeAvailableCapacityKey`.
`NSURLVolumeTotalCapacityKey` and `kCFURLVolumeTotalCapacityKey` share a seventh
cell with the native NSString value `NSURLVolumeTotalCapacityKey`.
URL resource-date, file-size, file-type and volume-capacity lookup, and
backup-exclusion metadata reads and writes, remain unsupported.
`OBJC_EHTYPE_$_NSException` exposes shared exception type-info through
Foundation and CoreFoundation, with a vtable/name/Class record and an
NSException class descriptor inheriting NSObject. Direct catch matching
supports the default class hierarchy, foreign type rejection and pointer
adjustment. NSException methods, exception throwing and Mach-O unwinding
remain unsupported.
UIKit typography/fit-to-width is approximate and UIKit accessibility labels
are accepted but not exposed through a Vinix accessibility service.
The Mach VM adapter supports allocations up to 4 GiB in the current process,
page-aligned no-copy remaps with a zero mask and copy inheritance, and complete
mapping removal. Cross-task mappings, copy-on-write remaps, partial removal,
VM protection APIs and Mach inheritance across fork are unsupported. Each alias
owns a backing descriptor, so removing its source does not invalidate the alias.
Vinix windows have no iOS home indicator or competing system-edge swipe;
controller update requests still invoke the app's native preference methods.
Idle-timer requests retain application state; the desktop currently has no
automatic screen-blanking timer.

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
font fallback, color emoji, transformed CoreText bitmap drawing, general CoreGraphics paths and multisampled GLK
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
tests/ios/run --with-cxx --with-gles --with-2048
```

These tests execute original ARM64 iOS instructions inside Vinix, checking shader
pixels, 64 drawable resizes, depth/stencil state, EAGL thread cleanup, display-link
timing/pause, nested main-queue blocks, native touch callbacks, shared-buffer
ownership, real font pixels and zlib. Mesa's disk shader cache is disabled by
default unless explicitly configured. No Apple framework or font implementation
is copied into the runner.

## Fortnite iOS 42.30.1: unsupported

The local `com.epicgames.FortniteGame_42.30.1_und3fined(1).ipa` was inspected
and its unchanged executable probed in an isolated Vinix ARM64 guest on
2026-10-09. This IPA contains unencrypted ordinary ARM64 images, including
the bundled EOSSDK and MarketplaceKitWrapper frameworks. Encryption is not
the blocker for this particular package.

```text
Bundle:     com.epicgames.FortniteGame
Version:    42.30.1 (58813929.3.4), minimum iOS 17.0
Executable: Payload/FortniteClient-IOS-Shipping.app/FortniteClient-IOS-Shipping
SHA-256:    6aae5109d316864fb67bea6a92046c347edbb04dc2a104c6666713da989cd373
Imports:    2,239 (chained fixups)
```

Its Mach-O metadata and memory layout are accepted. A structural relocation
probe exposed 29 valid C++ RTTI pointers with a `high8` tag of `0x80` that the
runner previously rejected as reserved bits. The decoder now preserves pointer
tags for both `DYLD_CHAINED_PTR_64` and `DYLD_CHAINED_PTR_64_OFFSET`, while still
rejecting reserved bits, unmapped targets and addresses that overflow into the
tag. With a test resolver, all 7,349,289 fixups validate; that structural check
does not resolve Fortnite's actual dependencies or execute game code.

The installed Mac CoreFoundation, Objective-C, Catalyst UIKit and CoreGraphics libraries were used as
behavioral references for independent V implementations of string conversions,
collections, mutable data, numbers, Booleans, ownership, framework constants,
accessibility metadata and runtime reflection/replacement. Dynamic classes and
ivars, saved built-in IMP callbacks and register-specific ARC calls are tested
with the same fixtures against the Mac libraries and Vinix. Accessibility
containers are zeroing weak references. VoiceOver reports disabled because no
screen-reader service is attached; notifications have no receiver in that state.
Accessibility container coordinate conversion is explicitly unsupported.
The same fixtures run against Apple's libraries and as native iOS instructions
in Vinix; no Apple implementation is copied into the runner.

The V bitmap implementation now supplies the missing UIKit image-context and
PNG/JPEG representation calls. Its shared reference/native fixture checks BGRA
format, scale rounding, nested context restoration, per-thread isolation and
cleanup, saved state and clipping, snapshot independence, drawing and real
codec round trips. JPEG transparency composites onto white, matching the Mac
reference. PNG/JPEG coding uses the V installation's existing open-source stb
library; UIKit object ownership, pixel conversion and compositing are V code.
Non-upright image orientations and rotated/sheared bitmap drawing remain
unsupported. This bitmap work does not implement Metal rendering.

App-bundled Mach-O framework loading now finds both EOSSDK and
MarketplaceKitWrapper from this IPA. The same two-library fixture passes
against Apple's Mac loader and Vinix: chained/legacy binds, export rebasing,
dependency constructors, cross-image Objective-C inheritance, independent TLS
in eight threads, dynamic lookup and reverse destructor order. Missing strong
libraries and ARM64e dylibs fail before app entry. An AddressSanitizer fixture
also audits and executes the bundle twice in one host process.

Additional UIKit/Foundation constants now match the installed Mac libraries,
including scene/application notifications, error domains and keys, file and
cookie attributes and floating-point window levels. Foundation selector/string
conversion preserves canonical selectors, UTF-8 names and nil behavior.

V now implements packed little-endian PCM converters, GenericOutput pull
rendering and mono mixer graphs. The same AudioToolbox fixtures run against
the installed Mac libraries and native iOS instructions in Vinix, checking
real sample values, callback errors, start/stop, silence and buffer ownership.
Disassembly of EOSSDK identifies RemoteIO (`rioc`) output and optional voice
processing (`vpio`); those hardware components are still unavailable. The
implemented AudioToolbox entry points resolve 41 more strong imports across
the executable and EOSSDK, without claiming device audio support.

CoreGraphics RGB/gray color creation, precise components/equality and color-space
ownership now also match the installed Mac reference. UIKit caches owned CGColors
without rounding their components. Fill color spaces survive saved-state restore;
the native fixture verifies gray/RGB pixel output and color release lifetimes.
This resolves another 15 strong imports across the executable and EOSSDK.

Raw data providers and `CGImageCreate` now also run in V. A shared Mac/iOS
fixture checks 19 packed 8-bit RGB layouts, straight/premultiplied alpha,
decode arrays, partial final-row padding, and overlapping source/destination
buffers. Images and `CGDataProviderCopyData` retain the provider; its native
release callback runs once with the original info, bytes and length, including
callbacks that reenter the runtime. CFData-backed providers retain their data.
An ARM64 adapter handles Darwin's packed stack arguments for image creation.
EOSSDK's disassembled call uses a 32-by-32 straight-alpha BGRA image, one of
the verified layouts. ASAN and the full native ARM64 regression pass. Gray,
floating-point, packed 16-bit and other unimplemented image formats return nil.
The two new Fortnite image entry points resolve four strong imports.

CoreGraphics rectangle queries, standardization, inset/offset/integral,
union/intersection, equality, hit testing and typed geometry constants now
match the Mac reference in V. The shared native fixture exercises negative
dimensions, null/empty rectangles, half-open point containment, over-insetting,
fractional coordinates and HFA register arguments/results. ASAN and the full
ARM64 regression pass. This resolves 13 more strong imports across the game
and EOSSDK.

GameController's imported key-code constants now have the measured 64-bit
values, and its keyboard/mouse notifications and haptic locality strings match
the installed Mac library. The same native fixture validates both platforms,
including constant object ownership under ASAN. This resolves 39 more strong
imports. Device discovery, controller profiles, keyboard/mouse device APIs and
haptics remain unimplemented; resolving their data constants does not provide
those services.

Security certificate parsing, copied DER/serial/subject data and RSA/EC public
key extraction now run in V. The Mac/iOS fixture checks RSA PKCS#1 and
P-256/P-384/P-521 X9.63 exports, key attributes/application labels, certificate
and key equality, retained outputs, trailing DER bytes, truncated input,
off-curve key rejection, owned decode errors, 46 typed string constants and
OS cryptographic random bytes. DER cursors and EC field arithmetic use bounded
stack storage. ASAN and the ARM64 C++/GLES/PPSSPP regression pass. Subject
summaries currently support UTF-8, PrintableString and IA5String; other string
encodings and public-key algorithms/curves remain unsupported. This resolves
43 strong imports and one weak import. General chain evaluation, signing/verification
and Apple's access-control service remain unimplemented; certificate
parsing alone does not authenticate a peer.

Fortnite's CommonCrypto imports now use V cryptographic primitives: one-shot
SHA-1/224/256/384/512, HMAC with those hashes, and AES-128/192/256 CBC/ECB through
`CCCrypt`. The shared Mac/iOS fixture checks independent digest/HMAC/OpenSSL
vectors, block/padding boundaries, long HMAC keys, zero IVs, in-place buffers,
required output sizes and the eleven-argument native ABI. Digest storage and
the boxed AES schedule are freed explicitly. ASAN and the full ARM64 regression
pass. Legacy unpadding follows the measured Mac final-length-byte behavior;
it does not authenticate ciphertext. Partial overlapping AES buffers, partial
padded ciphertext blocks, non-AES ciphers, MD5 HMAC and incremental cryptor
APIs remain unsupported. This resolves five more strong imports.

`SecItemAdd`, `SecItemCopyMatching`, `SecItemUpdate` and `SecItemDelete` now
implement EOSSDK's local generic-password queries in V. Service/account
identity, numeric type matching, binary data, duplicate/not-found errors,
copied data/attribute results and one/all queries are implemented. Updates
and deletes cover every match; a duplicate-producing update leaves the
stored records intact. The shared fixture compares CRUD and output ownership
with an isolated temporary Mac keychain; no existing user keychain is queried.
The Mac legacy keychain's default item reference and single-item mutations
differ from iOS, so shared comparisons use explicit accounts and return flags.

The store uses AES-256-CBC with a random IV and a separate HMAC-SHA-256 key;
the header, IV and ciphertext are authenticated before decryption, with strict
PKCS#7 validation. Files are replaced atomically under a stable `flock`, with
file/directory `fsync`. Owner-only directories (0700) and regular files (0600)
are required; symlink and hardlink files are rejected. A missing key, damaged
file or authentication failure returns an error without resetting records.
The key and store live under `Documents/Library/Keychains/<bundle-id>`;
`VINIX_IOS_KEYCHAIN` can select a private root for tests or deployment.
Fixtures exercise process restart, concurrent writers, tampering, wrong/missing
keys, unsafe modes, symlinks and an independent OpenSSL/Python encrypted vector.

This backend supports explicit `AfterFirstUnlock`/`AfterFirstUnlockThisDeviceOnly`
local items for the running user. The per-app namespace and Unix permissions
do not isolate apps sharing a uid, and the encryption key is a local 0600 file,
not a hardware-protected key. Vinix has no device lock-state service, secure
enclave, keychain synchronization, entitlement-backed access groups, interactive
authentication or persistent item references. Those policies, unsupported item
classes and the default `WhenUnlocked` policy return explicit errors. This
resolves eight strong imports across the game and EOSSDK without claiming Apple's
data-protection or trust services.

Security also constructs owned basic-X.509 and SSL policy objects in V.
Policy identifiers, optional hostname/client properties, retained metadata,
equality and hash consistency match the Mac reference. ASAN and the full
ARM64 C++/GLES/PPSSPP regression pass. Creating a policy does not evaluate a
certificate. This resolves one additional strong import in EOSSDK.

`SecTrustCreateWithCertificates` now owns immutable certificate and policy
snapshots, and both public-key getters return independently owned key bytes
without implying trust. The single-certificate count/index getters, copied
policies, anchor/date/policy setters and network-fetch preference are implemented
in V. `CFDateCreate`, its type ID, absolute-time getter and value equality support
the floating-point verify-date ABI. Mac comparison tests check the exported key
bytes: the deprecated Mac trust getter uses a different internal key class.

Trust evaluation has a deliberately bounded positive path: one self-issued CA
certificate, the basic X.509 policy, and an explicitly supplied DER-identical
anchor with custom-anchors-only enabled. Canonical UTC/GeneralizedTime dates,
public-key validity and matching inner/outer signature algorithm fields are
checked. The accepted extension profile is `basicConstraints` with `CA:true`
and no path length, plus optional noncritical subject/authority key identifiers;
every other extension and unique-ID field is rejected. The anchor's own
self-signature is not an issuer-chain proof, and the Mac reference also accepts
an explicitly trusted anchor with an altered self-signature.

An empty or mismatched explicit anchor set yields a real negative trust decision;
expired/not-yet-valid dates yield the measured Security date error. Setters
invalidate cached results. Legacy evaluation distinguishes API failure from a
negative trust result; the Boolean evaluator returns owned CFErrors and clears
the error output on success. System roots, chain building, SSL/hostname policies,
revocation and other profiles return `errSecUnimplemented` with an invalid trust
result. Multi-certificate count/index requests fail explicitly because no chain
has been built. This does not authenticate Fortnite's TLS peers or implement
general asymmetric signature verification. Shared Mac fixtures, malformed-profile
cases, ASAN ownership checks and the full ARM64 C++/GLES/PPSSPP regression pass.
This resolves eight additional strong imports across Fortnite and EOSSDK.

CFNetwork's three HTTP proxy constants now have the measured string values
`HTTPEnable`, `HTTPPort` and `HTTPProxy`. `CFNetworkCopySystemProxySettings`
returns an owned immutable snapshot of an explicitly inherited
`VINIX_IOS_HTTP_PROXY=http://host[:port]` configuration, with numeric enable/port
values and a copied host string. The default port is 80; a trailing slash is
accepted. DNS names and IPv4 host strings are supported. Missing/empty runtime
configuration returns NULL, as permitted for undefined proxy settings.
Malformed configuration, credentials, IPv6 literals and non-HTTP schemes fail
explicitly instead of silently selecting a direct connection. Vinix does not
yet have Apple's SystemConfiguration service, PAC, proxy authentication or
general CFNetwork networking. The Mac reference checks constant values and
dictionary field types without changing system settings or contacting servers;
Vinix fixtures check configuration changes, snapshot ownership, invalid input
and ASAN lifetime checks. The full ARM64 C++/GLES/PPSSPP regression passes.
This resolves five additional strong imports across Fortnite and EOSSDK.

The C++ resolver now exposes the real implementations of all 36 previously
missing C++ names in this IPA, resolving 38 strong imports across the executable
and EOSSDK. They already existed in the built libc++/libc++abi archives but
were excluded by the PPSSPP-only symbol list. Shared Mac/iOS fixtures verify
legacy string constructors, embedded-NUL comparison, growth with aliased input,
three integer sort widths, stream layouts, futures, weak ownership and demangling.
The V random_device adapter matches the Mac's four-byte, stateless object,
accepts arbitrary tokens and uses native OS entropy. A two-instruction assembly
entry passes Darwin variadic stack arguments to V's existing stdio bridge for
libc++'s formatted diagnostic followed by SIGABRT. Mac reference, ASAN ownership
and the full ARM64 C++/GLES/PPSSPP regression pass. A separate native ELF fixture
checks the real vector helper exception types/messages; exception unwinding
through Mach-O frames remains unsupported.

`CCRandomGenerateBytes` now fills caller-owned buffers directly from native
OS entropy in V, including requests larger than getentropy's 256-byte limit.
Zero-length calls succeed, null nonempty buffers return kCCParamError and
native entropy failures return kCCRNGFailure. Shared Mac/iOS fixtures check
chunk boundaries, independent output and buffer guards; ASAN and the full
ARM64 regression pass. This resolves two more strong imports.

`OSAtomicEnqueue`/`OSAtomicDequeue` now implement Darwin's lock-free LIFO queue
in V using baseline ARMv8 exclusive pair operations. The 16-byte head's pointer
and generation change atomically, preventing ABA when nodes are reused. The
Mac reference confirms generation updates, preserved node links and distinct
link offsets. Eight-thread fixtures exercise 65,536 head changes and verify
that every permanent node has exactly one owner at completion. Node storage
remains caller-owned and must stay mapped until concurrent dequeues return,
as required on Darwin. ASAN and the full ARM64 C++/GLES/PPSSPP regression pass.
This resolves four more strong imports across the game and EOSSDK.

`__assert_rtn` now emits the native assertion diagnostic, with or without a
function name, then terminates with SIGABRT. `__chkstk_darwin` uses an ARM64
adapter for the compiler's private x9 size argument, probes each 4 KiB page
and the allocation boundary, and preserves live integer/FP arguments and SP.
The installed Mac library and compiler establish the ABI; shared fixtures
exercise fatal assertions, 32 KiB frames and eight threads. ASAN tests also
verify a real inaccessible guard page faults, and the full ARM64
C++/GLES/PPSSPP regression passes. These helpers resolve five strong imports
across the three bundled images.

`__darwin_check_fd_set_overflow` now reproduces the installed Mac library's
negative-descriptor, unlimited-select and stack-containment checks in V, using
native pthread stack bounds. Only complete 128-byte objects on the current
thread's stack have the strict 1024 limit; heap/global storage remains the
caller's responsibility. The fortified `memmove`, `strncpy` and `strcat` entries
also work in V, checking capacity before writing, including strncpy padding,
overlap, missing terminators and SIZE_MAX object sizes. Overflow now takes the
native ARM64 SIGTRAP path, including the existing checked memcpy/memset entries.
Shared Mac/iOS fixtures and ASAN check main/worker stacks, heap/global bitmaps,
buffer guards and seven fatal overflow cases. The full ARM64 regression passes;
these entries resolve eight more strong imports across Fortnite and EOSSDK.

`__maskrune` and `isspace` now use compact V tables of the installed Mac
library's observed classification values. C/POSIX and UTF-8 locales preserve
Darwin's class masks, hexadecimal digit values and encoded screen widths;
other encodings fail explicitly. The V observation tool records 35 C ranges
and 3,585 UTF-8 ranges, without copying native library code. Shared fixtures
compare full-domain fingerprints over all 1,114,112 code points, mask widths,
invalid values, locale changes and eight-thread calls. Native ASAN and the full
ARM64 C++/GLES/PPSSPP regression pass. This resolves three strong imports.

The socket adapters now translate Darwin address lengths/families, native errno,
message flags, socket options and timeout layouts in V. Calls use real native
IPv4/IPv6 TCP, UDP and Unix sockets. Shared Mac/iOS fixtures check exchanges,
truncated address/option buffers, receive timeouts, second-based linger, empty
datagrams, byte order and eight simultaneous clients with independent errno.
Unsupported Apple service/QoS options and `SO_NOSIGPIPE` fail explicitly.

The guest tests exposed a kernel bug: `MSG_PEEK` consumed Internet socket data.
Internet and Unix stream receives now preserve queued bytes during peeks and
support `MSG_WAITALL` across delayed writes, timeout and EOF. Combined peeks
wait for the requested prefix, preserve it on timeout, and wake when queued
byte counts change; waiting observes event generations to avoid missed wakeups.
Native Mac reference and ASAN tests and the full ARM64 C++/GLES/PPSSPP regression
pass. The isolated kernel builds for both ARM64 and x86_64.

`atexit` now shares the image's locked C++ destructor queue, with a typed
zero-argument callback. Cleanup runs before Mach-O mappings are released;
callbacks are never registered with the host libc's process-global queue.
`exit` drains the image queue before native process termination, while `_exit`
skips cleanup. Shared Mac/iOS fixtures check mixed reverse-order callbacks,
registration during cleanup, nested scoped finalization, repeat finalization,
eight registering threads and both real process exit statuses. ASAN checks
two loads/unloads of the same image without leaving stale callbacks. The full
ARM64 C++/GLES/PPSSPP regression passes.

`atof` and `atoll` now reproduce the installed Mac library's conversion errors
in V over the native parser. Invalid floating input preserves errno; decimal
subnormals report `ERANGE`, while exactly representable hexadecimal subnormals
preserve errno. The adapter preserves floating-point status and rounding mode.
Decimal integers saturate at the signed 64-bit limits, with `ERANGE` for overflow
and `EINVAL` when no digits were parsed. Shared fixtures check binary floating
results, boundary rounding, signed zero, exact decimal/hexadecimal subnormals,
integer limits, and eight-thread errno and ARM64 status preservation. Mac
reference, ASAN and the full ARM64 C++/GLES/PPSSPP regression pass.

`chmod` and `fchmod` now adapt Darwin's 16-bit mode arguments to native permission
changes, with shared native-to-Darwin error translation. Shared fixtures check
real permission and setuid/sticky bits, unchanged file types, an open descriptor
after unlink, missing/closed files, symlink-loop errors and eight concurrent
clients with independent errno. Mac reference, ASAN and the full ARM64
C++/GLES/PPSSPP regression pass.

Dispatch now schedules real function callbacks and copied blocks in V over
native pthread synchronization. Main queue work runs on the UI thread; global
queues have concurrent workers, while private queues and their serial target
chains preserve FIFO exclusion. `dispatch_queue_create_with_target$V2` retains
its target. Pending work and queue-valued block captures retain their queues;
context finalizers run on the target after the last reference is released.
Synchronous callbacks wait for preceding work and diagnose recursive serial
or main-thread deadlocks. Delayed work enters its queue when the deadline
arrives, preserving work already queued ahead of it. Monotonic and wall-clock
tokens, overflow and underflow follow the installed Mac library's observations
and the documented [dispatch clock encoding](https://github.com/swiftlang/swift-corelibs-libdispatch/blob/main/src/shims/time.h).
Vinix's existing Mach timebase remains 1/1.

The scheduler joins active workers and releases pending captures before C++
destructors, framework teardown or image unmapping. Shared Mac/iOS fixtures
check 128 mixed FIFO callbacks, actual concurrent overlap, sibling serial
targets, queue labels and copies, finalizers, release with pending work,
queue-valued capture helpers, timer ordering and a callback still running when
main returns. ASAN checks two image loads/unloads, deferred main queue turns,
wall deadlines and background synchronous calls to a main-targeted queue.
The full ARM64 C++/GLES/PPSSPP regression passes. This resolves 19 additional
strong imports across Fortnite and EOSSDK.

This is a dispatch subset: the worker pool currently has four threads without
adaptive overcommit or QoS scheduling. Private queues accept NULL attributes
only; concurrent/custom attributes, target mutation, groups, semaphores,
sources, dispatch data and `OS_dispatch_queue` Objective-C classes remain
unsupported. Function contexts remain application-owned, and application
threads must finish before their image is unloaded.

`fcntl` now adapts Darwin descriptor duplication, close-on-exec flags and file
status flags in V. A small ARM64 entry passes the variadic stack; getters do
not read a missing third argument. Duplicate descriptors share offsets and
append/nonblocking/sync status while keeping independent descriptor flags.
Invalid duplicate search floors report Darwin `EINVAL`; real exhaustion keeps
`EMFILE`. `fsync` calls the native filesystem flush with Darwin error conversion.
EOSSDK's disassembly confirms nonblocking/close-on-exec use and its fallback
from `F_FULLFSYNC` to `fsync`.

Shared Mac/iOS fixtures check flag changes through three aliases, real append
writes and shared offsets, native flushing, nonblocking socket receives,
negative/oversized duplicate floors and eight simultaneous clients. ASAN and
the full ARM64 C++/GLES/PPSSPP regression pass. Apple-specific controls,
record locks, SIGIO configuration and simultaneous independent Darwin sync
bits remain unsupported and fail explicitly. These entries resolve four
additional strong imports across Fortnite and EOSSDK.

`getaddrinfo`, `freeaddrinfo` and `getnameinfo` now adapt Darwin's address-list
layout, IPv6 family, resolver flags and positive error codes in V over the native
resolver. Returned socket addresses and canonical names are independent owned
copies; partial failures release the entire list. Numeric IPv4/IPv6, mapped
IPv4, passive and loopback addresses, named hosts and services use the guest's
actual resolver configuration. Default hints include address configuration and
mapped-address handling. Numeric conversion preserves errno, while `EAI_SYSTEM`
translates the native error. Name buffers follow the Mac's host-first overflow
behavior. Raw ICMP hints select their appropriate address family.

`getifaddrs`, `freeifaddrs` and `if_nametoindex` now return owned snapshots of the
native interfaces. V converts Linux packet addresses into Darwin link addresses,
including actual interface names, indices and hardware addresses, and translates
multicast flags and IPv4/IPv6 addresses, masks and destinations. Interface names
remain those supplied by Vinix. Linux link statistics are currently unexposed
(`ifa_data` is NULL); no Apple interface services or network configuration changes
are implemented. Unsupported address families and unknown resolver flags fail
explicitly. `getnameinfo` requires a complete IPv4 or IPv6 input buffer, even
though the installed Mac library accepts inconsistent length arguments.

Shared Mac/iOS fixtures check resolver errors, defaults and mapped addresses,
canonical-name ownership, numeric and named services, buffer overflow without
partial strings, real UDP communication, independent interface snapshots, link
layouts, masks and indices, and eight simultaneous clients. ASAN checks two
loads/unloads of each fixture. The isolated guest has explicit localhost and
domain-service files so these checks do not depend on an external DNS server.
The full ARM64 C++/GLES/PPSSPP regression passes. These six entries resolve 12
additional strong imports across Fortnite and EOSSDK. The concurrent permission
fixture uses a permanently invalid descriptor for its closed-file check because
another worker can reuse a recently closed number. Worker failures are reported
after all clients have been joined, preserving mapped code until the threads end.

`getdtablesize`, `getgid` and `getegid` expose actual native limits and group IDs.
V adapters for `gethostname`, `getpwuid`, `getprotobyname` and `getrusage` use
the native hostname, account database, protocol configuration and process
accounting. Hostname truncation follows the Mac's successful, terminated prefix
behavior. Zero-capacity calls leave the buffer untouched; the measured Mac
implementation instead writes just before the supplied buffer in that case.
Account records use Darwin's 72-byte layout and grow a native reentrant lookup
buffer as needed. Password-change, class and expiration metadata unavailable in
the Linux account record are zero/empty. Account and protocol results belong to
the calling thread and are reclaimed at thread exit or runtime shutdown.

On Linux, the V protocol adapter reads `/etc/protocols` because musl's built-in
protocol list omits aliases and ignores that file. Names, numbers and all aliases
come from the guest's configuration, including custom records. The Mac backend
copies its native records. Resource usage copies native fields into Darwin's
144-byte layout, including 32-bit microseconds and peak memory in bytes. This
also keeps musl's larger native structure out of the application's buffer.
Darwin's self/children selectors are supported; Linux's additional thread
selector fails with `EINVAL`. The IPv6 loopback constant is also available.

Shared Mac/iOS fixtures check hostname boundaries, real identities and limits,
missing records, independent account/protocol records across eight synchronized
threads, long account fields, resource-usage buffer guards and memory units.
ASAN checks two loads/unloads, account-buffer growth, protocol aliases, custom
numbers, long records, comments, malformed entries and missing files. The
isolated guest supplies real account/protocol files for these checks. The full
ARM64 C++/GLES/PPSSPP regression passes. These eight entries resolve 16 additional
strong imports across Fortnite and EOSSDK.

V adapters for `initgroups`, `getgroups`, `setgroups`, `setuid` and `setgid`
use the native group database and process credentials. Successful calls retain
the caller's errno; failures translate the native error immediately. `kill`
uses native process existence/permission checks and maps Darwin signal numbers
to Linux numbers. Darwin `SIGEMT` and `SIGINFO` have no Linux counterpart and
fail explicitly. Signal-handler registration remains the existing limited
subset. `malloc_size` reports the native allocator's usable capacity for NULL
or allocation base pointers from `malloc`, `calloc` and `realloc`. Allocation
rounding differs between the native allocators; arbitrary/interior pointers
and other allocation zones remain unsupported.

`ioctl` has a small ARM64 variadic entry and V adapters for close-on-exec,
nonblocking mode, queued byte counts and IPv4 interface queries for flags,
metric, address, broadcast address, netmask and MTU. These controls act on real
native descriptors and interfaces. The Linux backend keeps its 40-byte `ifreq`
inside a stack buffer and copies only the selected result into Darwin's
32-byte structure. It preserves unused bytes, converts multicast flags and
sockaddr headers, and follows the Mac's shortened netmask lengths and missing
interface errors. Other requests fail explicitly without reading a missing
variadic argument; terminal controls and interface mutation remain unsupported.

Shared Mac/iOS fixtures check actual credential failures, signal queries,
descriptor aliases, queued socket bytes, guarded interface buffers and eight
concurrent clients. The isolated guest checks group-database membership,
credential changes and real delivery of Darwin `SIGUSR1`, `SIGUSR2` and `SIGBUS`.
Allocator checks write every reported usable byte and verify reallocation
contents. ASAN checks two loads/unloads of both fixtures. Workers are joined
before reporting failures, including partial thread creation. The full ARM64
C++/GLES/PPSSPP regression passes. These eight entries resolve 13 additional
strong imports across Fortnite and its bundled frameworks.

V adapters for `mktime`, `tzset`, `tzname` and `clock` use native calendar
conversion, timezone configuration and process CPU accounting. Compile-time
checks verify the shared 56-byte calendar layout, 64-bit timestamp/clock values
and one-million-ticks-per-second clock units. Successful conversions preserve
errno, including the valid timestamp `-1` just before the epoch. Conversion
failures translate native errors; NULL input reports `EFAULT`. Linux reports
`EOVERFLOW` for normalization beyond the signed calendar-year range, while
the measured Mac returns `-1` without changing errno in that case.

The timezone-name array belongs to native libc and updates after `tzset`;
its names and rules come from the guest's `TZ` setting and timezone files.
The unused daylight name can differ between libc implementations. Exact Mac
normalization of ambiguous/nonexistent local times remains unverified.
Shared Mac/iOS fixtures check signed and post-2038 timestamps, leap days,
normalized fields, positive offsets, winter/summer DST rules, buffer guards,
advancing native CPU clocks and eight concurrent callers. They restore the
previous timezone before returning. ASAN checks two loads/unloads. The full
ARM64 C++/GLES/PPSSPP regression passes. These four entries resolve five
additional strong imports across Fortnite and EOSSDK.

`nan` and `nanf` construct Darwin quiet NaNs in V from unsigned decimal,
octal or hexadecimal payload tags. Integer overflow wraps, malformed tags
discard the entire payload, and the result keeps the representable payload
bits. Unlike musl's constructors, these preserve the measured Mac payloads.
They allocate nothing and leave errno, exception flags and rounding mode
unchanged. Shared Mac/iOS fixtures verify exact single/double bit patterns,
large tags, four floating-point states/rounding modes and eight concurrent
callers; ASAN also checks two image loads/unloads.

V adapters for `pipe` and `poll` use real native descriptors and readiness
waits. They translate Darwin normal/band filters, restrict pipe readiness
to the correct endpoint, preserve errno, and follow the Mac's EOF and
zero-filter behavior. Unix stream EOF conversion does not consume `SO_ERROR`.
Polling uses stack storage for up to 32 entries and frees larger translation
arrays on success and failure. The native Vinix limit is 4,096 descriptors;
Darwin vnode change notifications and unknown filters fail explicitly with
`EOPNOTSUPP`. Shared Mac/iOS fixtures check guarded layouts, real pipe/socket
data, both ends closing, negative/invalid descriptors, 65-entry arrays,
finite waits, negative timeouts waking on real I/O and eight concurrent
clients. ASAN checks two image loads/unloads. The full ARM64 C++/GLES/PPSSPP
regression passes. Urgent TCP data and connection error combinations remain
unverified. These four entries resolve five additional strong imports across
Fortnite and EOSSDK.

The actual executable, using the updated static C++ runner in a 4 GiB Vinix guest,
still exits with status 1 before its entry point, now at:

```text
iOS: linking /opt/ios/Frameworks/EOSSDK.framework/EOSSDK: iOS: library is not implemented: /usr/lib/libz.1.dylib (_inflate)
```

The existing C++/GLES/Text runner supplies native zlib and gets beyond that
dependency. With its private library closure included in the same 4 GiB guest,
the actual game gets beyond the legacy libc++ ABI dependency and still exits
before entry, at:

```text
iOS: linking /opt/ios/Frameworks/EOSSDK.framework/EOSSDK: iOS: libSystem symbol is not implemented: _utime
```

The installed Mac SDK defines `os_proc_available_memory` as an app's remaining dirty
memory budget, equivalent to `task_vm_info.limit_bytes_remaining`; it does not
return free system RAM or an address-space limit. The installed native entry
dispatches Darwin syscall 534 and returns zero for the probed Mac process,
before and after a touched 64 MiB allocation. A shared Mac/Vinix fixture also
checks errno preservation and eight concurrent callers.

The V `os_proc_available_memory` adapter now reads the calling process's
unified cgroup membership and its mounted hierarchy. It returns the smallest
remaining `memory.max - memory.current` across the group and visible parents,
saturating at zero. The queries are fresh, use bounded stack buffers and close
all native descriptors. Unlimited/unmanaged processes return zero, as the Mac
reference does. Invalid, truncated or unreadable snapshots, legacy/hybrid
hierarchies, ambiguous membership names, namespace-relative paths and
subtree-only mounts also return zero rather than an unverified budget.
Mountinfo octal escapes are decoded, and caller errno is preserved.

This is Vinix's native enforced group budget: its charge includes committed
anonymous memory and kernel allocations, and a shared group's other processes
also consume that budget. It is not an exact emulation of Darwin's per-task
`phys_footprint`; limits above a cgroup namespace's visible root cannot be
inspected. No finite app budget is invented from free system RAM or `RLIMIT_AS`.
The native guest fixture creates real nested groups under a mount point with a
space, verifies headroom loss after touching 8 MiB, recovery after unmapping,
live child/parent limit changes and unlimited budgets. ASAN covers bounded
hierarchy parsing and two Mach-O image loads/unloads with eight concurrent
callers. The full ARM64 C++/GLES/PPSSPP regression passes. This resolves two more
strong imports across Fortnite and EOSSDK.

The installed `libsystem_pthread.dylib` reference accepts null fork handlers
and preserves errno across eight-thread registration. A real fork verifies
reverse registration order for prepare callbacks and forward order for parent
and child callbacks. A separate native probe that attempted registration from
a prepare callback terminated before that registration returned.

The V `pthread_atfork` adapter keeps an image-owned callback list. A single
permanent native dispatcher invokes prepare callbacks in reverse order and
parent/child callbacks in forward order around real libc forks, including the
parent phase when a fork fails. A mutex pins the list throughout all phases
and serializes concurrent forks. Null handlers are accepted without allocating;
registration preserves errno and returns Darwin error numbers. Registration
from any active callback explicitly returns `EDEADLK` (11).

After image destructors run, teardown waits for active callbacks, removes every
handler and frees its storage before the Mach-O mappings unmap. Native libc
retains only dispatcher pointers into the runner, so a later native fork cannot
call an unloaded app. App callbacks share one native dispatcher group; their
relative registration order with callbacks added by native backend libraries
is not preserved. Broader Objective-C/UI execution in a multithreaded fork child
remains unverified.

V `fork` and `waitpid` adapters use actual native cloning and child events,
preserve successful-call errno and translate native failures. Wait flags and
exit, signal, stopped and continued status are translated to Darwin's ABI;
status output remains untouched for `WNOHANG` with no ready child. Shared Mac/iOS
fixtures check ordering, image TLS, eight-thread registration and forking,
guarded 32-bit wait status, signals, stop/continue events, null status and errors.
The guest also forces a real `EAGAIN` using its enforced PID quota and checks
parent callbacks and subsequent registration. ASAN/UBSAN checks two Mach-O
loads/unloads, a real fork after unmapping and teardown blocked on an active
prepare callback. The full ARM64 C++/GLES/PPSSPP regression passes. This resolves
two more strong imports across Fortnite and EOSSDK.

The installed ARM64 Mac pthread library's attribute object is 64 bytes. Its
defaults are a joinable thread, inherited scheduling, a 512 KiB stack and a
16 KiB guard. Stack-size and guard setters accept legacy 4 KiB multiples and
round them to 16 KiB pages; explicit user stacks require both address and size
to align to 16 KiB. A user stack is stored as its top plus its size, so changing
the size keeps the top fixed. Destroy clears only the signature. These layouts,
defaults, mutations, invalid states and errno behavior were measured against
the installed `libsystem_pthread.dylib`.

V adapters now implement attribute init/destroy and stack, size, guard and
detach getters/setters in the inline Darwin object, with no per-object
allocation or registry. Getters leave output untouched on invalid signatures.
`pthread_create` translates the fields into a stack-local native attribute
object and creates a real thread, including caller-provided stacks and detached
state. Null attributes also use the measured 512 KiB default. Successful
creation writes a native 64-bit handle; failures preserve its output and caller
errno. Non-default scheduling/QoS fields return `ENOTSUP` (45) explicitly.

The `pthread_join` adapter uses native joining, preserves errno and returns
Darwin `EDEADLK` for self-join. On Vinix it first reads a live thread's native
detach state and returns `EINVAL` for detached joins, matching the Mac; direct
musl joining faults on that unsupported operation. Callers must provide valid
thread handles. App threads must finish before the app returns from its entry
point; unloading an image with active detached threads remains unsupported.

Shared Mac/iOS fixtures check guarded 64-byte attributes and 32-bit getter
outputs, copying, size rounding, fixed-top resizing, destruction and errors.
Eight real threads touch 256 KiB stack frames, check image TLS and use both
allocated native stacks and caller-provided 1 MiB stacks, verifying their local
addresses. The detached fixture verifies joining rejection while its worker is
blocked, then exits the process without unloading a live image. ASAN/UBSAN
checks two image loads/unloads with joined workers and explicit rejection of
foreign scheduling fields; the fork lifetime tests also pass with the new
creation/join adapters. The full ARM64 C++/GLES/PPSSPP regression passes. This
resolves nine more strong imports across Fortnite and EOSSDK.

The installed Mac pthread library uses a 16-byte condition attribute object.
Init writes its signature and private sharing bits while preserving opaque
padding; getters/setters validate the signature, and repeated destroy clears
only the signature and succeeds. Private and shared values are 2 and 1. Native
condition initialization reads these bits even from a destroyed attribute.
V implements the four attribute operations with the measured layout and guarded
32-bit outputs, without allocating. Private condition initialization accepts
copied attributes and uses real native conditions. Shared initialization returns
Darwin `ENOTSUP` (45) before modifying the condition because the current registry
stores process-private native state. Condition operations preserve caller errno
and return 32-bit Darwin errors.

The shared Mac/iOS fixture checks copying, opaque bytes, invalid and destroyed
attributes, timed waits and eight rounds of eight real workers using signals and
broadcasts. ASAN/UBSAN checks two image loads/unloads with all workers joined and
conditions destroyed. The full ARM64 C++/GLES/PPSSPP regression passes. This
resolves two more strong imports in EOSSDK.

The installed Mac pthread library compares native handles, accepts null/null
equality and preserves errno. `pthread_main_np` identifies the process's original
main thread, including returning false in a child forked by a worker. V now
exposes native handle comparison and captures the runner's process thread at
initialization on Vinix; loading an image from a worker does not change that
identity. On Mac the adapter calls native `pthread_main_np` directly.
The `pthread_exit` adapter uses actual native thread exit, so joining observes
the supplied return value after libc has run key destructors.

The shared Mac/iOS fixture runs eight rounds of eight real workers with isolated
image TLS, distinct handles, mixed return/explicit exit, null and non-null join
values, guarded outputs and three rearmed key-destructor passes. It also forks
from a worker and checks the child's main-thread identity. ASAN/UBSAN checks
two image loads/unloads on the process thread and another on a native worker,
with all app workers joined and keys/conditions destroyed before unmapping.
TLS reads from arbitrary native pthread-key destructors remain unverified;
C++ thread-local destructor ordering is checked by the TLV fixture below.
The full ARM64 C++/GLES/PPSSPP regression passes; an earlier attempt
failed the existing concurrent permission fixture with `ENOENT` and its log is
preserved. This resolves five more strong imports across Fortnite and EOSSDK.

The installed Mac pthread library's scheduling parameter is eight bytes, with
default priority 31 and opaque word 10. Getters permit either or both outputs to
be null, copy the complete parameter, preserve errno and report `ESRCH` (3) for
a null thread handle. The priority range calls return 15 and 47 regardless of
the supplied policy, including unknown values. These behaviors and copied setter
inputs were measured against `libsystem_pthread.dylib`.

V now translates Darwin ordinary/FIFO/RR policies to native thread scheduling,
preserves errno and writes guarded 32-bit policy and eight-byte parameter outputs
only after successful native queries. The default ordinary priority maps from 31
to native zero; FIFO/RR use the native 1–99 priorities. Setters call real native
pthread scheduling and obey its permissions. Yield calls native `sched_yield`.
No allocation or remembered scheduling registry is added. Non-default ordinary
priorities, non-default opaque words, unrepresentable real-time priorities and
native batch/idle/deadline/reset policies return `ENOTSUP` (45) explicitly.
On Mac the adapters retain the native scheduling parameter and policies.

The shared Mac/iOS fixture checks optional and guarded outputs, copied inputs,
invalid requests, yielding, isolated TLS and eight rounds of eight workers,
including changing a blocked worker's policy from another thread. The guest
independently checks the main thread's real FIFO/RR policy and priority in kernel
stat fields, forces `EPERM` with a zero real-time priority limit before dropping
root, and verifies that an inherited native batch policy leaves getter outputs
untouched before restoring ordinary scheduling. This kernel's thread stat files
report the process main thread's scheduling fields, so worker stat records are
not used for independent verification. ASAN/UBSAN checks two Mach-O loads/unloads
with every worker joined and condition/mutex destroyed. The full ARM64
C++/GLES/PPSSPP regression passes; the existing permission fixture again needed
a retry after `ENOENT`. These entries resolve eight more strong imports across
Fortnite and EOSSDK; the actual game still exits before entry at
`pthread_mach_thread_np` at that revision.

The installed Mac library returns a borrowed thread port from
`pthread_mach_thread_np`, while `mach_thread_self` adds an owned send reference.
Repeated borrowed queries leave the count unchanged. After native key destructors
and thread termination, owned references become dead-name references; a port with
only the borrowed reference disappears. Mac thread exit can destroy its port
asynchronously after joining. Send-reference overflow saturates at 65,535 and
pins reference counts; saturated dead names can still be removed in full. Native probes
also measured null/dead names, invalid rights, underflow and guarded outputs.

V now assigns a port namespace to adapter-created threads and to native threads
that query themselves. Each registered Vinix thread holds a real native robust
mutex for its lifetime. Native libc reports owner death after its key destructors,
so a freed pthread object or recycled thread ID cannot revive an old port. A V
start adapter publishes the native handle before entering the app callback;
return and explicit exit retain the native join result and destructor behavior.
Port lookup reverses to the actual native pthread handle. Owned references keep
dead names until released; lifetime objects are freed after native owner death.
The namespace has one cached borrowed reference per thread and preserves caller
errno. The native Mac main thread can have additional system-cached references,
so shared fixtures verify changes relative to its initial count.

The normal namespace mutex is pinned across fork. Prepare removes the caller's
lifetime mutex from its native robust list, the parent restores ownership, and
the child discards the inherited namespace before registering its surviving
thread. Shutdown releases the entry thread's lifetime, reaps terminated workers
and rejects active registered workers before unmapping callbacks. Port names are
not reused across image executions. Foreign native threads must query themselves
before remote lookup; unregistered remote handles return a null port. This subset
provides thread-port identity, type and reference operations. Mach IPC, task
thread enumeration, suspension, register state and thread policy RPCs remain
unimplemented.

The shared Mac/iOS fixture uses eight rounds of eight joined workers plus eight
detached workers, mixed normal/explicit exit and three rearmed key-destructor
passes. It checks borrowed/owned counts, guarded outputs, live and dead reference
operations, saturation, lookup to real native workers, native FIFO changes and a
worker fork. Detached termination is observed before their callback image unloads.
The Vinix guest also checks 64 failed native creations, unchanged output guards
and errno. ASAN/UBSAN exercises two Mach-O loads/unloads, a native fork after
unload and the V namespace's allocation/retirement paths; native robust owner
tracking is exercised in the ARM64 guest. The full C++/GLES/PPSSPP regression
passes. These entries resolve five strong imports across Fortnite and EOSSDK.
That probe still exited before entry at `pthread_mutexattr_setpolicy_np`.

The V mutex-attribute adapters now follow the measured 16-byte Darwin layout:
signature, signed priority ceiling and packed type, sharing, protocol and policy
fields. Initialization preserves the unused flag bits and defaults to private
NORMAL/FIRSTFIT. Getters use guarded 32-bit outputs; setters preserve unrelated
fields and reject invalid values. Copied attributes are independent values,
and destruction clears only a valid signature. Ceiling values range from -999
through 999 in the installed Mac implementation.

Both EOSSDK call sites request FIRSTFIT (3), including one recursive mutex.
These requests create real native mutexes: musl releases ownership before waking
a futex waiter, allowing a new contender to acquire it. Host verification uses
the Mac's explicit native FIRSTFIT policy. Recursive and ERRORCHECK behavior,
condition waits and errno preservation use native pthread operations. The C++
recursive constructor now builds attributes through the same V functions.
Explicit FAIRSHARE ownership handoff, shared-process mutex storage and priority
protocols remain unsupported: attributes can represent those requests, but mutex
initialization returns Darwin ENOTSUP (45) before allocating or changing the
caller object. Destruction requires a quiescent mutex; busy-object destruction
and cancellation are outside this tested subset.

The shared Mac/iOS fixture checks exact packed fields, copied attributes,
preserved guards, invalid policies and ceiling boundaries, all four static
initializers, timed condition waits and three rounds of eight workers for each
mutex type. It also runs inside the existing condition-attribute guest fixture.
ASAN/UBSAN checks two Mach-O loads/unloads and rejection before native allocation.
The full ARM64 C++/GLES/PPSSPP regression passes. That game probe got past the
mutex-policy import but still exited before entry at `pthread_rwlock_destroy`.

The V read/write-lock adapters now provide initialization, destruction, blocking
and try acquisition, unlock and sharing attributes. Darwin's 200-byte lock and
24-byte attribute layouts stay separate from native pthread storage. Attributes
preserve their unused bytes, copy by value and use guarded 32-bit sharing outputs.
The measured native attribute destruction accepts invalid/already-cleared values
and clears the signature and sharing field. Shared-process requests return
Darwin ENOTSUP before modifying the caller's lock.

Native rwlocks provide concurrent shared reads and exclusive writes. A V gate
uses a native mutex and condition variable to preserve the Mac's queued-writer
preference. Try-read returns busy after a writer queues, including for an existing
reader. Writer identity follows the real native pthread handle; uncontended
recursive acquisition reports EDEADLK, while try acquisition after a contended
writer handoff reports EBUSY as measured on the Mac. The adapter also diagnoses
blocking recursive write ownership with EDEADLK; the contended native-Mac
reference stalled on that path. Writer FIFO ordering and cancellation are
outside the verified subset.

Each operation pins the registry entry before accessing native state. Destruction
returns EBUSY while ownership or another caller exists, including waiters. The
last quiescent destruction frees the native lock, guard, condition and V state.
Image shutdown reclaims quiescent entries and rejects active ownership/callers.
The generated C confirms the state guard unlocks before the call reference drops.

Shared Mac/iOS checks exercise eight readers holding one lock concurrently,
eight queued-writer/read-waiter handoffs, three rounds of eight mixed workers,
copied attributes, lazy initialization, busy destruction, guards and errno.
The checks also run inside the condition-attribute guest fixture. ASAN/UBSAN
checks two image loads/unloads, 32 init/destroy cycles, pinned-entry destruction
and shutdown reclamation. The full ARM64 C++/GLES/PPSSPP regression passes using
the installed QEMU after a separate custom-QEMU ROM lookup failure. These APIs
resolve 19 strong imports across the three Fortnite images. The actual game
still exits before entry, now at `readlink`.

The V `readlink` adapter now reads real native symlink contents with a signed
64-bit result, guarded truncation and no null terminator. The installed Mac
reference accepts zero bytes while still validating the link and rejects counts
above INT_MAX before pathname validation. A one-byte stack read preserves the
zero-count behavior on Linux; successful calls preserve the thread's errno.
Native errors translate immediately to Darwin values. `symlink` creates actual
filesystem links rather than keeping a separate compatibility namespace.

The preserved guest kernel can lose absolute parent symlinks during native
lookup. On ENOENT, the V adapter resolves only the parent with the existing
native libc's component-by-component `realpath`, opens it with O_PATH, and
retries native `readlinkat` through that descriptor. The final link remains
unfollowed, including a self-referential link. The descriptor closes before
returning, and the generated C confirms all adapter scratch buffers stay on
the stack. The fallback uses native libc's symlink-chain limit; exact Darwin
chain limits and concurrent path replacement are outside the verified subset.

Shared Mac/iOS fixtures check missing and ordinary files, dangling targets,
absolute parent aliases and loops, null pointers, count limits, untouched buffer
guards and eight concurrent callers. The checks also run inside the permissions
guest fixture. ASAN/UBSAN checks two image loads/unloads, and the full ARM64
C++/GLES/PPSSPP regression passes. The actual game gets past two more strong
imports but still exits before entry, now at `recvmsg`.

The V `recvmsg` and `sendmsg` adapters now use real native scatter/gather socket
I/O with the 48-byte Darwin header and signed 64-bit results. Native errors
translate immediately, successful calls preserve thread errno, and failure
leaves the caller's header untouched. Address and control conversion uses
bounded stack storage; generated C confirms no adapter heap allocations.
Null name/control pointers retain their input lengths, and buffer guards survive
short addresses, datagrams and partial control headers.

SCM_RIGHTS uses actual native descriptor passing. The adapter delivers complete
descriptor integers and closes every installed descriptor that cannot reach the
caller, including zero capacity and partial words. This deliberately avoids the
inaccessible descriptor leaks measured in the native Mac reference. Ancillary
storage is limited to 8 KiB; unsupported send controls fail before socket I/O.
Real native timestamps translate to Darwin's four-byte-aligned 28-byte
SCM_TIMESTAMP record, using unaligned-safe copies for seconds and microseconds.
SO_TIMESTAMP maps to the native option, including Darwin's enabled option bit
on reads. The preserved Vinix kernel reports ENOPROTOOPT for receive timestamps;
the adapter does not invent arrival timestamps or report successful enabling.

The native guest recvmsg backend also rejects MSG_PEEK with ENOTSUP; rejected
calls preserve queued data and buffers. Other native flag combinations beyond
flags zero and DONTWAIT remain outside the verified guest subset. For datagrams
with fewer than 1,024 vectors, a private one-byte vector detects truncation in
the same atomic receive when the native INET backend omits MSG_TRUNC. Truncated
INET messages at the 1,024-vector boundary retain the native backend's flag
limitation. EOSSDK's traced call uses one vector, flags zero, and optional
128-byte name and 28-byte timestamp buffers.

Shared Mac/iOS checks cover real UNIX and IPv4/IPv6 traffic, scatter/gather,
guarded truncation, invalid headers/counts, native descriptor identity and eight
concurrent workers. ASAN/UBSAN checks two image loads/unloads, independent Linux
timestamp-layout bytes and 32 rounds of partial/absent descriptor storage with
unchanged native descriptor availability. The full ARM64 C++/GLES/PPSSPP
regression passes. These checks run inside the sockets guest fixture using the
previously verified host harness, leaving the concurrent host-controller
migration untouched. The actual game resolves one additional strong EOSSDK
import and still exits before entry, now at `select`.

The V `select` adapter now waits on actual native descriptors. It translates
Darwin's 32-bit bitmap words and 16-byte timeval into private native stack
storage, preserving the caller's timeout, padding and thread errno. Only the
required bitmap prefix is copied back on success; errors preserve all sets.
Descriptors are validated before waiting because the preserved native backend
can omit invalid descriptors instead of returning EBADF. The ready count comes
from each returned set bit, matching the Mac's count when one descriptor is both
readable and writable. Generated C confirms the adapter uses no heap storage.

The same V tests compare the installed Mac library with the adapter and run as
a native ARM64 executable in Vinix. They cover guarded buffers, descriptor 1023,
invalid counts/timeouts, closed descriptors, real delayed readiness, EOF, a
20 ms wait, unchanged timeval padding and eight concurrent workers. Host
ASAN/UBSAN and the full ARM64 C++/GLES/PPSSPP regression pass. Exception/urgent
data, signal interruptions and concurrent descriptor replacement remain outside
the verified subset. Infinite waits with no selected descriptors retain the
native backend's EINVAL limitation. EOSSDK's traced calls use 32-bit bitmap
operations, signed 32-bit counts/results and optional timeval pointers.

The standalone host driver and guest PID 1 are now V. They reuse the existing
prepared Mach-O fixtures and native compiler/library closure, boot the preserved
verified kernel, and stage both actual Fortnite frameworks for retries and
audits. New select tests execute in native V; the existing regression fixtures
are unchanged. That game retry resolved two more strong imports and exited
with status 1 before entry at `semaphore_create`.

The V Mach semaphore adapters now maintain actual credits and block using native
mutexes and condition variables. FIFO and LIFO policies grant one queued waiter
per signal; otherwise a signal adds a credit. Destroy wakes pending waits with
`KERN_TERMINATED` and consumes one send reference. Extra send references keep the
terminated port name valid until released. Dropping the last reference also
wakes pending waits. Call pins keep each object's native storage alive through
guard unlock and the last returning waiter. Generated C confirms wait nodes use
native stack storage, with no per-wait heap allocation, and identity comparisons
use addresses. Caller errno and guarded 32-bit outputs are preserved.

Names are not reused across runtime teardowns. The fork child discards private
copies without visiting vanished threads' wait nodes; the parent's waiters and
credits remain intact. Inherited semaphore rights are outside this process-private
subset and return an invalid-name error in the child. Only policies 0 (FIFO) and
2 (LIFO) are supported; other policy flags fail explicitly. Initial counts are
nonnegative signed 32-bit values. Signalling a full `INT_MAX` count returns
`KERN_RESOURCE_SHORTAGE`, avoiding the signed-count wrap observed in the installed
Mac library. Timed waits, broadcast/thread-targeted signals, cancellation and
interprocess Mach semaphore rights remain unimplemented or unverified.

Shared V checks compare native Mac and adapter credit consumption, blocking,
send-reference changes, terminated names, errors and eight destroy waiters.
Adapter checks also verify FIFO/LIFO order, eight last-reference-drop waiters,
count bounds, wrong-object ports, a fork while a worker is blocked, and two
runtime teardowns with an undestroyed object. Host ASAN/UBSAN and the full ARM64
C++/GLES/PPSSPP regression pass. The regression needed a retry after the previously
observed permissions `readlink`/`ENOENT` failure; its failed log is retained.
The V host driver now allows expected negative-fixture panics during regression
and receives a distinct failure marker from native PID 1. EOSSDK's two traced
create sites use FIFO with zero initial credits. The four adapters resolve four
strong EOSSDK imports; the actual game still exits with status 1 before entry,
now at `sigaction`.

The V signal bridge now translates Darwin's 16-byte action records and signal
numbers/masks to native libc. One-argument handlers receive the Darwin number;
default/ignored dispositions, `SA_RESTART` and `SA_NODEFER` use the actual native
implementation. `signal` uses a zero mask and restart semantics, matching the
installed Mac library, including EOSSDK's `signal(SIGWINCH, SIG_DFL)` call.
Queries, aliased input/output records, guarded outputs and caller errno are
preserved. EOSSDK's traced installation uses one-argument handlers with zero
mask/flags and saves/restores 16-byte records.

Process-static callback gates use lock-free atomics without allocation or mutexes
on delivery. Teardown closes the gates, restores original native dispositions
through libc, and drains running callbacks before unmapping app code. Runtime
restart is rejected while draining. A fork outside a callback clears the child's
copies of vanished threads' pins while preserving the parent's running callback.
Registry queries/changes while any callback is running return Darwin `EDEADLK`
(11) before taking a mutex; callers can retry after handlers return.

Other flags, including `SA_SIGINFO`, alternate stacks, reset-on-delivery and
child-specific modes, return `ENOTSUP` (45). Linux cannot represent Darwin
`SIGEMT`, `SIGINFO`, mask bit 32 or foreign native mask bits; those requests also
fail explicitly. Native `siginfo`/context layouts are not supplied as Darwin
objects. Fork/shutdown from inside a callback, concurrent native disposition
changes outside the bridge, and interrupted app APIs remain unverified.

Shared native Mac/V checks cover real delivery and masks, both verified flags,
aliasing, guards and errors. Adapter checks deliver signals on 32 worker threads
per round, fork while a worker's handler blocks, reject callback registry reentry
and restart during draining, and verify two runtime teardowns. Restored public
handler/mask/flags match; Linux libc's private restorer flag/padding need not be
byte-identical. Host ASAN/UBSAN and the full ARM64 C++/GLES/PPSSPP regression pass.
An earlier regression failed the existing stdio directory check with exit 73;
that log is retained, and the completed rerun passed. This resolves two strong
imports across Fortnite and EOSSDK. The actual game still exits with status 1
before entry, now at `strcspn` in EOSSDK.

`strcspn`, `strncat` and `strtok_r` now resolve to native libc entry points.
The installed Mac SDK and Vinix's libc use matching 64-bit sizes, pointers and
caller-owned tokenizer state for these byte-string operations. EOSSDK's traced
`strcspn` call uses the returned 64-bit span to split a string in place. The
existing host libSystem checks and full ARM64 C++/GLES/PPSSPP regression pass;
the regression needed a retry after the previously observed concurrent
permissions/readlink failure, whose log is retained. The three bindings resolve
four more strong imports. The actual game still exits with status 1 before
entry, now at `strerror` in EOSSDK. Native Mac measurements for the next
`strerror`/`strerror_r` adapters are retained under `byte-string-checks`;
those two imports were still unresolved in that probe.

The V `strerror` and POSIX `strerror_r` adapters now use the measured C-locale
Darwin messages for error numbers 0 through 107. Unknown signed 32-bit numbers
produce `Unknown error: <number>`, including `INT_MIN`, without integer overflow.
`strerror_r` copies a terminated prefix when space is short, returns `ERANGE`
(34), and preserves caller errno. Unknown numbers return `EINVAL` (22) even
when the output is truncated. Zero capacity writes nothing; a null destination
with nonzero capacity is explicitly rejected with `EINVAL`.

`strerror` reuses one 128-byte native TLS buffer per calling thread, preserving
errno for known numbers and setting `EINVAL` for unknown numbers. One private
native key lasts for the process; libc's resident `free` releases each worker's
buffer at thread exit, without calling app code. Buffers remain usable across
runtime teardowns. The reentrant formatter uses native stack scratch storage;
generated C confirms no per-call V heap allocation. Localized error text and
allocation-failure behavior against native Darwin remain unverified.

Shared native Mac/V tests compare all known messages, unknown numbers, errno,
seven guarded buffer sizes and truncation results. Adapter checks also exercise
32 workers per round with repeated calls, private buffer reuse and two runtime
teardowns. ASAN verifies that terminated workers' buffers were freed; host
ASAN/UBSAN and the full ARM64 C++/GLES/PPSSPP regression pass. These adapters
resolve four more strong imports across Fortnite and EOSSDK. The actual game
still exited with status 1 before entry, at `sysctl` in EOSSDK, in that probe.

The V numeric `sysctl` adapter now supports the hardware MIBs for configured
CPUs `{6,3}`, byte order `{6,4}`, page size `{6,7}`, physical memory `{6,24}`
and active CPUs `{6,25}`. EOSSDK directly requests `{6,25}` with a four-byte
destination; the main executable also requests `{6,24}` with eight bytes.
Counts and memory come from native libc, and page size comes from the running
kernel. Other MIBs, including process records and hardware strings, return
`ENOENT`; resolving the import does not establish support for every query.

Numeric and named hardware queries now share the measured Darwin buffer rules.
Short destinations remain untouched, return `ENOMEM` (12), and report length
zero. Size-only queries report the full width and preserve errno. Named page
size and physical memory use eight bytes; a four-byte destination receives a
narrowed value when it fits, otherwise `ERANGE` (34) leaves both outputs
untouched. Numeric page size remains four bytes. Nonempty writes to supported
leaves return `EPERM`; zero-length or null new values are reads. Invalid MIB
counts return `EINVAL`, and extra components on a supported leaf return
`EISDIR`. Named queries compare C strings directly and allocate nothing per
call, as confirmed in generated C. The existing physical-CPU names still use
logical native counts because separate topology reporting is unavailable;
CPU subtype/family remain generic zero values.

Native Mac comparisons cover nine guarded buffer capacities, numeric/name
widths, errno, invalid counts, omitted outputs and rejected writes. Host
ASAN/UBSAN and the full four-core ARM64 C++/GLES/PPSSPP regression pass;
eight workers per runtime exercise 16,000 query pairs across two teardowns.
The first full regression exposed a stale length-four assertion in the legacy
stdio fixture. The V staging tool checks the complete compiled fixture's hash
and surrounding instructions, then changes only that comparison immediate to
zero; its other checks remain intact. Two further attempts hit poisoned kernel
map keys during permissions/readlink checks. Those failed serial logs and VM
hashes are retained alongside the passing run under `sysctl-checks`.

The V monitor also rejects QEMU exit without a guest PASS marker and detects
interleaved kernel exception output. Direct host checks verify both failures
and successful completion. The hardware-query adapter resolves two more strong
imports. That probe still exited with status 1 before entry, at `tcgetattr`
in EOSSDK.

The V terminal adapters now implement `tcgetattr` and `tcsetattr` over real
native terminals. Darwin's 72-byte structure, flag positions, control-character
indices and disabled value (255 rather than Linux's zero) are translated
explicitly. Linux input baud zero means follow the output rate; the getter
reports that effective rate as measured on Darwin. Nineteen baud values from
zero through 230400 and separate input/output rates are supported. Immediate,
drained and flushed updates reach native `tcsetattr`; `TCSASOFT` and `CIGNORE`
preserve hardware flags and rates while applying software settings.

Conversion uses stack storage and copies getter output only after success;
generated C confirms no per-call heap allocation. Bad descriptors, pipes,
invalid actions and null buffers return Darwin errors, and successful calls
preserve errno. Unsupported native flags leave the entire destination untouched
and return `ENOTSUP` (45). Unrepresentable Darwin flags or control characters,
including an enabled NUL binding, are rejected before applying an update;
unsupported baud values return `EINVAL`. Additional output delays, separate
CTS/RTS flow control and Darwin-specific special characters remain unsupported.

Native Mac PTY comparisons and host ASAN/UBSAN checks pass. All six native V
checks pass in the four-core ARM64 guest, including real echo suppression and
restoration, flag and character mapping, separate baud readback, soft updates,
guarded errors, four workers and two teardowns. The broader Mach-O regression
failed three times in the existing concurrent permissions check with `chmod`
returning `ENOENT`; that revision did not pass the broader suite. These logs and the two
earlier terminal failures that exposed the input-baud encoding are retained
with VM hashes under `terminal-checks`. The actual Fortnite probe gets past
four more strong imports and still exited with status 1 before entry, at
`thread_policy_set` in EOSSDK, in that probe.

The installed Mac's ARM64 `thread_policy_set` returns `KERN_NOT_SUPPORTED`
(46) for cache-affinity hints, including an empty request. EOSSDK requests
that flavor with one 32-bit tag and ignores the return value. V now returns
the same result for live thread ports; a CPU binding would have different
semantics. Calling-thread standard policy and extended policy with timesharing
enabled apply real native ordinary scheduling. Fixed-priority, time-constraint,
importance and remote scheduling updates remain unsupported. Remote requests
never dereference a borrowed pthread pointer that another thread could free.

The adapter validates the shared Mach namespace. Live task/semaphore ports
return `KERN_INVALID_ARGUMENT` (4), while invalid or dead thread destinations
return `MACH_SEND_INVALID_DEST` (268435459). Like the native MIG client, it
rejects arrays larger than sixteen 32-bit words with `MIG_ARRAY_TOO_LARGE`
(-307) before destination lookup. It preserves errno and allocates nothing
per call, as confirmed in generated C. Oversized requests and affinity hints
do not read or modify caller policy storage.

Native Mac measurements and host ASAN/UBSAN checks pass. Eight workers per
runtime make 16,000 guarded affinity calls across two teardowns; live remote,
dead, wrong-type and destroyed semaphore ports are covered. The ARM64 guest
independently verifies restoration from native FIFO to ordinary scheduling.
All seven native V checks and the full four-core ARM64 C++/UIKit/GLES/PPSSPP
regression pass at this revision. The initial test incorrectly expected a
surviving reference after semaphore destruction consumed its only send
reference; it now retains a second reference and verifies its release. That
failed serial log and VM hashes are retained under `thread-policy-checks`.
This resolves two more strong imports. The actual Fortnite probe still exits
with status 1 before entry, now at `utime` in EOSSDK.

V now implements `utime` with real native filesystem updates. Its Darwin
input has two signed 64-bit seconds, preserving EOSSDK's existing access
time while changing modification time. A null timestamp pointer sets both
times to now. Native errors are translated, successful calls preserve errno,
and input storage remains unchanged. Native component lookup retries an
`ENOENT` result to handle the kernel's absolute-symlink lookup limitation
and recover `ELOOP` for a self-referencing link.

`uuid_generate` now fills precisely sixteen bytes from native `getentropy`,
setting the version-4 and RFC variant bits measured on the installed Mac.
It preserves thread-local errno and fails if native entropy is unavailable.
Both adapters allocate no V heap storage per call, as checked in generated C.
Native Mac ASAN/UBSAN checks pass. Eight workers over two runtime teardowns
verify timestamps with independent native stat reads, epoch/pre-1970/post-2038
values, symlinks, set-to-now behavior, unchanged file contents and guarded
inputs. UUID checks verify 16,000 distinct values, every random bit varying,
guarded outputs and thread-local errno. Both new checks also pass in Vinix.

The final four-core ARM64 run passes all nine native V checks and the full
C++/UIKit/GLES/PPSSPP regression. The first run exposed the symlink-loop
error above; a second run passed the native checks but hit an intermittent
`ENOENT` in the existing concurrent readlink fixture's regular-file lookup.
Both failed serial logs and VM hashes are retained under `file-time-checks`,
alongside the passing run and native Mac measurements. Four more strong
imports now resolve. The actual Fortnite probe still exits with status 1
before entry, at AVFAudio's `AVAudioSessionInterruptionOptionKey` in EOSSDK.
Its native Mac string value and the other imported audio-session constants
have been measured; audio-session configuration and output remain unsupported.

The thirteen remaining imported AVAudioSession string constants now resolve
through both AVFAudio and AVFoundation. Their values match the installed Mac's
native exports, including `Receiver`, `Speaker` and `Headphones` for the port
constants. Each data import addresses a cached, owned eight-byte NSString
pointer cell. Native Mac ASAN/UBSAN checks verify guarded UTF-8 conversion,
framework alias identity, eight concurrent first lookups, autorelease-pool
survival and two clean runtime teardowns.

All ten native V checks and the full four-core ARM64 C++/UIKit/GLES/PPSSPP
regression pass. An initial run passed the native checks before hitting the
previously observed concurrent readlink fixture's regular-file `ENOENT`;
its serial log and VM hashes are retained under `audio-session-checks`.
Sixteen more strong imports resolve across the executable and EOSSDK.
The actual Fortnite probe still exits with status 1 before entry, now at
CoreFoundation's `CFDictionaryAddValue` in EOSSDK. Audio-session configuration
and output remain unsupported.

`CFDictionaryAddValue` now keeps the first key/value pair for an equal key,
without retaining discarded entries or changing the mutation count. Type
callbacks compare owned keys by value; null callbacks compare raw pointers.
Native CoreFoundation measurements also confirm that raw null keys and values
are valid, and both AddValue and SetValue now support them.

CoreFoundation's `__NSDictionary0__struct` export now resolves to the immutable
empty dictionary object itself. Its address is stable across concurrent first
lookups and the existing empty-dictionary alias. Native retain/release calls
leave this constant alive; the V runtime does the same, then frees its cache
reference after containing collections and the root autorelease pool finish.
Native Mac ASAN/UBSAN checks cover all four supported callback combinations,
duplicate-key ownership, 258-entry growth, eight independent dictionary workers,
eight concurrent singleton lookups and two clean teardowns per new check.

All eleven native V checks and the full four-core ARM64 C++/UIKit/GLES/PPSSPP
regression pass with these dictionary changes. The intermediate AddValue-only
run and its next-blocker probe at the empty-dictionary export are retained
with VM and runner hashes under `cf-dictionary-checks/before-empty`.
Three more strong imports now resolve. The actual Fortnite probe still exits
with status 1 before entry, at Objective-C's `objc_constructInstance` in EOSSDK.

`objc_constructInstance` and `objc_destructInstance` now use V implementations
matching measurements against the installed Mac's Objective-C runtime. A supplied,
aligned, zero-filled buffer becomes the instance itself, without sending
`+initialize` or `init`. C++ constructors run superclass first; a failing
constructor unwinds only completed bases and leaves the caller's bytes intact.
Explicit destruction runs derived-class destructors first, clears weak slots,
releases owned metadata and returns the original address without freeing it.

Private metadata now lives in a separately allocated, synchronized object
registry for both ordinary and supplied instances. A custom deallocator can
explicitly destroy its instance and then preserve or free its storage; the
outer release keeps metadata until that callback returns and avoids a second
free. Class instance counts track destruction and `object_setClass`. Framework
and GLES dispatch select their supported classes before reading metadata, so
literal NSString messages continue to reach Foundation.

Native Mac ASAN/UBSAN checks cover guarded buffer reuse, constructor failure,
weak references, custom deallocation and ordinary allocated instances. Eight V
workers and two runtime teardowns leave the object registry and live counts
empty. The unchanged Objective-C++ startup fixture supplies genuine native C++
class flags for the Mac measurements. Proofs and generated lifecycle bodies
are retained under `objc-storage-checks`.

All twelve native V checks and the full four-core ARM64 C++/UIKit/GLES/PPSSPP
regression pass. An initial accessibility regression from eager metadata
lookups was fixed; another run stopped earlier in the unchanged file-timestamp
fixture. Both failed serial logs and VM hashes are retained. Four more strong
imports now resolve. The next Fortnite linking blocker was
`objc_getAssociatedObject` in EOSSDK.

`objc_getAssociatedObject`, `objc_setAssociatedObject` and
`objc_removeAssociatedObjects` now use V-owned association tables. All five
native policies are supported: assign, retain and copy, with atomic getters
retaining under the runtime lock and autoreleasing into the caller's pool.
Keys compare by address, including null keys. Copy invokes app methods or
creates immutable snapshots of supported mutable data and collections; copied
blocks move to heap storage. Replacement acquires the new value before
retiring the old one, preserving same-value assignments.

Removal detaches the table before releasing values, allowing deallocation
callbacks to read or add associations. Instance and heap-block destruction
remove associations after C++ and capture destructors. Classes and literal
strings can also own associations. Shutdown drains their tables and the root
autorelease pool until reentrant callbacks leave both empty.

Native Mac ASAN/UBSAN checks cover policy ownership, raw keys, mutable copies,
explicit destruction, C++ destructor ordering, blocks and reentrant removal.
Eight workers share one owner; atomic getter references survive simultaneous
replacement and removal. Two V runtime teardowns leave association tables,
object metadata and live counts empty. Measurements, EOSSDK call traces and
generated lifecycle bodies are retained under `objc-associated-checks`.

All thirteen native V checks and the full four-core ARM64 C++/UIKit/GLES/PPSSPP
regression pass. Earlier runs hit the previously observed concurrent readlink
and file-timestamp failures in unchanged checks; both failed serial logs and
VM hashes are retained. Four more strong imports resolve. The next Fortnite
linking blocker was `objc_getProperty` in EOSSDK.

V now implements `objc_getProperty`, the legacy six-argument `objc_setProperty`,
and the atomic retain/copy setters. The existing nonatomic setters share the
same implementation, including real copying of supported Foundation values.
Atomic getters retain the slot value under the runtime lock and autorelease it
after unlocking. Setters acquire or copy the new value before locking, publish
it before retiring the old reference, and run deallocation callbacks outside
the lock. Signed pointer-sized offsets address the app's actual ivar storage;
offset zero delegates to the existing class access/replacement helpers.

Native property setters invoke `copyWithZone:nil` or `mutableCopyWithZone:nil`
directly, ignoring overrides of `copy` and `mutableCopy`. V matches this
measured behavior while associated-object copying continues to dispatch
`copy`. Mutable data, arrays and dictionaries receive independent mutable
snapshots. Copy setters also promote stack blocks to owned heap blocks.

Native Mac ASAN/UBSAN checks cover all setters, getter pool ownership,
guarded positive and negative offsets, class replacement, nil-copy clearing,
mutable snapshots, blocks and reentrant deallocation. A deallocator waits for
another thread to read the same slot, verifying that callbacks run without
the property lock. Eight workers share a slot, and two V teardowns leave
metadata, class instance counts and live objects empty. An initial native
block fixture accessed V state before initialization; it was corrected and
the clean sanitizer run and passing guest suite repeated. Its diagnostic and
the earlier passing VM hashes are retained under `objc-property-checks`.
Intervening runs hit a filesystem fault in the preserved kernel's
`fs.reduce_node_on_mount` during concurrent readlink, and the previously
observed timestamp failure. Their serial logs and VM hashes are also retained.

All fourteen native V checks and the full four-core ARM64 C++/UIKit/GLES/PPSSPP
regression pass. Six more strong imports resolve. The next Fortnite linking
blocker was `objc_sync_enter` in EOSSDK.

`objc_sync_enter` and `objc_sync_exit` now provide recursive object monitors
in V, matching measurements against the installed Mac Objective-C runtime.
Nil succeeds; an unmatched exit or an exit from another thread returns signed
32-bit `-1`. Keys are opaque identities: classes, tagged pointers and blocks
are accepted without inspecting or retaining the object. Releasing an instance
or block while its monitor is held does not prevent the matching exit.

Each recursive entry or waiting acquisition pins its monitor under the runtime
registry lock, then waits on a separate native recursive mutex after unlocking
the registry. Independent monitors and object creation can therefore progress
while a caller waits. Exit keeps the registry guarded through native unlock
and frees the monitor only after the last entry and waiter are gone. Balanced
use leaves no monitor allocations; shutdown requires an empty table.

Native Mac ASAN/UBSAN checks cover nil, ownership errors, recursive depth 64,
weak death while locked, opaque and released-block identities, 50 recursive
waiter handoffs and independent registry access. Eight workers protect a
shared counter while another thread attempts foreign exits. Two V runtime
teardowns leave monitors, object metadata, blocks and live counts empty.
Measurements, EOSSDK call traces, generated bodies and failed VM evidence are
retained under `objc-sync-checks`.

All fifteen native V checks and the full four-core ARM64 C++/UIKit/GLES/PPSSPP
regression pass. Three earlier attempts hit poison-pointer faults in the
preserved kernel's `fs.reduce_node_on_mount` or `stubs.memcmp` during the
unchanged concurrent timestamp check, before reaching the monitor check.
Their serial logs, VM hashes and kernel debug-symbol locations are retained.

Four more strong imports resolve. The following Fortnite probe exited with
status 1 before entry, at Swift's string-to-UTF-8 array getter
`_$sSS11utf8CStrings15ContiguousArrayVys4Int8VGvg` in EOSSDK.

The first Swift core exports now implement the builtin string-literal
initializer, consuming interpolation initializer and `String.utf8CString`
in V. Their two-register String ABI,
15-byte inline storage, immortal literal bias and borrowed native tail storage
match calls into this Mac's installed Swift library. UTF-8 conversion copies
all code units, including embedded NULs, into independently owned byte arrays
with a trailing NUL, count at byte 16, capacity/flags at byte 24 and elements
at byte 32. Shared and foreign String forms fail before their pointers are read.
The frozen interpolation builder holds one String field; its consuming
initializer transfers both words with no extra retain or release. Native
owned-string measurements verify that the reference count stays unchanged.

Swift retain/release, batch releases and uniqueness checks operate on these
V-owned buffers. The reference-count word starts at three and stores extra
strong references above bit 32. The runtime lock guards count changes and
removal before final free; overflow and underflow fail without changing the
buffer. Bridge ARC preserves native spare bits, ignores immortal/tagged values
and routes Objective-C bridge objects through their existing ownership APIs.
Unknown-object ARC distinguishes these buffers from registered Objective-C
objects. The batch signatures follow Swift's
[runtime declarations](https://github.com/swiftlang/swift/blob/swift-6.3-RELEASE/include/swift/Runtime/HeapObject.h):
plain release uses unsigned 32-bit counts, bridge release signed 32-bit counts.
On ARM64, plain retain/release also follow Swift's preserve-most convention.
Two entry thunks emitted in V preserve registers x9–x15 in addition to the
ordinary C callee saves. Their page is written once, made executable/read-only
and unmapped at quiescent shutdown. Register-seeding probes against native and
V entries verify nil and owned-buffer calls.

This is a bounded String/byte-buffer implementation. Its buffer header points
to a private V descriptor, not Swift class/type metadata. Generic array
reflection, casts, value witnesses, allocation, weak/unowned ownership and ARC for
application Swift heap objects still fail explicitly. Returning this buffer
does not establish compatibility with generic Swift array operations.

Native Mac ASAN/UBSAN checks compare literal register pairs and array bodies,
nil/tagged/Objective-C ownership, native owned String input, batch releases,
unique references and eight concurrent ARC workers. Exact-size inputs cover
each small-string length, and returned arrays survive releasing their source.
Repeated conversions and two V runtime teardowns leave the owned-buffer and
Objective-C object registries empty. Measurements, installed Swift interfaces
and headers, EOSSDK call traces and generated bodies are retained under
`swift-string-checks`.

All sixteen native V checks and the full four-core ARM64 C++/UIKit/GLES/PPSSPP
regression pass. One final-build attempt passed the Swift check but exited 73
in the unchanged stdio directory-enumeration fixture. That return covers
errno, directory close or a missing/duplicate created entry; the cause is
not established. Its serial log and VM hashes are retained, and the identical
suite passes on retry.

Thirty more strong imports resolved. That Fortnite probe exited with status 1
before entry at String type metadata `_$sSSN` in EOSSDK.

String metadata, its nominal descriptor and accessor now resolve in V, with
all eight value witnesses. Measurements against this Mac's installed library
verify struct kind `0x200`, the header's witness pointer, size/stride 16,
8-byte alignment and the sole field offset zero. The descriptor identifies
`Swift.String` through relative pointers and returns the same complete metadata
through its accessor for blocking and nonblocking requests. The
[Swift metadata ABI](https://github.com/swiftlang/swift/blob/swift-6.3-RELEASE/include/swift/ABI/Metadata.h)
and [value-witness definitions](https://github.com/swiftlang/swift/blob/swift-6.3-RELEASE/include/swift/ABI/ValueWitness.def)
provide the layouts and callback signatures.

Copies acquire their bridge owner before writing the destination. Assignments
publish the new words before releasing the previous owner; takes transfer the
reference without acquiring it. Destruction releases the owner without clearing
the now-uninitialized words. Supported ownership paths cover inline/immortal
Strings and registered Cocoa bridge objects. ARC for application Swift heaps
still fails explicitly; native owned String measurements exercise native
witnesses only. Foreign String ownership does not add foreign UTF-8 conversion.

The two enum witnesses encode Optional and other single-payload enum cases.
The advertised extra-inhabitant count is `INT32_MAX`; the native raw reader
recognizes low 32-bit bridge-pointer patterns. Enums with more empty cases use
one trailing tag byte and a case index in the first four payload bytes.
Tests allocate exactly 16 or 17 bytes and compare encodings through `UINT32_MAX`.
An initial boundary assertion incorrectly equated the advertised count with
the raw reader's range; additional native measurements corrected that assumption.

One mapping holds adjacent accessor and metadata pages, keeping relative
pointers in signed 32-bit range. V emits the ARM64 accessor, seals its page RX
and the data page read-only, then publishes the metadata under the runtime lock.
Quiescent teardown unmaps both pages. The nominal descriptor has no reflection
field record; generic reflection and mangled type lookup remain unresolved.
The UTF-8 arrays still use their separate private buffer descriptor.

Native Mac/V ASAN/UBSAN checks cover all eight callbacks, descriptor/accessor
responses, buffer guards, enum boundaries, copy self-assignment, assignments
between owners and eight concurrent copy/destroy workers. V deallocation
callbacks verify the replacement owner is already published and wait for a
second thread to copy it, checking that callbacks hold no witness lock.
Two runtime teardown cycles leave objects, owned buffers and metadata mappings
empty. Native captures, fixed-version primary sources, installed SDK interfaces
and generated bodies are retained under `swift-metadata-checks`.

All seventeen native V checks and the full four-core ARM64 C++/UIKit/GLES/PPSSPP
regression pass. Two earlier runs failed at the unchanged timestamp fixture's
successful-`utime` assertion before reaching the new check. A separate diagnostic
copy and then the unchanged final build both pass; the failures' cause remains
unestablished. Serial logs and VM hashes for both failures and the diagnostic
run are retained, along with matching generated timestamp helper bodies from
the prior passing build.

Two more strong imports resolved. That probe exited with status 1 before
entry at String's `TextOutputStreamable` protocol witness table
`_$sSSs20TextOutputStreamablesWP` in EOSSDK.

String's `TextOutputStreamable` and `CustomStringConvertible` conformances now
resolve with real protocol/conformance descriptors and witness tables. V emits
their ARM64 adapters into the existing accessor page and their relative records
into the read-only metadata page before publication. The stream witness forwards
the borrowed String to the caller's generic target `write` requirement, preserving
its metadata, table and inout context. The description witness returns the same
String words with an acquired bridge owner. Copies retained by a stream remain
the stream's responsibility. The layouts follow Swift's
[protocol metadata definitions](https://github.com/swiftlang/swift/blob/swift-6.3-RELEASE/include/swift/ABI/Metadata.h);
installed callback instructions and native calls establish their register and
ownership conventions.

V research uses this Mac's Swift library and installed LLVM C disassembler.
Native/V ASAN/UBSAN checks compare both descriptors, two independent generic
target metadata/table/context addresses, unchanged borrowed inputs and reference
counts inside callbacks, owned descriptions, preserved Swift contexts and nested
calls from another worker. Small, immortal and Cocoa bridge Strings are covered;
native owned Swift Strings are measured on native witnesses only. Two V teardowns
leave the object, buffer and metadata registries empty. Native instructions,
installed interfaces, fixed-version primary sources, generated bodies and guest
evidence are retained under `swift-protocol-checks`.

All eighteen native V checks and the full four-core ARM64 C++/UIKit/GLES/PPSSPP
regression pass. The first attempt passed all eighteen checks but the unchanged
stdio directory-enumeration fixture returned 73; an identical retry failed the
timestamp fixture's successful-`utime` assertion. The third identical full build
passes. Both failed serial logs and VM hashes are retained; their causes remain
unestablished.

Three more strong imports resolved. That probe exited with status 1 before
entry at the generic `RawRepresentable.hashValue` getter in EOSSDK,
`_$sSYsSHRzSH8RawValueSYRpzrlE04hashB0Sivg`.

The getter, generic `_hashValue(for:)` function and three Hashable requirement
dispatch entries now resolve in V. Generic hashing calls the caller's
`Self._rawHashValue(seed: 0)` witness; requirement dispatch selects `hashValue`,
`hash(into:)` or `_rawHashValue(seed:)` from that conformance. The
[Swift Hashable implementation](https://github.com/swiftlang/swift/blob/swift-6.3-RELEASE/stdlib/public/core/Hashable.swift)
and installed interfaces establish the zero-seed behavior. Native instructions
and callback probes establish the argument order and witness slots.

These entries borrow opaque receivers without inspecting or copying them.
Methods preserve Swift's context register, while the free function temporarily
sets it to the value address and restores the caller's context after the callback.
Signed 64-bit seeds/results and the original inout pointer pass through unchanged.
One V-emitted code page is sealed RX before publication under the runtime lock;
callbacks hold no lock and quiescent teardown unmaps it. Hashing dispatch does
not allocate String metadata or provide a hashing algorithm itself.

Native/V ASAN/UBSAN checks exercise all five entries with exact one-byte,
16-byte and Objective-C-reference receivers, distinct generic tables, separate
getter/raw-hash callbacks, `INT64_MIN/MAX` seed/result boundaries, guarded inout
state and unchanged ownership inside callbacks. Eight workers check concurrent
publication and another eight exercise callbacks. Reentrant callbacks wait for
a worker that resolves the same runtime symbol and hashes another value.
Two runtime cycles leave objects, buffers and code mappings empty. Native LLVM
instruction captures, fixed-version primary sources, installed SDK interfaces,
generated bodies and guest evidence are retained under `swift-hash-checks`.

All nineteen native V checks and the full four-core ARM64 C++/UIKit/GLES/PPSSPP
regression pass. The initial attempt failed the unchanged timestamp fixture's
successful-`utime` assertion. An identical retry passed all nineteen checks but
the stdio directory-enumeration fixture returned 73; the third identical full
suite passes. Both failed serial logs and VM hashes are retained; causes remain
unestablished.

Those dispatch entries resolved two more strong imports. That probe exited with
status 1 before entry at the `RawRepresentable._rawHashValue(seed:)` default in EOSSDK,
`_$sSYsSHRzSH8RawValueSYRpzrlE08_rawHashB04seedS2i_tF`. Native instructions for
that blocker establish that it creates a local Hasher and calls Self's
`hash(into:)` witness.

That default and the general Hashable raw-hash default now resolve in V, with
Hasher constructors, scalar/partial/raw-buffer combining, generic combine,
finalizers, static hash functions and process hashing parameters. The frozen
72-byte layout contains a tail/count word, four SipHash state words and four
reserved zero words. The implementation follows
[Swift Hasher](https://github.com/swiftlang/swift/blob/swift-6.3-RELEASE/stdlib/public/core/Hasher.swift)
and [SipHash-1-3](https://github.com/swiftlang/swift/blob/swift-6.3-RELEASE/stdlib/public/core/SipHash.swift),
and matches the installed library's intermediate states and final hashes.
The process seeds are generated once with native entropy; setting
`SWIFT_DETERMINISTIC_HASHING=1` selects zero keys, matching
[Swift's process parameters](https://github.com/swiftlang/swift/blob/swift-6.3-RELEASE/stdlib/public/stubs/GlobalObjects.cpp).
The same parameters are exported for client-inlined initialization and survive
runtime shutdown.

V emits ARM64 bridges for Swift's context register and raw-hash defaults into
the existing immutable RX page. Defaults borrow opaque Self, create a local
Hasher, call the caller's Hashable witness and finalize its state. Generic
combine temporarily uses the value as context and restores the Hasher context.
Raw buffers use start/end addresses and bounded byte loads at any alignment.
Public consuming `finalize()` computes on a copy; internal `_finalize()` mutates
the original state. These operations allocate nothing and hold no runtime lock
across callbacks.

Native/V ASAN/UBSAN checks pass with random and deterministic process seeds,
covering all 21 functions and the parameters export. They compare 64 captured
native hash vectors with eight chunk sizes, all tail occupancies and partial
lengths, narrow integer truncation, modulo-256 count wrap, signed seed boundaries,
guarded state and unaligned buffers through 513 bytes. Generic/default callbacks
exercise borrowed one-byte and 16-byte receivers, context preservation,
reentrant symbol resolution and eight concurrent workers. Concurrent resolution
and two runtime teardowns leave no objects, buffers or code mappings. The earlier
generic hash checks also pass in both seed modes. Measurements, generated bodies,
fixed primary sources and guest evidence are retained under `swift-hasher-checks`.

Generated C checks verify that the runtime Hasher bodies contain no heap
allocation calls. Function-scoped stack storage avoids V's automatic promotion
of temporary state passed to ABI entry bodies. All twenty native V checks and
the full four-core ARM64 C++/UIKit/GLES/PPSSPP regression pass on the final build.
The passing preliminary regression and probe are retained with VM hashes;
the final evidence uses the rebuilt runners after the stack-storage fix.

Five more strong imports resolved in that build. Its probe exited with status 1 before
entry at EOSSDK's `RawRepresentable.hash(into:)` default,
`_$sSYsSHRzSH8RawValueSYRpzrlE4hash4intoys6HasherVz_tF`.

That default now resolves in V. It obtains associated RawValue metadata, sizes
a 16-byte-aligned stack temporary using the value witness table, calls the
RawRepresentable getter with its indirect result address in `x8`, then calls
RawValue's hash witness with the temporary as Swift context. Value-witness
destruction consumes the owned getter result exactly once afterward. Self stays
borrowed and unchanged. The callbacks hold no runtime lock, and generated C
checks verify scoped stack storage without V heap promotion.

The genuine RawRepresentable protocol descriptor and its requirement-base,
associated-type, initializer and getter descriptor aliases also resolve. Native
descriptor flags, relative names and alias addresses were measured. Associated
type slots contain complete metadata or a low-bit-tagged mangled name, rather
than an accessor function. The V helper follows
[Swift's associated-type lookup](https://github.com/swiftlang/swift/blob/swift-6.3-RELEASE/stdlib/public/runtime/Metadata.cpp)
and [metadata ABI](https://github.com/swiftlang/swift/blob/swift-6.3-RELEASE/include/swift/ABI/Metadata.h):
cached metadata returns state Complete for every request; the concrete `SS`
String mangling, with or without its protocol-context prefix, resolves to
String metadata and publishes it using acquire/release operations. Other
generic or symbolic mangled type names reject explicitly.

Native/V ASAN/UBSAN checks pass in both hash-seed modes. They exercise exact
payload sizes 0, 1, 3, 8, 16, 17, 33, 257 and 8,193 bytes, distinct metadata and
witness tables, guarded Hasher state, preserved contexts, associated requirement
indices 1/3/7/15, complete-response requests and concurrent tagged-name caching.
Getter/hash/destroy ordering and reference ownership are checked inside callbacks;
String cases use the actual native and V String destruction witnesses. Reentrant
callbacks at every phase wait for another resolver worker, eight workers hash
independent values, and two runtime cycles leave no owned objects, buffers or
mappings. The existing Hasher checks also pass under ASAN/UBSAN. Evidence is
retained under `swift-raw-representable-checks`.

All twenty-one native V checks and the full four-core ARM64 C++/UIKit/GLES/PPSSPP
regression pass on the final build. The passing preliminary regression, probe
and audits from before the requirement aliases are retained with VM hashes and
both runner binaries/generated C; final evidence uses the rebuilt exports.

Fourteen more strong imports resolved in that build. Its probe exited with status
1 before entry at EOSSDK's generic Array metadata accessor, `_$sSaMa`.

The Array accessor and nominal descriptor now resolve in V. Measurements from
the installed Mac library show an eight-byte BridgeObject payload, independent
of Element, and a shared value witness table. Each specialization records its
Element metadata pointer and zero field offset. The implementation follows
[Swift's frozen Array definition](https://github.com/swiftlang/swift/blob/swift-6.3-RELEASE/stdlib/public/core/Array.swift)
and [generic metadata ABI](https://github.com/swiftlang/swift/blob/swift-6.3-RELEASE/include/swift/ABI/Metadata.h).
The descriptor has one key type parameter, no requirements, nearby accessor and
instantiation bridges, a complete instantiation pattern and writable zero-filled
private cache storage. Reflection Fields records remain absent.

The cache publishes one sealed metadata mapping per exact Element pointer under
the runtime lock. Repeated requests reuse the same complete metadata. Eight value
witnesses implement retain/copy, destroy, copy/take assignment and enum tags.
Copies acquire ownership before publishing, assignments publish before retiring
the old owner, and takes transfer ownership without retaining. Releases hold no
registry lock across an ObjC deallocator. The array storage ARC path currently
accepts registered UTF-8 buffers, ObjC owners and immortal references; this does
not implement general Swift array storage allocation or reflection.

Native/V ASAN/UBSAN checks pass in both hash-seed modes, alongside the existing
String metadata and String/ARC checks. They cover both exports, descriptor and
pattern accessors, complete-response requests, all eight witnesses, guarded
buffers, native and ObjC ownership, distinct-owner and self-copy assignments,
and exact eight/nine-byte enum payloads through `UINT32_MAX`. Eight workers race
publication of sixteen nested specializations while copying shared owners.
A native nonblocking request may observe partial initialization; the native
fixture requests completion before using that entry. Vinix always publishes
complete metadata. Reentrant deallocation waits for another resolver/copy worker.
Two shutdowns leave no owners and prove all specialization and arena mappings
unmapped. Generated C checks reject hidden V heap promotions in the runtime
bodies. Measurements, primary sources and verification evidence are retained
under `swift-array-checks`.

All twenty-two native V checks and the full four-core ARM64 C++/UIKit/GLES/PPSSPP
regression pass. Three more strong imports resolved. Its probe exited with
status 1 before entry at EOSSDK's `Int.init(bitPattern: OpaquePointer?)`,
`_$sSi10bitPatternSis13OpaquePointerVSg_tcfC`. The installed initializer is a
single return instruction; native calls preserve all 64 bits, including nil and
the signed boundary.

That initializer now resolves in V and preserves the raw pointer word as signed
64-bit Int. It reads no pointed-to memory and performs no ownership operations.
Native/V ASAN/UBSAN checks pass in both seed modes, covering nil, signed limits,
every single and complemented bit, Swift context preservation and 32,768 inputs
across eight concurrent workers. Two runtime cycles leave no owners or metadata
allocations. The existing Array checks also pass under sanitizers. Both compiled
ARM64 runners contain the same single `ret` instruction as the native initializer;
generated C checks verify no hidden allocations.

The pointer initializer layer passed twenty-three native V checks and the full
four-core ARM64 C++/UIKit/GLES/PPSSPP regression, resolving one more strong import.
Its probe stopped before entry at EOSSDK's Int Hashable table, `_$sSiSHsWP`;
evidence is retained under `swift-integer-checks`.

Int now has canonical, sealed metadata, all eight POD value witnesses, and real
Equatable/Hashable witness tables and conformance descriptors in V. Its eight-byte
payload has no extra inhabitants; enums with empty cases use one additional tag
byte. Hashable's descriptor includes its generic signature requiring Equatable,
the inherited table requirement and the three hashing requirements. Public Int
hashing and borrowed indirect witnesses feed the full word into the existing
process-seeded Hasher. Generic dispatch, combine, hash-value and raw-hash defaults
use the same tables. Metadata, descriptor, accessor and measured protocol aliases
resolve together; runtime-wide conformance discovery remains unsupported.

Native/V ASAN/UBSAN checks pass in random and deterministic seed modes: value
witnesses, exact eight/nine-byte enum storage through UINT32_MAX, signed limits,
every single/complemented bit, five signed seeds, all partial Hasher tails,
guarded state, equality/inequality, unchanged borrowed inputs and Swift context
preservation. Eight workers exercise concurrent publication and hashing;
`Array<Int>` uses the same metadata. Two drained teardowns prove both Int pages
unmapped after dependent Array specializations retire. Generated C contains no
hidden allocations in the thirteen Int runtime bodies or existing Array bodies.

The Int layer passed twenty-four native V checks and the full four-core ARM64
C++/UIKit/GLES/PPSSPP regression, resolving twenty-four more strong imports across
the three images. Its probe stopped before entry at EOSSDK's StaticString overload
of `_assertionFailure`,
`_$ss17_assertionFailure__4file4line5flagss5NeverOs12StaticStringV_A2HSus6UInt32VtF`.
Evidence is retained under `swift-integer-hash-checks`, including installed LLVM
disassembly obtained from V, native descriptor/enum measurements, sanitizer and
guest logs.

Swift assertion failures now have real V diagnostic bodies and sealed ARM64
entries. Both `_assertionFailure` overloads with a file argument and the
StaticString `_fatalErrorMessage` alias capture the registers and spilled file
flag, line and reporting flags. StaticString supports pointers and Unicode
scalars; String supports the existing small, native-tail and immortal-literal
forms. Diagnostics preserve native empty-message and bounded NUL behavior,
checked CInt lengths and UInt32 lines. Each entry ends in `brk #1`; assertions
never return successfully. Invalid arguments and unsupported foreign/shared
String storage report a bridge diagnostic and trap. Host debugger crash
annotations/backtrace integration remain unsupported.

Installed-runtime and V comparisons pass ASAN/UBSAN in both hash-seed modes:
thirteen StaticString and eleven String cases cover Unicode, empty/NUL values,
15/16-byte boundaries, guarded read-only storage, flags 0/1 and UInt32 line
limits. Child handlers observe actual SIGTRAP; a returning test target exits 99,
so the adapter cannot manufacture the expected trap. Eight concurrent resolvers
publish one canonical RX page. Two drained runtime cycles prove its unmapping
and leave no Swift or ObjC owners. All eleven generated assertion runtime bodies
have no hidden V allocations; existing Int Hashable sanitizer checks still pass.

All twenty-five native guest checks and the full four-core ARM64
C++/UIKit/GLES/PPSSPP regression pass. Six more strong imports resolve across
the three images. An initial run exited 73 in the existing stdio directory
fixture; the unchanged rerun passed, and both serial logs are retained. Fortnite
then exited with status 1 before entry at EOSSDK's generic
string-interpolation append overload,
`_$ss26DefaultStringInterpolationV06appendC0yyxs06CustomB11ConvertibleRzs20TextOutputStreamableRzlF`.
Assertion evidence is retained under `swift-fatal-checks`.

The dual-constrained generic interpolation overload now dispatches the source's
actual `TextOutputStreamable.write` witness in V. Sealed ARM64 adapters forward
the measured source/target metadata and tables, preserve Swift's context register
and hold no registry lock across callbacks. Frozen interpolation metadata has one
String field at offset zero and reuses String's non-POD value witnesses. Its
canonical `TextOutputStream` descriptor and conformance supply all four methods.
The installed default lock/unlock bodies are single return instructions; the
generic ASCII default creates a String and calls the supplied target's write
witness, supporting a target that retains the result.

The constructor checks capacity arithmetic and reserves native-tail String
storage. Literal append and `String.append` borrow their inputs, grow byte
capacity, preserve UTF-8 and embedded NUL, reuse unique storage and copy retained
aliases. Self-append handles overlap and finishes copying before releasing the
old owner. String buffers have their own registry and measured count/flags and
capacity header, distinct from UTF-8 Array storage. Their private descriptor
does not implement Swift class metadata or reflection.

Installed-library and V interpolation, existing String storage, String metadata
and String protocol suites pass ASAN/UBSAN in both seed modes. Cases cover small
and large boundaries, negative/overflowing hints, real heap String input and its
stream witness, all four stream requirements, an ASCII default whose retained
output survives overwriting the source buffer, and arbitrary source tables.
Reentrant workers verify callback context and locking. Eight resolvers publish
one sealed arena; two drained cycles leave no owners and prove it unmapped.
Eleven generated runtime bodies have no hidden V allocations on valid paths;
registered storage and rejected-input Result errors are the explicit allocations.
Existing Int, Array and assertion bodies remain allocation-free.

All twenty-six native V checks and the full four-core ARM64
C++/UIKit/GLES/PPSSPP regression pass. Eight more strong imports resolve across
the executable and EOSSDK.

The interpolation layer's Fortnite probe stopped before entry at EOSSDK's
uninitialized Array allocator, `_$ss27_allocateUninitializedArrayySayxG_BptBwlF`,
with exit status 1.
Interpolation evidence is retained under `swift-interpolation-checks`, including
native measurements of that next allocator's ABI and typed/empty storage.
Unconstrained interpolation, other associated-type manglings, Hasher metadata,
additional conformances, runtime-wide conformance discovery and arbitrary
application Swift heap classes remain incomplete.

The uninitialized Array allocator now resolves in V. It accepts complete
value-element metadata, returns an owner and aligned element pointer, and
checks count, size, stride, alignment and allocation overflow before allocating.
The measured 32-byte header records the live element count and exact capacity.
One sealed, canonical empty owner is immortal and never unique. Its zero-length
element pointer follows the native header-offset rule even for over-aligned types.
The implementation follows the installed SDK's Array allocation/adoption contract
and [Swift's value witness flags](https://github.com/swiftlang/swift/blob/swift-6.3-RELEASE/include/swift/ABI/MetadataValues.h).

Typed storage has its own registry. Last release marks it deinitializing and
removes the entry before dropping the lock and invoking each non-POD Element's
actual destroy witness in element order. Storage stays alive until every witness
returns. Array aliases retain their shared storage without copying elements;
String and nested Array elements release their real owners. A cleared live count
allows an uninitialized allocation to be discarded without destroying its tail.
Private storage descriptors do not implement Swift class metadata, reflection,
casts or ObjC bridging. Class and class-constrained elements reject explicitly.

Native-library and V typed Array tests, existing String ARC, Array metadata and
interpolation suites pass ASAN/UBSAN in both seed modes. Cases cover empty and
zero-sized values, POD, Unicode/NUL and owned String tails, foreign String owners,
nested Arrays, retained aliases, alignments through 256, invalid/incomplete
layouts and count/refcount overflow. Custom destroy callbacks wait for another
resolver worker, eight workers allocate concurrently, and two drained runtime
cycles leave no owners and prove the empty mapping unmapped. Seven generated
allocation/ARC bodies have no hidden V allocations on valid paths. Explicit
storage and registry allocations are owned; rejected-input Result errors box.

The typed Array Fortnite probe gets past the allocator import and exits with status
1 before entry at EOSSDK's `CVarArg` protocol descriptor, `_$ss7CVarArgMp`.
Evidence is retained under `swift-array-storage-checks`, including native
measurements of that descriptor, Int's conformance/witness and the forty-byte
`CVarArg` existential layout. Verification helpers keep assertions enabled;
a deliberate failing assertion confirms that they reject failures with this
Mac's compiler, whose production mode removes assertions.

All twenty-seven native guest checks pass in both full regression attempts.
The broader regression then fails in the existing concurrent permissions fixture:
first `chmod` reports ENOENT (status 768), then duplicate `symlink` unexpectedly
succeeds (status 512). A comparison using the previously published runner hits
a poisoned kernel pointer in `fs__reduce_node_on_mount` during the file-time
check, before reaching the new allocator test. Full regression has not passed.
All three serial/config logs and VM image hashes are retained. The new runner
binaries remain in the evidence directory; the five published runners retain
their previous verified hashes pending a passing full regression.

V now supplies the sealed `CVarArg` protocol descriptor, its requirement aliases,
Int's concrete conformance/witness table and `_cVarArgEncoding` getter. The
getter preserves every signed Int bit in an owned, one-element typed Array.
Witness calls borrow indirect Self in x20; generic dispatch forwards the actual
table requirement, metadata and context. Generic dispatch also works with an
arbitrary supplied getter witness.

Installed-library and V CVarArg tests pass ASAN/UBSAN in both seed modes,
alongside the existing Int Hashable/value-witness and typed Array suites.
Tests cover native descriptor aliases, direct/witness/generic calls, Array
retained aliases, distinct callback dispatch, preserved contexts, a callback
waiting for another resolver, eight workers and two drained/unmapped runtime
cycles. The getter and descriptor emitter have no hidden V allocations.
Existential metadata, conformance discovery, va_list construction and
Foundation/String CVarArg support remain unimplemented.

All thirty-one programs rebuild, and the thirteen Swift ABI guest checks pass
in the focused mode. The actual Fortnite probe gets past `CVarArg` and exits
with status 1 before entry at EOSSDK's empty-tuple metadata import, `_$sytN`.
Evidence is retained under `swift-vararg-checks`, including native measurements
of Void's full-metadata export/address point, zero-sized witnesses and enum
storage boundaries for the next implementation step. Two host ENOSPC staging
failures occurred before QEMU and are recorded separately from guest results.
The broader regression failures above still hold publication; the five
published runners retain their last passing hashes.

V now supplies Void's `_$sytN` full metadata header. Its empty-tuple address
point is eight bytes after the export, with kind `0x301`, zero elements and
null labels. The canonical read-only page carries zero-size, stride-one POD
value witnesses. Copy, take, assignment and destruction touch no value bytes;
single-payload enum witnesses use the native one/two/four-byte tag boundaries,
including the installed runtime's UInt32 overflow at `UINT32_MAX` empty cases.
Dynamic tuple metadata construction remains unimplemented.

Installed-library and V Void tests pass ASAN/UBSAN in both seed modes, alongside
the existing typed Array suite. Tests inspect actual read-only permissions,
exercise null/protected addresses, unaligned tags and protected page boundaries,
verify `Array<Void>` and nested Array alias ownership, and run eight workers
and two drained/unmapped runtime cycles. Generated witnesses and metadata
construction/retirement contain no hidden V allocations. All thirty-two
programs rebuild, and all fourteen Swift ABI guest checks pass.

The Void probe resolved the empty tuple and exited with status 1 before
entry at EOSSDK's `__swift_stdlib_operatingSystemVersion` import. Evidence is
retained under `swift-void-checks`, including native measurements of that next
entry's indirect 24-byte return ABI. Full regression remains unpassed and the
five published runners retain their last passing hashes.

V now supplies `__swift_stdlib_operatingSystemVersion` using the existing iOS
17.0 device profile, matching this IPA's minimum OS version. The ordinary
ARM64 C ABI returns three signed pointer-sized fields in exactly 24 bytes
through x8. `UIDevice.systemVersion` reads the profile's static text, and the
Swift query returns 17.0.0 independently of the host OS. The getter needs no
allocation, cache, lock or runtime arena.

Installed-library and V version tests pass ASAN/UBSAN in both seed modes.
Native results agree with this Mac's sysctl; V results agree with UIDevice.
Direct calls and a raw x8 probe verify guards, a protected page boundary,
preserved Swift context/errno, concurrent resolution and eight query workers.
Calls also work before initialization and after two drained runtime cycles.
All thirty-three programs rebuild, and all fifteen Swift ABI guest checks pass.

The version probe exited with status 1 before entry at EOSSDK's
`__swift_stdlib_reportUnimplementedInitializerInFile` import. Evidence is retained
under `swift-version-checks`, including native measurements of that reporter's
ordinary C ABI, bounded diagnostic and successful return. Full regression
remains unpassed and the five published runners retain their last passing hashes.

V now supplies `__swift_stdlib_reportUnimplementedInitializerInFile` and
`__swift_stdlib_reportUnimplementedInitializer`. Both use the ordinary C ABI,
with signed 32-bit byte lengths and unsigned 32-bit line/column/flags. They
print the measured diagnostic and return; the Swift initializer caller performs
termination separately. Text is borrowed, bounded by its supplied length and
stopped at its first NUL. The file variant prints the unsigned line number
without the column, matching this Mac's library. Flags leave stderr unchanged;
host debugger crash annotations and backtraces remain unimplemented.

Installed-library and V reporter tests pass ASAN/UBSAN in both seed modes.
Twenty cases compare both exact diagnostics through direct calls and raw ARM64
adapters, including empty/NUL/Unicode text, read-only spans ending at protected
pages, zero-length protected addresses, poisoned upper argument halves and
UInt32 line/flag boundaries. Both return with broken stderr and preserve Swift's
context. V rejects negative lengths and null unsafe inputs before reading them.
Eight reporting/resolution workers, calls before initialization and two drained
runtime cycles need no Swift owners or arenas. Generated diagnostic bodies have
no hidden V allocations, locks or traps. All thirty-four programs rebuild, and
all sixteen Swift ABI guest checks pass.

The initializer probe now exits with status 1 before entry at EOSSDK's
`_swift_allocObject` import. Evidence is retained under `swift-initializer-checks`,
including native heap-class metadata, allocation/deallocation/type/ARC
instructions and eighteen aligned allocations with measured header/refcount
transitions and real Array storage destruction. Heap-class allocation and ARC
were unimplemented at that probe. Full regression remains unpassed, and the five
published runners retain their last passing hashes.

V now supplies `_swift_allocObject`, `_swift_deallocObject`,
`_swift_deallocClassInstance` and `_swift_deallocUninitializedObject`. Native ARC
classes and heap-local/generic contexts use real borrowed heap metadata,
aligned storage and the measured two-word header initialized to three.
Stored properties remain uninitialized until Swift constructs them. Final
strong release marks the owner deinitializing before calling the metadata's
deallocating destructor with self in x20. That destructor frees its own object
through the deallocation entry; constructor-failure deallocation skips it.

The registry checks allocation layout and tracks deinitialization and allocation
generations under the runtime lock. Destructors run unlocked and can release
children, wait for another resolver thread, or allocate again after freeing self.
The outer release checks the generation without reading freed owner bytes.
Strong/batch/bridge/unknown ARC uses the existing synchronized ownership paths;
plain ARC preserves x9–x15 and x20 through final destruction. Metadata and sealed
thunks stay alive until all owners drain. Weak/unowned/side-table ownership,
further ARC during deinitialization, ObjC-counted classes, nonzero instance
prefixes, reflection/casts and other heap runtime exports remain unsupported.

Installed-library and V heap, String and typed Array suites pass ASAN/UBSAN in
both seed modes. Heap checks cover 54 aligned layouts, initialized/uninitialized
ownership, child destruction, reentrant callbacks and address reuse, eight
allocation and shared-owner workers, invalid layouts/states and two drained
runtime cycles. Generated successful paths have no hidden V temporaries;
aligned storage and registry capacity are explicit allocations. Failure-only
V error boxes are accounted for separately. All thirty-five programs rebuild,
and all seventeen Swift ABI guest checks pass. Two host fixture mistakes and
an obsolete guest assertion that allocation must remain unresolved are retained
with their corrections and passing final results under `swift-heap-checks`.

The heap probe now exits with status 1 before entry at EOSSDK's
`_swift_errorRelease` import. Native measurements of that next entry and
`_swift_errorRetain` show ordinary C calls using Objective-C ownership, including
real CFError reference counts and final domain disposal. Full regression remains
unpassed, and the five published runners retain their last passing hashes.

V now supplies `_swift_errorRetain` and `_swift_errorRelease` through the existing
Objective-C ownership functions, matching Darwin's ordinary C error ARC ABI.
Error retain returns the same owner; final release runs the existing dealloc,
weak-slot and owned-field cleanup. These exports add no Swift arenas, allocation
registries or ARC adapters. Native Swift error boxes remain unsupported;
the CFError extraction support below adds concrete Error protocol witnesses.

Installed SwiftCore and V error ARC, String and typed Array suites pass
ASAN/UBSAN in both seed modes. Error checks cover real native CFErrors, reference
count transitions, four signed error codes, separately retained domains surviving
final error destruction, and raw ARM64 calls preserving x20/x21 through dealloc.
Eight creation and shared-owner workers pass. V checks also verify weak zeroing,
owned-child disposal, reentrant destruction, a resolver thread awaited inside
dealloc, nil calls before/after initialization and two drained runtime cycles.
Generated ownership bodies introduce no hidden V allocations. All thirty-six
programs rebuild, and all eighteen focused Swift ABI guest checks pass.

The error ARC probe exits with status 1 before entry at EOSSDK's
`_swift_getErrorValue` import. Evidence is retained under `swift-error-checks`,
including 256 native CFError extraction calls with guarded scratch/output words,
borrowed owner references, stable genuine type metadata and Error witnesses,
and unchanged reference counts. Native boxed Swift error values remain
unmeasured. A corrected host fixture header conflict is preserved with the
passing results. Full regression remains unpassed, and the five published
runners retain their last passing hashes.

V now supplies `_swift_getErrorValue`, `_swift_getObjCClassMetadata`, Error's
`_$ss5ErrorMp` descriptor and all four requirement-descriptor aliases. Extraction
borrows a live VinixCFError into caller scratch and returns that address, its
canonical type metadata and a complete Error witness table. The four witnesses
return an owned domain String, signed code, owned user-info dictionary and owned
embedded error. Long domain text is copied into owned Swift storage so it remains
valid after the error and its NSString are destroyed. Native Swift error boxes,
arbitrary NSError subclasses and general conformance discovery remain unsupported.

Objective-C class metadata uses sealed wrapper kind `0x305`, the actual registered
class pointer and a complete eight-byte reference value witness table. Swift
classes retain their existing metadata address point, and null class lookup
returns zero. Copy assignment retains before publishing; both assignments publish
before releasing the old owner, allowing its destructor to reenter. The cache
publishes under the runtime lock and retires its mappings before classes are
freed at quiescent teardown. Explicit disposal of a class with published wrapper
metadata is rejected while those borrowed metadata addresses may remain in use.

Installed SwiftCore and V extraction, error ARC and String metadata suites pass
ASAN/UBSAN in both hash modes. Extraction checks cover native descriptor aliases,
guarded output words, borrowed counts, signed codes, UTF-8 and embedded NUL domains,
user-info contents surviving final error release, all four Swift-context witnesses,
pointer value ownership and preserved x20/x21. V checks also exercise unlocked
reentrant assignment, eight concurrent metadata publishers, eight shared-owner
extraction workers, explicit invalid/unsupported inputs and two drained/unmapped
runtime cycles. An artificial class flag tests metadata forwarding; it does not
establish native Swift class allocation support. Generated C checks distinguish
explicit metadata/storage allocations from failure-only V error boxes.

All thirty-seven programs rebuild, and all nineteen focused Swift ABI guest
checks pass. The actual IPA now exits with status 1 before entry at EOSSDK's
`_swift_getObjectType` import. Native measurements of that next entry verify
canonical metadata for genuine CFError, string and dictionary owners, unchanged
reference counts, ordinary C calls and preserved x20/x21. Evidence is retained
under `swift-error-value-checks`. Full regression remains unpassed after the
previously preserved kernel/concurrent-filesystem failures, and the five
published runners retain their last passing hashes.

V now supplies `_swift_getObjectType` for registered Objective-C instances,
registered constants and supported Swift nominal class allocations. Lookup
borrows the owner without changing reference counts. Objective-C instances
initialize their class and honor an overridden `-class` method, called with
the canonical selector outside the registry lock. The returned class must be
registered instance metadata. Swift classes return their existing metadata
address point; Objective-C classes share the sealed `0x305` wrapper cache.
Unknown, destroyed, tagged and nil owners, class/metaclass objects, blocks,
heap contexts, private String/Array/UTF8 descriptors and artificial Swift
subclasses with null nominal descriptors are explicitly unsupported.

The object-type host fixture passes ASAN/UBSAN in both hash modes. Installed
SwiftCore supplies genuine CFError, string and dictionary owners and a real
`ContiguousArrayStorage<Int>` class. A Vinix heap allocation against that native
class returns identical metadata, then deallocates uninitialized storage.
Raw ARM64 calls preserve x20/x21 and guarded output words. V checks cover eight
first-publication readers, canonical metadata after `object_setClass`, constant
storage, a formal-class callback waiting for another metadata worker, canonical
`_cmd`, caller construction before `+initialize`, the Swift class fast path,
borrowed lookup during Objective-C and Swift deallocation, protected/freed
storage rejection and two drained/unmapped runtime cycles. The full class-layout
fixtures are distinct from the genuine native Swift allocation comparison.

All thirty-eight programs rebuild, and all twenty focused Swift ABI guest
checks pass. Generated C verifies owner lookup before storage access, unlocked
formal-class dispatch, shared sealed metadata and no hidden successful V
allocations. The actual IPA still exits with status 1 before entry, now at
EOSSDK's `_swift_getTypeByMangledNameInContext` import. Native measurements of
that next lookup return canonical Int, String, Void and Array<String> metadata
through guarded direct/raw calls preserving x20/x21. Its declaration and
context substitution are also recorded from the
[Swift runtime source](https://github.com/swiftlang/swift/blob/main/stdlib/public/runtime/MetadataLookup.cpp).
Generic contexts, symbolic references and invalid names remain unmeasured.
Evidence is retained under `swift-object-type-checks`; full regression remains
unpassed, and the five published runners retain their last passing hashes.

V now supplies bounded `_swift_getTypeByMangledNameInContext` lookup for `Int`,
`String`, `Void`, nested Arrays, Objective-C class names and direct/indirect
relative references to nongeneric class, struct and enum descriptors. Metadata
comes from the existing canonical caches or the descriptor's borrowed accessor;
lookup adds no metadata arena, owner registry or reference count changes.
Binary symbolic offsets may contain zero bytes. Parsing respects the supplied
length, checks the complete supported expression before invoking an accessor,
and requires a complete metadata response. Borrowed accessors run outside the
runtime lock. Generic substitution currently supports `x` in Array's canonical
one-type-parameter context, including `Array<x>`.

Installed SwiftCore and Vinix pass the mangled-name fixture under ASAN/UBSAN in
both hash modes. Tests compare canonical pointers and raw ARM64 calls preserving
x20/x21, including exact byte spans ending at a protected page, embedded zeros,
nested Arrays, class wrappers and relative nominal accessors. V checks cover
unlocked accessor reentry through another worker, incomplete response rejection,
eight concurrent readers and two drained runtime cycles. Missing generic
arguments and nongeneric contexts return null in the installed runtime and
Vinix. Earlier fixture failures from a reserved identifier and a one-character
C literal used as a pointer are retained; corrected fixtures pass.

The framework inventory records eight calls to EOS's cached lookup helper with
null context. Those calls request `ScPSg` (Optional<TaskPriority>) or a
`CVarArg` protocol existential; both remain unsupported. Its type-reference
section also contains `Int` and nominal class/enum references.
MarketplaceKitWrapper's records are retained as well. Protocol, opaque,
function, Optional and other compound types, general nominal name lookup,
additional generic contexts and witness substitution remain unsupported.
Empty or truncated supported expressions, missing classes and unavailable
generic arguments return null; other unsupported expressions fail explicitly.

All thirty-nine programs rebuild, and all twenty-one focused Swift ABI guest
checks pass. Generated C verifies bounded reads, borrowed class-name keys,
complete responses, unlocked accessor calls and no hidden successful V
allocations. The actual IPA now exits with status 1 before entry at EOSSDK's
`_swift_getWitnessTable` import. Installed SwiftCore measurements of that next
ordinary C entry return canonical static Int Hashable/Equatable and String
Hashable tables in 768 guarded raw and 768 direct calls preserving x20/x21.
Generic, conditional and resilient witness lookup remains unmeasured. The
remaining EOS type queries have native layout measurements: TaskPriority uses
one byte, its Optional uses two, and the CVarArg existential uses forty.
These measurements do not establish value ownership or concurrency execution.
Evidence is retained under `swift-mangled-checks`; full regression remains
unpassed and the five published runners retain their last passing hashes.

V now supplies the ordinary C `_swift_getWitnessTable` entry for unique,
unconditional static conformances. It returns the borrowed relative pattern,
including a null pattern, without reading metadata, instantiation arguments,
protocol/type references or table contents. Signed offsets work in both
directions. Lookup adds no cache, allocation, arena or reference count changes;
descriptors and tables remain owned by their images or existing metadata arenas.
Caller descriptors must stay readable and immutable while used. Unsupported
flags, null/misaligned/overflowing descriptor addresses and misaligned patterns
fail explicitly. Generic, conditional, resilient and non-unique foreign tables are
rejected rather than returning an uninstantiated pattern.

Installed SwiftCore and V pass this fixture under ASAN/UBSAN in both hash modes,
alongside String protocol dispatch and Int Hashable/Equatable suites. Tests
compare canonical Int and String tables, preserve x20/x21 through guarded raw
calls and place descriptors exactly before protected pages. Unused inputs and
table bodies may be unreadable. Eight readers and two drained cycles pass.
Generated C checks flags before pattern reads and confirms no successful hidden
allocation or ownership operation.

The framework inventory identifies EOS's three AppDistributorType conformances
to Equatable, Hashable and RawRepresentable. All have flags `0x30000`, null
patterns, zero template words and resilient requirements. These need actual
instantiation, which remains unsupported. MarketplaceKitWrapper contains the
same conformances and two non-unique ActivationState conformances. Fifteen
lookup call sites and their records are retained. A separate native synthetic
probe measures allocation from a null pattern, placement of an out-of-order
witness, default and null-default witnesses, and private-cache reuse across 256
lookups. Base protocols, associated witnesses and instantiation callbacks still
need measurements. The corresponding
[Swift runtime instantiation source](https://github.com/swiftlang/swift/blob/main/stdlib/public/runtime/Metadata.cpp)
is retained with the ABI declarations.

All forty programs rebuild and all twenty-two focused Swift ABI guest checks
pass. The supplied IPA still exits with status 1 before entry, now at EOS's
`_swift_once` import. Native measurements of that next ordinary C entry use
sixteen static tokens with eight concurrent readers each; all observe both
callback writes exactly once. Another 2,048 completed-token raw calls preserve
x20/x21. The observed nonzero token words are consistent with libdispatch's
epoch handling; an initial fixture incorrectly assumed every completed token
was `-1` and used a local token. Its failure is retained, and the corrected
fixture uses static storage as required by the
[Swift declaration](https://github.com/swiftlang/swift/blob/main/include/swift/Runtime/Once.h).
At that stage this next entry was unimplemented. Evidence is retained under
`swift-witness-checks`; full regression remains unpassed, the five published
runners retain their last passing hashes, and playable Fortnite compatibility
is still unverified.

V now implements `_swift_once` with the ordinary C predicate/function/context
argument order. Its callback receives a borrowed context in x0. The adapter
uses dispatch's existing per-token mutex map, release publication and shutdown
cleanup. A shared helper preserves dispatch-once's original argument order and
`-1` convention. The global runtime lock is released before calling an
initializer, allowing nested independent tokens and callbacks that join work
on another thread. Same-token recursion fails through the inherited
error-check mutex; cancellation and callbacks that do not return remain
unsupported. Tokens must be aligned, zero-initialized words with static extent.
The supplied frameworks' six call sites use three such tokens in `__bss`.

Swift's Darwin compiler fast path can skip the runtime after a barrier-free
load of `-1`. Vinix does not implement Darwin's global quiescence protocol,
so the adapter publishes the opaque completed word `2`. Compiled callers
therefore continue through its acquire load before reading initialized data.
This preserves publication ordering at the cost of a runtime call on completed
tokens. An already completed token needs no writable storage, valid callback,
readable context or running runtime. Precompleted `-1` tokens are also accepted.
Null, unaligned and overflowing token addresses, missing callbacks during
initialization and initialization outside the runtime lifetime fail explicitly.

The installed SwiftCore and V pass the same fixture under ASAN/UBSAN in both
hash modes. Sixteen tokens each have eight readers that observe both callback
writes exactly once through an emitted Darwin compiler fast path. Counters
verify that V's completed tokens still enter the acquire adapter. Guarded raw
initialization and 2,048 completed calls preserve x20/x21; x0 is ignored for the
void return. Nested callbacks, independent thread joins, null contexts,
unreadable completed callbacks/contexts and read-only boundary tokens pass.
Two additional dispatch tokens retain their original behavior. The shared
cache contains exactly twenty-two entries per runtime cycle, all workers join
before shutdown, and two cycles drain it. Completed calls after teardown add
no owner. Static witness lookup and the existing dispatch suite also pass host
sanitizers. Generated C confirms the acquire/release order, unlocked callback,
existing teardown and no successful hidden allocation or ARC in the adapter.

All forty-one programs rebuild and all twenty-three focused Swift ABI guest
checks pass. The IPA still exits with status 1 before entry, now at EOS's
`_$s10ObjectiveC22_convertBoolToObjCBoolyAA0eF0VSbF` import from
`libswiftObjectiveC.dylib`. Native measurements of both Boolean conversions
preserve x20/x21 and return canonical 0/1 for valid input values. The retained
ARM64 Mac SDK interface defines frozen `ObjCBool` with Swift `Bool` storage,
and both measured native exports mask bit 0. The Mac Catalyst interface instead
uses `Int8` storage and a nonzero comparison. These target differences are
retained; the iOS conversion ABI still needed verification at that checkpoint. A failed initial probe
assumed any nonzero byte meant true; its source, output and status are retained.
Additional raw-bit observations are not a contract for malformed Boolean
values. Those conversions were still unimplemented. Evidence is retained under
`swift-once-checks`; full regression remains unpassed, the five published
runners retain their last passing hashes, and gameplay remains unverified.
EOS resilient witness instantiation, `Optional<TaskPriority>` and `CVarArg`
existential metadata also remain unsupported.

V now implements both Swift Objective-C Boolean conversion imports,
`_$s10ObjectiveC22_convertBoolToObjCBoolyAA0eF0VSbF` and
`_$s10ObjectiveC22_convertObjCBoolToBoolySbAA0cD0VF`, through
`/usr/lib/swift/libswiftObjectiveC.dylib`. They receive the scalar Boolean in
`x0` and return canonical 0/1 in `x0`, preserving Swift context/error registers.
The [Swift 5.0 overlay source](https://github.com/swiftlang/swift/blob/swift-5.0-RELEASE/stdlib/public/SDK/ObjectiveC/ObjectiveC.swift)
explicitly gives ARM64 iOS `ObjCBool` Boolean storage; the current Apple Clang
iOS 17 target macros and SDK Objective-C header agree on real `BOOL`.
Installed ARM64 Mac exports and their Swift interface use the same Boolean
representation. The Catalyst Swift interface uses signed-byte storage and is
retained separately; the adapter does not implement its nonzero-byte semantics.
This combines source, compiler and real caller evidence, without claiming an
iOS device runtime comparison. EOS has four conversion calls and Marketplace
one; retained assembly shows bit-0 masking around Boolean callers.

Native Mac and V conversion fixtures pass ASAN/UBSAN in both hash modes,
alongside the existing static witness and dispatch suites. Each conversion
sweeps 256 upper-register patterns for valid 0/1 values, checks canonical results
and round trips, and makes guarded raw calls preserving `x20`/`x21`. V resolves
only the two exact overlay symbols, rejects wrong libraries and unsupported
metadata/conformances, and passes before startup and before/during/after two
runtime cycles. These entries allocate no owner, cache or metadata arena;
generated C verifies scalar signatures, masking and absence of allocation or
ARC operations. Invalid Boolean byte patterns are not additional supported
values. At this stage, `ObjCBool` metadata and `NSObject: Hashable` remained unsupported;
ObjCBool metadata and NSObject conformances were implemented in the later steps below.

All forty-two programs rebuild and all twenty-four focused Swift ABI guest
checks pass. The supplied Fortnite probe passes the conversions and next exits
while linking EOS at `_$sScA15unownedExecutorScevgTj`, the Swift concurrency
`Actor.unownedExecutor` getter dispatch thunk. Native export disassembly,
demangled names, the installed concurrency interface, official Actor/Executor
sources and actual EOS call sites are retained for further measurement. Actor
dispatch, executor identity/ownership and scheduling remain unimplemented.
Evidence is retained under `build/ios/fortnite/swift-objc-bool-checks`, including
verified lossless generated C archives and original byte hashes. Full regression
remains unpassed, all five published runners retain their last passing hashes,
and Fortnite still exits before entry; gameplay remains unverified.

V now resolves the concurrency imports
`_$sScA15unownedExecutorScevgTj` (`Actor.unownedExecutor` dispatch) and
`_$sScP8rawValues5UInt8Vvg` (`TaskPriority.rawValue`). The actor dispatcher
reads only witness-table word 1, then tail-calls the caller's getter with
metadata in `x0`, table in `x1` and borrowed self in `x20`. It forwards the two
opaque executor words in `x0`/`x1` without choosing an executor or changing
ownership. Vinix uses ordinary ARM64 pointers; the native Mac comparison signs
its fixture witness with the measured arm64e discriminator 26998. The priority
getter receives indirect self in `x20`, reads exactly one byte and returns
canonical `UInt8` in `x0`. The installed interface does not freeze `TaskPriority`;
the actual EOS and Marketplace callers also use indirect self.

Native Mac and V fixtures pass ASAN/UBSAN in both hash modes, alongside the
existing witness and hashing suites. Protected pages independently guard the
witness descriptor, table tail and metadata; read-only tables pass. All 256
priority bytes pass, including a byte immediately before a protected page.
Guarded calls preserve `x20`/`x21`, executor words and borrowed fixture owner
counts. Eight resolvers publish one completed RX page, eight independent workers
dispatch through it, and a getter callback joins a resolver thread. Two runtime
cycles join calls before unmapping, clear the page and reject later resolution.
Unsupported imports allocate no page. Generated C confirms sealing before
publication, failed-seal cleanup, retirement and no hidden successful allocation
or ARC. These fixtures test protocol forwarding; they do not construct genuine
actors or run a scheduler.

All forty-three programs rebuild and all twenty-five focused Swift guest checks
pass. The two entries resolve six strong imports across the three images. The
actual Fortnite probe now exits with status 1 before entry at EOS's `_$sScPMa`,
the `TaskPriority` metadata accessor. Retained native measurements make 768
guarded accessor calls across blocking/nonblocking complete, layout and abstract
requests: one canonical struct metadata pointer, complete response state, size
and stride one, and preserved context/error registers. Actual EOS and Marketplace
call sites and the [official metadata request definitions](https://github.com/swiftlang/swift/blob/main/include/swift/ABI/MetadataValues.h)
are retained. Priority metadata/value witnesses, `Optional<TaskPriority>`, actor
creation, executor ownership, task scheduling, EOS resilient witness instantiation
and further dependencies remain unsupported. Evidence is under
`build/ios/fortnite/swift-actor-executor-checks`; generated C and completed parent
build artifacts are retained as verified lossless gzip with original hashes and
manifests. Full regression remains unpassed, the five published runners retain
their last passing bytes, and gameplay remains unverified.

V now also resolves `_$sScPMa`, `_$sScPMn` and `_$sScPN`: the canonical
`TaskPriority` accessor, nominal descriptor and direct metadata exports. The
installed Mac Swift runtime reports struct kind `0x200`, field offset zero,
size/stride one, POD flags `0x02000000`, no extra inhabitants and the module
name `Swift`. One runtime arena supplies an RX accessor page and a read-only
metadata/value-witness page. The accessor returns complete metadata for all
measured request modes, preserving `x20`/`x21`. Copy, take and assignment read
and write exactly one byte; destruction touches no storage. Single-payload
enum witnesses reproduce the measured tag-width boundaries and UInt32 wrap.
The bounded type parser recognizes `ScP` and nested Arrays of TaskPriority.

The installed native runtime and V fixtures pass ASAN/UBSAN in both hash modes,
alongside the existing static witness and hashing suites. Guard pages cover
byte values, unaligned enum tails and an exact non-NUL `ScP` span. Tests check
all 256 payload bytes, accessor requests through both exports and descriptor
references, nested Array ownership, eight concurrent resolvers/workers, and two
drained runtime lifetimes. Unsupported Optional, conformance and malformed type
expressions reject before allocating metadata. Generated C audits verify both
page protections before publication, failed-seal cleanup, retirement and no
hidden successful allocation or ARC in the new witnesses. Reflection field
records, TaskPriority conformances, Optional metadata, actor creation, executor
ownership and task scheduling remain unsupported. This compares installed Mac
Swift and actual IPA callers; it does not claim an iOS device runtime comparison.

All forty-four programs rebuild and all twenty-six focused Swift guest checks
pass. The new exports resolve three strong imports and one weak import across
the supplied images. Fortnite passes them and next exits with status 1
before entry at EOS's `_swift_task_alloc`. Native export disassembly and actual
framework call sites (21 in EOS and 31 in Marketplace) are retained for
task-allocation ABI work. Evidence is
under `build/ios/fortnite/swift-task-priority-checks`. The initial host ENOSPC
build and compression failures are preserved; the retry joins every compiler,
linker and generated-C audit before lossless compression. Completed parent
artifacts and proof ancestry are also verified after recompression. Temporary
VM payloads use the mounted test volume and are retired after joined runs;
logs, configuration and hashes remain accessible from the evidence directory.
Full regression remains unpassed and the five published runners keep their
last passing bytes. Fortnite still has not entered gameplay.

V also resolves `_swift_task_alloc` and `_swift_task_dealloc` for Swift's
no-active-task fallback. The installed Mac runtime uses one shared allocator
across threads; its API requires 16-byte alignment and strict LIFO lifetimes.
The implementation uses an explicit aligned allocation with a private
16-byte linked header and a rounded, uninitialized payload. Zero-byte requests
return distinct aligned pointers. Bounds checks precede allocation; frees
compare with the registered stack top before reading a header, unlink before
freeing, and reject null, foreign, interior, non-top and repeated pointers.
Shutdown refuses a live allocation stack. Task creation, current-task switching,
task-private allocators and scheduling remain unsupported.

Standalone native measurements pass before the runtime comparison. Native and
V fixtures cover 28 nested sizes from zero through 1,048,577 bytes, writable
nonoverlapping payloads, reverse frees, eight serialized worker sequences and
cross-thread LIFO transfer. Raw ARM64 probes preserve borrowed `x20`/`x21`/`x22`
even when they point into protected storage. The allocator, priority and actor
suites pass six actual ASAN/UBSAN processes across both hash modes. V checks
also cover rounded tails, overflow rejection, invalid frees without mutation,
refused live drain, 512 zero/small allocation pairs per lifetime, concurrent
canonical resolution and two drained runtime lifetimes. Resolution needs no
executable adapter page or Swift owner. Generated C audits check explicit
allocation/free and reject hidden successful allocations or ARC operations.

Evidence is under `build/ios/fortnite/swift-task-alloc-checks`, including the
52 pinned framework allocation calls, installed native export disassembly,
probe encoding and hashed official Swift
[task allocation](https://github.com/swiftlang/swift/blob/main/stdlib/public/Concurrency/TaskAlloc.cpp)
and [stack allocator](https://github.com/swiftlang/swift/blob/main/stdlib/public/runtime/StackAllocator.h)
sources. The preceding proof's serial logs and configuration were recovered
byte-for-byte from archived evidence after the external test volume unmounted;
that proof verifies again. New temporary VM payloads use local storage and are
retired after joined checks. These measurements keep the native current task
nil and do not create tasks or invoke a scheduler.

All forty-five programs build, and all twenty-seven focused Swift checks pass
in the Vinix guest. The first IPA probe preparation and binary-compression
attempts encountered host ENOSPC; their joined failures, overlay and incomplete
archive hash are preserved. Completed binaries and generated C are retained as
verified lossless gzip with original byte hashes before retrying the probe.
The successful retry passes both allocation imports and exits with status 1
before entry at EOS's `_swift_task_create`. Its native export and six actual
call sites (two EOS, four Marketplace) are retained for further measurement;
the task-creation ABI has not been invoked. Both import audits resolve six
additional strong imports across the three images. Full regression remains
unpassed, candidates remain in the evidence directory, and the five published
runners retain their last passing bytes. Gameplay remains unverified.

V now implements `_swift_task_create`, `_swift_task_getCurrent` and
`_swift_job_run` for unstructured tasks on the generic executor. Creation
returns the task and its initial context as two words. The installed runtime
reports Task heap kind `0x502`, a 176-byte task header, the resume entry at
offset 56 and context at offset 64. Relative async descriptors supply the
entry and frame size. Sealed V-emitted adapters pass context in `x22`, closure
in `x20`, and a future's indirect result in `x0`; completion receives its
error argument in `x20`. Context/result allocation is aligned to 16 bytes.

Tasks carry one caller reference. Enqueue or an explicitly retained job run
adds the execution reference, released at completion. Current-task TLS is
installed for execution and restored on return. Running tasks use their own
LIFO allocation stack; a live fallback allocation stays unchanged while tasks
run. A consumed closure context is opaque and may point into protected storage;
creation and completion do not read or release it. Transferred heap closures
are released before clearing current-task TLS. Typed future results remain
alive until final task destruction, which calls their value witness. Failed
futures own and release a supported CFError instead of destroying a result.
Task names are copied from option records into task-owned storage.

The implementation uses an intrusive task registry in private header storage,
with no per-task V box or map. Registry removal precedes result destruction;
a disposal count protects unlocked destruction callbacks. A closure destructor
can join another resolver. Queued and executing callbacks drain before dispatch
shutdown, and callers must release task handles before metadata, TLS and
synchronization are retired. Early invalid descriptors, option cycles, custom
executors, structured/inline/immediate flags and premature destruction reject
without publishing a task. Enqueue requires a live dispatch scheduler.

Standalone native measurements create and execute twelve real tasks, use their
private allocators and complete integer futures. Native/V fixtures additionally
cover discarded, Int, String and Void futures, CFError failures, actual enqueue,
an exact protected eight-byte descriptor, opaque consumed contexts, transferred
closure ownership and eight workers. All eight final host sanitizer processes
pass in both hash modes; all forty-six programs build and all twenty-eight
focused Swift guest checks pass. Generated C audits check publication, explicit
allocations, unlocked callbacks, no task access after completion can free it,
and join/drain ordering. Initial fixture failures involving the Void metadata
address point and omitted dispatch initialization were corrected; the dispatch
failure's exact C, binary and status are retained.

Evidence is under `build/ios/fortnite/swift-task-create-checks`, including native
measurements, six pinned framework creation calls, opcode measurements and
hashed official Swift [task implementation](https://github.com/swiftlang/swift/blob/main/stdlib/public/Concurrency/Task.cpp)
and [ABI definitions](https://github.com/swiftlang/swift/blob/main/include/swift/ABI/Task.h).
Custom executors, task groups, async-let, native error boxes, cancellation,
future waiting, immediate/inline tasks and async suspension remain unsupported.
Task-local copying currently covers the empty state; no task-local APIs have
been implemented. This compares the installed Mac runtime with V and IPA
callers; it does not claim an iOS device runtime comparison.

The IPA probe now passes task creation and exits with status 1 before entry
at EOS's `_swift_task_switch`. Its native export and twenty framework call
sites (eleven EOS, nine Marketplace) are retained for suspension/executor work.
Both audits resolve three more strong imports across the supplied images.
Full regression remains unpassed, so these runners remain candidates and the
five published runners keep their last passing bytes. Host disk pressure was
handled with a private RAM volume; final compressed evidence is verified back
to persistent repository storage before that volume is detached.

V now implements `_swift_task_switch` for a running task switching to the same
generic executor (`0/0`). The native Swift async ABI passes the opaque frame
in `x22`, continuation in `x0`, and executor words in `x1/x2`. Native
disassembly and the official Swift
[executor implementation](https://github.com/swiftlang/swift/blob/main/stdlib/public/Concurrency/Actor.cpp)
show immediate tail resumption for this case. Vinix validates the current
registered task and its running phase, releases the runtime lock, restores the
bridge's stack frame, and tail-branches to the continuation. It keeps current
task TLS, execution ownership and saved resume slots unchanged; it neither
reads the opaque context nor allocates on the successful switch path.

Expanded inspection of all twenty framework calls found nineteen generic
switches and one dynamic Marketplace switch at `a500`. That call obtains its
executor from `Actor.unownedExecutor`; actor/custom executor switching and
actual suspension remain unsupported. Continuation bounds, foreign current
tasks, nonrunning phases and unsupported executor pairs reject before resuming.
This implementation covers the measured generic path, with further executor
work still required by the IPA.

Native and V fixtures complete 100,000 consecutive switches with constant C
stack usage, alternate between task-private frames, and resume an opaque
context in a protected page. They cover manual and queued jobs, discarded and
Int futures, completion that frees the final task reference, eight concurrent
workers, fallback allocator isolation and two drained V lifetimes. All eight
host sanitizer processes pass in both hash modes. All forty-seven programs
build. Generated C audits cover every runner/test module; all fifty-one original
C streams are retained with verified lossless compression.

All twenty-nine Swift checks pass in the Vinix guest. The first guest run
passed the preceding twenty-eight checks but could not execute the new test
because the Swift VM packaging list omitted it. The corrected harness passes;
the failed driver's exact source, statuses, guest payload and serial/config
are retained. The IPA now passes `_swift_task_switch` and exits with status 1
before entry at Swift Foundation's
`_$s10Foundation5NSLogyySS_s7CVarArg_pdtF`, demangled as
`NSLog(String, CVarArg...)`. Its native export and two EOS call sites are
captured without invoking that ABI. Both audits resolve three additional
strong imports. Evidence is under
`build/ios/fortnite/swift-task-switch-checks`; full regression remains unpassed,
the candidates stay there, and the five published runners retain their last
passing bytes. Gameplay remains unverified.

V now resolves Swift Foundation's `NSLog(String, CVarArg...)`,
`String._bridgeToObjectiveC()` and the String `CVarArg` conformance. The
measured logger takes String words in `x0/x1` and a borrowed Array in `x2`.
Each existential element occupies forty bytes, with concrete metadata and
its witness table at offsets 24 and 32. Vinix copies supported inline values
through their value witnesses, invokes the actual encoding getter with
borrowed Self in `x20`, concatenates its owned `Array<Int>` result as Darwin
stack words, then releases both the encoding and copied value. Format String
ownership stays pinned through callbacks. A getter can join another resolver.

String encoding bridges to a scoped autoreleased NSString; the standalone
String bridge returns a caller-owned NSString. A concrete specialization of
Foundation's retroactive String conformance has real relative protocol/type/
table/module records. It uses the existing witness lookup. A sealed two-page
arena holds the adapters and conformance, and is retired before the core
metadata it references. Logging writes a formatted UTF-8 message to stderr
from one explicitly owned buffer; temporary objects drain with its pool.

The native Mac and V fixtures compare String/Int and custom multiword encoding,
Unicode, percent escaping, empty arrays, caller-owned bridging, preserved
inputs and cleanup. Eight sanitizer processes pass in both hash modes, all
forty-eight programs build, and all thirty Swift guest checks pass. Generated
C audits cover the logging path and all fifty-two original C streams are
retained with verified lossless compression. The initial capture fixture used
V `int` pipe slots emitted as 64-bit by this compiler, while libc requires
32-bit slots; bounded captures and explicit `i32` slots corrected it. Its
exact failed fixture, C, binary and joined termination status are retained.

Evidence is under `build/ios/fortnite/swift-nslog-checks`, including the installed
native metadata/witness layout, expanded native export and both EOS call sites,
and hashed official Swift [varargs implementation](https://github.com/swiftlang/swift/blob/main/stdlib/public/core/VarArgs.swift)
and [metadata API](https://github.com/swiftlang/swift/blob/main/include/swift/Runtime/Metadata.h).
Only registered value Array storage and inline struct/enum CVarArgs are
supported, with at most 512 encoded words and 1 MiB of formatted output.
Boxed/reference values, general existential metadata creation, positional/star
formats, long doubles and object formatting beyond NSString remain unsupported.
The log destination follows Vinix's stderr convention; Apple's timestamp and
system-log routing are not implemented.

The supplied IPA resolves these logging, String bridge and conformance imports
and still exits with status 1 before entry at EOS's
`_$sSS10FoundationE36_unconditionallyBridgeFromObjectiveCySSSo8NSStringCSgFZ`,
the reverse optional NSString-to-String bridge. Its native export and two EOS
call sites are retained for measurement. Both import audits resolve four
additional strong imports across the bundled frameworks. Full regression
remains unpassed; these runners stay in the evidence directory and the five published runners
keep their last passing bytes. Entry, rendering and gameplay remain unverified.

V now also resolves Foundation's
`String._unconditionallyBridgeFromObjectiveC(NSString?)`. The installed Mac
export and both pinned EOS callers establish a borrowed optional NSString
argument in `x0` and an owned String result in `x0/x1`; nil returns the empty
small String. Native measurements cover tagged strings, shared ASCII and
foreign UTF-16 storage, source retain counts, Unicode and embedded NUL bytes,
and result use after releasing the caller's NSString reference.

Vinix validates the object registry before reading its class or bytes and
copies stored NSString text into the existing inline or owned native-tail
Swift String representation. The recursive registry lock protects the borrowed
text through the copy, which runs without guest callbacks. Source ownership
stays with the caller; large result storage drains through normal Swift bridge
ARC. Loaded UTF-8 and decoded UTF-16 constants use the same path. Inputs are
limited to 1 MiB and registered storage-backed NSString objects or constants;
foreign Objective-C objects and custom NSString primitive overrides remain
unsupported.

The main executable requests both String bridges through Foundation.framework,
whereas EOS requests them through libswiftFoundation. Installed native
measurements confirm that the four currently supported Swift Foundation exports
have identical addresses under both install names. Vinix routes those exact
exports through the same resolver for Foundation.framework; other frameworks
do not acquire these Swift aliases.

The final eight host sanitizer processes pass in both hash modes, all
forty-nine programs build, and all thirty-one Swift checks pass in Vinix.
Fixtures cover source/result destruction in either order, repeated and
concurrent bridges, byte lengths across the inline boundary, nil, embedded
NUL, Unicode, decoded constants and inaccessible or retired object handles.
Generated C confirms that the bridge and framework routing add no hidden
successful V allocations; all fifty-three final C streams are retained with
verified lossless compression.

Both import audits resolve three more strong imports than the preceding
logging cohort: the two main-executable String bridges and EOS's reverse
bridge. The supplied IPA still exits with status 1 before entry at
`_$ss5ErrorP10FoundationE20localizedDescriptionSSvg`, Swift
`Error.localizedDescription`. Its native export and four EOS plus two
Marketplace wrapper call sites are captured without invoking that ABI.
Evidence is under `build/ios/fortnite/swift-string-unbridge-checks`, including
the initial host header collision and the entire earlier passing cohort whose
audit exposed the missing framework aliases. Full regression remains unpassed;
the candidates stay in the evidence directory and the five published runners
retain their last passing bytes. Entry, rendering and gameplay remain unverified.

V resolves Swift `Error.localizedDescription` through both Foundation install
names for the concrete CFError conformance already supported by error
extraction. Native measurements establish metadata in `x0`, the Error witness
table in `x1`, and borrowed indirect Self in `x20`. A sealed adapter forwards
these to V; the owned two-word String returns in `x0/x1`, preserving `x20/x21`.
The installed getter agrees with CFError's description for the measured inputs,
and both library names reexport the same native address.

The implementation validates the canonical metadata and witness table before
reading Self, then validates the live CFError registry entry before fields.
Stored NSString text stays borrowed under the recursive lock until copied
into independent Swift String storage. No input ARC changes, guest callbacks,
temporary NSError objects or hidden successful V allocations are needed.
Fixed stack views and decimal scratch preserve embedded NULs, Unicode and
the complete signed 64-bit code range; the existing String reservation and
appender own any large result.

Explicit description, failure, failure reason and detail fields follow the
measured native priority, including explicit empty strings. Generic domain/code,
abbreviated OSStatus and existing C-locale Darwin POSIX messages are supported;
POSIX codes narrow to 32 bits as on the measured Mac. The existing concrete
CFError conformance is required: native Swift error boxes, arbitrary value
Error conformances and NSError subclasses remain unsupported. Fields require
registered NSString storage and owned dictionary callbacks, with at most
1 MiB of output. Cocoa and Mach requests needing implicit platform catalogs
fail explicitly instead of generating unverified descriptions.

All eight final native/V sanitizer processes pass in both hash modes, all
fifty programs build, and all thirty-two Swift checks pass in Vinix. Tests
cover both source/result destruction orders, repeated and concurrent calls,
preserved context registers, explicit empty/Unicode/NUL fields, field priority,
POSIX narrowing, signed code limits, invalid metadata/owners and bounded text.
All fifty-four final C streams are retained with verified lossless compression.
The native invalid-field measurement, which supplied NSNumber as a description
and raised an Objective-C exception, retains its exact V/C/binary and joined
status 134; a guarded measurement and full merged-output reproduction document
the unsupported type.

The supplied IPA resolves the getter in both bundled frameworks and still exits
with status 1 before entry. Its next blocker is a chained Mach-O weak-lookup
binding: ordinal `-3` for EOS's `__ZTISt12length_error`. The installed SDK names
this ordinal `BIND_SPECIAL_DYLIB_WEAK_LOOKUP`, and Mac libc++ exports the RTTI
data. At that point the V C++ bridge contained this exact symbol, but the chained
resolver rejected special ordinals and the module resolver lacked process-wide
weak lookup. The Marketplace wrapper also imports operator new/delete through
this scope. These imports and native data bytes are retained for the resolver
work without treating RTTI as callable code.

Evidence is under `build/ios/fortnite/swift-error-description-checks`. Both
audits resolve two more strong imports than the preceding String-bridge cohort.
Full regression remains unpassed, candidates stay in the evidence directory,
and the five published runners keep their last passing bytes. Entry, rendering
and gameplay remain unverified.

The subsequent Mach-O loader increment implements self, main executable, flat
and weak lookup scopes for chained imports. Weak lookup selects a canonical
definition across the loaded images and the measured C++ bridge: the first weak
definition wins unless a strong definition overrides it. Legacy weak bindings
also use this scope when rewriting pointers to their own weak definitions.
Export-trie and nlist lookup preserve definition strength and distinguish a
missing export from an absolute zero. Required imports still fail when missing;
missing optional imports stay null even with pointer addends. Named-library
lookup keeps its library scope, and malformed export metadata fails explicitly.
Other built-in libraries' weak exports require an ABI description before joining
coalescing; export re-exports and resolvers remain unsupported.

`build-support/ios/generate-cxx-weak.v` records the seven implemented weak C++
exports from the installed SDK stub. `tests/ios/weak-lookup-native.v` generates
Mach-O objects in V and links them with the Mac's installed linker. Four actual
dyld processes confirm first-weak and strong-override behavior; the resulting
client contains a required chained weak-lookup import. The same client binds to
the canonical definition in the V loader on both the host and Vinix. Host tests
cover all three chained import formats, legacy streams, nlist strengths,
absolute zero, symbol scopes, missing imports, unchanged input on failure and
teardown. Both host suites pass Clang O1 ASAN/UBSAN. All 51 native programs build,
53 original generated C streams restore to their recorded hashes, and Vinix
passes the loader program plus all 32 Swift programs. The loader program also
checks the real C++ RTTI, operator new and operator delete exports.

The supplied IPA now passes the weak-lookup bindings and stops before entry at
EOS's required `_$sBi64_WV` import, the Swift `Builtin.Int64` value-witness table.
The installed Swift runtime exports that data table: size and stride are eight,
flags are seven (POD, inline, alignment eight), and extra inhabitants are zero.
The 88-byte table is captured as data without invoking its function pointers.
Evidence is under `build/ios/fortnite/weak-lookup-checks`. Full regression remains
unpassed and the five published runners retain their last passing bytes. Entry,
rendering and gameplay remain unverified.

The subsequent Swift data increment exports `_$sBi64_WV` through the existing
sealed Int value-witness table. Native measurement confirms that Builtin.Int64
and Int use the same table address, including all eight function pointers and
the size, stride, flags and extra-inhabitant fields. The direct export passes
native and V witness calls for copy, assignment, take, destruction and enum
storage, including aliasing, signed boundaries, an exact eight-byte allocation
and guarded tag storage. Eight concurrent resolvers return the canonical table;
two runtime lifetimes verify unchanged table contents and retired mappings.

After that export, the IPA reached `_$sSHSQTb`, the Hashable-to-Equatable base
conformance descriptor. Native inspection identifies data at the Hashable
protocol descriptor plus 36: the first eight-byte protocol requirement, with
zero flags and a null default implementation. Vinix now exports that existing
record, preserving descriptor identity and the inherited witness-table index.
Both exports reuse the sealed Int/Hashable records without another arena or
allocation. A test-only unaligned eight-byte descriptor read was caught by
UBSan and corrected to read the two four-byte fields separately; the failed run
is retained alongside the completed Int64-only cohort.

All 51 programs build, 55 final original C streams restore to their recorded
hashes, and four host suites pass ASAN/UBSAN in both hashing modes. The four
native dyld fixture processes pass again, and Vinix passes all 32 Swift programs
plus the loader program. The supplied IPA passes both new exports and exits
with status 1 before entry at CoreFoundation's
`_OBJC_CLASS_$_NSConstantDictionary`. Typed native runtime inspection reports
an NSDictionary subclass with a 40-byte instance: options at 8, count at 16,
keys at 24 and objects at 32. EOS contains three class bindings in its
`__objc_dictobj` section. Static dictionary instance decoding remains
unimplemented. Evidence is under `build/ios/fortnite/swift-builtin-checks`.
Full regression remains unpassed, the five published runners retain their last
passing bytes, and entry, rendering and gameplay remain unverified.

The subsequent Objective-C increment implements the `NSConstantDictionary`
class and its `__objc_dictobj` records. The native runtime and
[Clang's literal ABI](https://github.com/llvm/llvm-project/blob/main/clang/lib/CodeGen/CGObjCMac.cpp)
agree on the forty-byte layout and sorted string-key format. Vinix validates
all records, member arrays and supported member lifetimes before publishing
metadata. The mapped objects and arrays stay read-only. Each record owns one
sidecar and two sized member arrays; shutdown frees them after collection and
autorelease users drain, without releasing borrowed image members or freeing
mapped object bytes. Ordinary owned objects and disposable classes are rejected
as literal members.

Native comparisons cover CF/Objective-C lookup, equal and missing keys,
extraction, enumeration, arrays, immortal copies and independent mutable copies.
The native extraction method fills every pair even when its count argument is
zero; the tests provision complete output buffers and check their guards.
Concurrent registration, malformed records, immutable mutation, explicit
destruction and two drained runtime lifetimes also pass. A metadata-only fixture
rebases and registers EOS's three actual dictionaries on both the host and
Vinix, checks equal-key lookup and retires their metadata without executing app
code. The native getter's initially incorrect count-limit expectation, a missing
archived storage fixture, a test declaration conflict and the VM monitor's
rejection of expected child panics retain their failed/partial evidence. Child
panics are now captured and checked inside the test; the monitor still rejects
unexpected failures.

All 52 programs build, 56 final generated C streams restore to their recorded
hashes, and four host suites pass ASAN/UBSAN in both hashing modes. Vinix passes
33 Swift/loader programs and six Objective-C collection/storage programs. The
IPA passes the dictionary class binding and exits with status 1 before entry at
Foundation's `_OBJC_CLASS_$_NSLayoutConstraint`. Native runtime metadata for
that eighty-byte NSObject subclass and its method signatures was captured;
constraint construction and layout were unimplemented at that checkpoint.
Evidence is under
`build/ios/fortnite/constant-dictionary-checks`. Full regression remains
unpassed, the five published runners retain their last passing bytes, and entry,
rendering and gameplay remain unverified.

`NSLayoutConstraint` now provides item and anchor factories, scalar properties,
identifiers and archive flags. Its eighty-byte record and the sixty-four-byte
`NSLayoutAnchor`, `NSLayoutXAxisAnchor`, `NSLayoutYAxisAnchor` and
`NSLayoutDimension` records match the measured native instance sizes. UIView
anchors are cached lazily. Constraints own their anchors; anchors borrow their
views. Vinix zeros those borrowed references when a view dies, so retained
constraints preserve attributes without returning freed view storage.

Typed V calls into this Mac's Foundation and AppKit compare twelve attributes,
three relations, anchor identity, defaults and mutations. Multipliers round to
float before returning a double, constants remain doubles, and priority uses
the float message ABI. A missing second item normalizes the multiplier to one.
The native rejection of priority zero is retained: valid priorities are greater
than zero through 1000. Repeated drained runtimes and captured invalid-input
children verify ownership and cleanup. Constraint activation raises an explicit
missing-solver error; layout solving, layout guides and visual-format parsing
remain unimplemented.

All 53 programs build and 58 final original generated C streams restore to
their recorded hashes. Five host suites pass ASAN/UBSAN in both hashing modes,
including replays against four native dyld load orders. Vinix passes seven
Objective-C collection/storage/layout programs and 33 Swift/loader programs.
The initial generated-code audit spelling mismatch retains its joined failed
cohorts and exact inputs; the corrected audit verifies one fixed anchor cache
per touched view and allocation-free disposal.

The IPA passes the constraint class binding and exits with status 1 before
entry at Foundation's `_OBJC_CLASS_$_NSJSONSerialization` in EOS. That native
eight-byte NSObject subclass's method signatures are captured without app code
execution. Evidence is under `build/ios/fortnite/layout-constraint-checks`.
Full regression remains unpassed after the earlier permissions, readlink and
kernel file-time failures. The five published runners retain their last passing
bytes, and entry, rendering and gameplay remain unverified.

`NSJSONSerialization` now implements its NSData reading/writing methods and
`isValidJSONObject:` in V. The eight-byte JSON and NSNull classes and forty-byte
NSError record match native Foundation measurements. JSON failures return nil
and an autoreleased Cocoa error 3840 with a debug description; successful calls
leave the caller's existing error output untouched. Null and Boolean objects
use owned runtime caches. NSError owns its copied domain and user-info snapshot
and exposes code, domain, userInfo and localizedDescription getters.

Shared typed native/V message tests compare immutable and mutable containers,
first-versus-last duplicate-key handling, fragments, trailing commas, escaped
controls and Unicode surrogate pairs, UTF-8/16/32 input, signed and unsigned
64-bit limits, double output, malformed input, slash escaping, two-space pretty
output and natural ASCII key sorting. Unsigned NSNumber values retain their
exact spelling and equality, including at the double-rounding boundary. Heap
sort leaves input dictionaries unchanged and allocates no scratch storage.

This bounded data profile accepts reading options 0, 1, 4 and 5 and writing
options 0 through 15. Input/output is limited to 16 MiB, depth to 64, and values
to 65,536 nodes. Integer storage covers signed 64-bit and positive unsigned
64-bit values; real tokens allow up to 17 significant mantissa digits and 128
token bytes. Decimal-number storage, mutable leaves, streams and extended
reading options remain unimplemented. Sorted keys are limited to ASCII letters,
digits and underscore; ordinary unsorted JSON supports Unicode keys. Unsupported
profiles return errors. Cycles and non-finite numbers are rejected.

All 54 programs build and all 60 final original generated C streams restore to
their recorded hashes. Six host suites pass ASAN/UBSAN in both hashing modes,
including actual EOS constant records and four final native dyld load orders.
Vinix passes eight Objective-C/collection/storage/layout/JSON programs and 33
Swift/loader programs. Repeated pool drains and partial parse failures leave
only the three singleton caches, which are freed when the runtime stops. The
initial empty-NSData nil-string failure and its original generated C are
retained alongside the passing checks; cached failure interfaces avoid a heap
allocation per malformed request.

The supplied IPA passes the JSON class binding and exits with status 1 before
entry at `_OBJC_CLASS_$_NSCondition` in EOS. Native metadata shows a 128-byte
NSObject subclass containing a Darwin mutex at offset 8, a condition at offset
72 and a string name at offset 120. Those signatures were measured without
constructing that class or executing app code; its behavior remains
unimplemented. Evidence is under `build/ios/fortnite/json-serialization-checks`.
Full regression remains unpassed and the five published runners are unchanged.
Entry, rendering and gameplay remain unverified.

`NSCondition` now implements initialization, lock/unlock, wait, signal,
broadcast, deadline waits and copied names in V. Its 128-byte record and
mutex/condition/name ivars match the native layout. Initialized opaque records
carry the measured `MUTZ` and `COND` signatures, while the existing pthread
adapters own the real native synchronization objects. Allocation and
`objc_constructInstance` leave synchronization uninitialized; `init` and `new`
initialize it. Disposal removes both pthread entries and frees the owned name,
including after a change of isa or destruction of caller-owned storage.

Typed message calls into Mac Foundation and the V trampoline compare twenty
mutex handoffs, eight simultaneous waiters awakened by broadcast, signaled
deadline waits, past/nil deadlines and mutex reacquisition under contention.
A separate native measurement confirms that changing a mutable source string
does not change the copied name. Repeated creation/release and two drained
runtimes leave zero live objects and zero condition/mutex registry entries.
Captured invalid-input children verify explicit rejection of uninitialized
synchronization, non-string names, foreign dates and oversized deadlines.
Deadline objects use the existing CFDate profile and finite, representable
clock values; general NSDate factories remain unimplemented. Callers keep
objects alive while synchronization is in use and release them when quiescent.

All 55 programs build and all 62 final original generated C streams restore
to their recorded hashes. Seven host suites pass ASAN/UBSAN in both hashing
modes, with final native dyld and EOS dictionary fixtures. Vinix passes nine
Objective-C/collection/storage/layout/JSON/condition programs and 33
Swift/loader programs. Generated-code checks confirm stack-only deadline
conversion and no temporary allocation during condition disposal. A Clang
temporary-file failure caused by host disk exhaustion is recorded; compiler
scratch files moved to the private RAM volume and subsequent builds passed.

Fortnite passes the NSCondition binding and still exits with status 1 before
entry at Foundation's `_OBJC_CLASS_$_NSHTTPCookie` in EOS. Native metadata shows
a sixteen-byte NSObject subclass with an `NSHTTPCookieInternal` object at offset
8; its getters and cookie/header factories are recorded without constructing
that class or executing app code. Evidence is under
`build/ios/fortnite/condition-checks`. Full regression remains unpassed, the
five published runners are unchanged, and entry/rendering/gameplay remain
unverified.

`NSHTTPCookie` now implements property construction, its public getters,
mutable property snapshots, equality and request/response header factories in
V. The 16-byte cookie record owns an 8-byte `NSHTTPCookieInternal` object through
the measured `_cookiePrivate` ivar. That object owns copied strings, a canonical
dictionary, a port array and the parsed comment URL. Disposal releases them
after class changes and caller-storage destruction too. The ordinary mutable
dictionary setter is implemented for editing property snapshots.

Typed calls into the installed Foundation library verify domain normalization,
empty values, presence-based Secure/HttpOnly flags, Discard removing expiry,
SameSite normalization, version/port conversion and comment URL getters. A
supplied integer creation timestamp survives a property round trip, while zero
removes it; equality ignores creation time and Max-Age uses the current clock.
Request headers preserve array order and duplicate names. Response checks cover
combined cookies, quoted values, default paths, domain attributes and RFC1123
GMT expiry dates. Cookie hash values preserve equal-object consistency without
matching Cocoa's numeric hash values.

The URL profile constructs absolute HTTP/HTTPS URLs without making network
requests. It owns scheme, host, decoded path, query, fragment, port and absolute
string components. Initialization retains an argument borrowed from that same
URL until the old components have been replaced. File URLs retain their existing
behavior; file handles and font loading reject HTTP URLs.

Properties and response headers are bounded to 128 keys and 64 KiB per string;
request headers are bounded to 1 MiB and cookie arrays to 1,024 entries. Creation
timestamps use nonnegative integers, other numeric cookie properties use signed
32-bit prefixes, and versions are limited to 0..255. Expiry objects use the
existing CFDate profile. Relative URLs, user information, IPv6 authorities,
Unicode domains, quoted semicolons and other expiry date formats remain outside
the implemented profile. General NSDate factories and cookie coding/description
APIs remain unimplemented. ASCII attribute folding avoids the V library's
unfreed Unicode lowercase scratch array.

All 56 final programs build and 64 final generated C streams restore to their
recorded hashes. Eight host suites pass ASAN/UBSAN in both hashing modes, and
Vinix passes ten Objective-C programs and 33 Swift/loader programs. Repeated
cookie release, class changes, caller-storage destruction and URL argument
aliasing leave zero live objects. Generated-code checks cover token/buffer
cleanup and allocation-free disposal. Earlier failed native assumptions and
sanitizer trials are retained with their sources and actual statuses.

Fortnite passes cookie binding and exits with status 1 before entry at EOS's
required WebKit import `_OBJC_CLASS_$_WKWebViewConfiguration`. Native metadata
shows a 592-byte NSObject subclass, including 576 bytes of page configuration
storage at offset 8 and a navigation-limit flag at offset 584; no WebKit objects
were constructed. The metadata helper was corrected to recognize this
unsupported-library error after all five guest phases passed; its original
failed parsing attempt is retained.
Evidence is under `build/ios/fortnite/cookie-checks`. Full regression remains
unpassed, five published runners are unchanged, and entry/rendering/gameplay
remain unverified.

`WKWebViewConfiguration` now has a V implementation of the public configuration
profile measured against the installed macOS WebKit. It preserves the measured
592-byte layout and navigation-limit ivar, with owned public state outside the
reserved inline C++ storage. Its five dependencies have their measured class
layouts too: preferences, process pool, user content controller, website data
store and default webpage preferences. Configuration copies share dependency
objects, nil setters recreate defaults, and the user-agent name is copied.
Preference copies have independent scalar state. The default data-store identity
is shared within a runtime; nonpersistent stores have separate identities.

The configuration supports the measured boolean, enum and media policy
properties. Preferences support minimum font size, JavaScript/window policies,
tab focus and text interaction; webpage preferences support content mode,
content JavaScript and lockdown policy. These objects hold configuration state.
Process pools do not start browser processes, data stores do not persist browsing
data, and the content controller currently exposes only an empty script list.
Inline native C++ bytes remain zero-filled. Private engine access, coding,
script registration/execution, URL scheme handlers, nonnil web extensions and
unmeasured iOS-only properties remain unimplemented.

All 57 final programs build, and 66 final generated C streams restore to their
recorded hashes. Nine host suites pass ASAN/UBSAN in both hashing modes. Vinix
passes eleven Objective-C programs and 33 Swift/loader programs. Shared native
and guest fixtures check defaults, floating-point setters, dependency sharing,
copies, nil resets and persistence policy. Repeated release, class changes and
caller-storage destruction balance ownership across two runtime cycles; four
rejection children verify unsupported operations fail explicitly. Generated-code
checks confirm one fixed sidecar per initialized object and no temporary
allocation during its disposal.

Fortnite passes the configuration binding and still exits with status 1 before
entry at EOS's required `_OBJC_CLASS_$_WKUserScript` import. Native metadata shows
a 128-byte NSObject subclass with 120 bytes of script storage at offset 8,
source/injection-time/main-frame getters and the public script initializer.
The next-class measurement invokes metadata APIs only. Evidence is under
`build/ios/fortnite/webkit-configuration-checks`. Full regression remains
unpassed, the five published runners are unchanged, and entry/rendering/gameplay
remain unverified.

`WKUserScript` and `WKContentWorld` now implement their measured public data
APIs in V. Scripts copy source strings, preserve document-start/document-end and
main-frame policies, and support both public initializers, including an explicit
content world. Copying an immutable script retains that same object. Page and
default-client worlds have distinct identities and nil names; named worlds copy
their names and are interned within a runtime. Their measured native records are
128 and 80 bytes, with public state in the existing owned sidecars.

`WKUserContentController` now registers scripts in order, including duplicates,
and removes all registrations. Its `userScripts` getter returns a stable,
read-only 40-byte `WKNSArray` adapter. The list changes when registrations change;
copying it retains the same live list. A retained list keeps its scripts alive
after controller destruction. Configuration copies share their controller and
registrations. Array storage owns each script reference; each script owns its
copied source and world. Disposal still works after class changes and
caller-storage destruction. Explicit app methods remain discoverable when added
to WebKit classes whose native profile has no copy implementation.

Sources are bounded to 1 MiB, lists to 1,024 entries and world names to 4,096 UTF-8
bytes. The runtime owns page/client worlds and at most 126 named worlds until
shutdown. Script reinitialization, other injection values, private engine/C++
access, coding and script execution remain unimplemented. Native inline C++
storage stays zero-filled. The first native probe read a borrowed script after
clearing registrations and failed; subsequent probes used explicit retains and
verified live-list ownership. Original trials and their actual statuses remain
preserved.

All 58 final programs build and 68 final generated C streams restore to their
recorded hashes. Ten host suites pass ASAN/UBSAN in both hashing modes. Vinix
passes twelve Objective-C programs and 33 Swift/loader programs. Shared fixtures
verify copied mutable inputs, immutable copies, world identity, duplicates,
registration order, live lists and retained-list lifetimes. Repeated release,
class changes and caller-storage checks balance ownership across two runtime
cycles, with six explicit rejection children. Generated-code checks verify
allocation-free list clearing and world-cache retirement.

Fortnite passes script binding and still exits with status 1 before entry at
EOS's required `_OBJC_CLASS_$_WKWebView` import. The metadata probe observes a
1,008-byte macOS NSView subclass; that platform layout does not establish the
iOS UIView layout. No web view is constructed. Evidence is under
`build/ios/fortnite/user-script-checks`. Full regression remains unpassed, the
five published runners are unchanged, and entry/rendering/gameplay remain
unverified.

`WKWebView` now implements a blank UIView frontend in V. Typed probes of the
installed Catalyst WebKit verify frame initialization, fresh configuration
copies with shared dependencies, copied user agents, zeroing weak navigation/UI
delegates, floating-point zoom/progress properties and retained empty history.
`WKBackForwardList` exposes empty, read-only history arrays and nil items. Its
lifetime remains valid after releasing the view. View destruction unregisters
both weak slots and releases its configuration, strings and history, including
after class changes and caller-storage destruction.

The reference view record is 1,992 bytes, with the configuration reference at
offset 408; the history record is 88 bytes. These sizes come from a genuine
Catalyst process using the installed iOSSupport frameworks. They do not establish
the private device iOS ABI. The existing UIView and macOS configuration profiles
still supply the public state; other native C++ bytes remain reserved and
zero-filled. Navigation, reload, JavaScript execution, script-message handlers,
rendering, coding and private engine APIs remain unimplemented. An earlier
Catalyst probe returned a navigation object for blank reload, so reload is
explicitly unavailable in this profile.

All 59 programs build and 70 original generated C streams restore to their
recorded hashes. Eleven host suites pass ASAN/UBSAN in both hashing modes. Vinix
passes thirteen Objective-C programs and 33 Swift/loader programs. The new
fixtures check 100 release cycles, changed classes, caller storage, two runtime
cycles and seven explicit rejection children. Generated-code checks confirm
one fixed view state and no temporary allocation during disposal. The build
driver links the installed V runtime helper sources that the current toolchain
keeps outside generated C. The original host link failure and native measurement
trials are preserved.

Fortnite passes the WebKit view binding and exits with status 1 before entry at
EOS's required `_OBJC_CLASS_$_NSURLRequest` import. Native metadata shows a
24-byte NSObject subclass with `_internal` and `_cookiePartitionIdentifier`
references at offsets 8 and 16. That next-class probe invokes metadata APIs
only. Evidence is under `build/ios/fortnite/webview-checks`. Full regression
remains unpassed, the five published runners are unchanged, and game entry,
rendering and gameplay remain unverified.

`NSURLRequest` and `NSMutableURLRequest` now implement public request data in V.
Factories and initializers accept the existing HTTP/file URL objects and nil
URLs, including the mixed integer/floating-point cache-policy/timeout arguments.
Defaults match installed Foundation: GET, a 60-second timeout, protocol cache
policy, and enabled cellular, expensive-network, constrained-network and cookie
policies. Finite timeouts preserve zero and negative values. Mutable requests
store the measured boolean, cache, service, attribution and DNSSEC policy fields.
These fields describe a request; they do not initiate network operations.

Copying an immutable request retains it. Copying a mutable request creates a
separate mutable request, as observed on this Mac; `mutableCopy` also creates a
mutable request. Header dictionaries are independent between copies. Header
lookups fold ASCII case, replacement preserves the supplied field spelling,
append joins values with a comma, and nil removes a field. Header getters return
independent mutable snapshots. Bulk setters skip non-string entries. Values,
custom methods and cookie partition strings retain their inputs, including
mutable strings, matching the typed native observations despite copy property
declarations. GET, HEAD, POST, PUT, DELETE, CONNECT and PATCH normalize their
method spelling; other methods preserve it. Bodies copy mutable NSData inputs
and retain immutable data. A nil body-stream setter clears the body.

Both reference records are 24 bytes, with native private ivar metadata at
offsets 8 and 16. This is a macOS Foundation measurement, not a private device
iOS ABI measurement. Owned public state stays outside those reserved,
zero-filled slots. Destruction releases all six object references and frees the
state, including after class changes and caller-storage destruction. Header
replacement acquires both arguments before retiring old slots, so a value may
alias the key being replaced.

The profile supports 128 fields, 256-byte ASCII field names and 64 KiB strings.
Field names must remain unchanged after insertion. Embedded NUL, CR and LF are
rejected; cache/service/attribution values are limited to the declared enum
profile. Request equality/hash, coding, reinitialization, private CFNetwork
bridges, nonnil body streams and URL loading remain unimplemented.

All 60 programs build and 72 original generated C streams restore to their
recorded hashes. Twelve host suites pass ASAN/UBSAN in both hashing modes. Vinix
passes fourteen Objective-C programs and 33 Swift/loader programs. Request
fixtures compare the native data behavior, exercise 100 release cycles after
class changes, check caller storage and run nine explicit rejection children.
The additional header key-to-value alias case passes both sanitizer modes.
Generated-code checks verify fixed state allocation, six-reference retirement
and appended-text cleanup. Earlier compile trials and their actual statuses
remain preserved.

Fortnite passes both request class imports and exits with status 1 before entry
at EOS's required `_OBJC_CLASS_$_NSValue` import. Native metadata shows an
8-byte NSObject subclass with generic byte/type, pointer, nonretained-object,
range and geometry value APIs. The next-class probe constructs no values or
application objects. Evidence is under `build/ios/fortnite/request-checks`.
Full regression remains unpassed, the five published runners are unchanged,
and game entry, rendering and gameplay remain unverified.

`NSValue` now implements immutable public byte/type boxes in V, including
generic factories and designated initialization, pointer and nonretained-object
boxes, ranges, points, sizes, CGRect, edge insets and affine transforms. EOS
imports this class strongly and references `valueWithCGRect:`, `CGRectValue`
and `objCType`. Typed Catalyst calls verify those CGRect methods and the
indirect argument/result ABI for six-double affine transforms. Generic boxes
copy both bytes and their type encoding; immutable copies retain the same
object. Equality compares the complete encoding and bytes, including structure
names and padding. Equal boxes have equal hashes; numeric hash reproduction
from native Foundation is outside this profile.

Installed Foundation reports an 8-byte NSValue base and 24-byte concrete box;
NSNumber now inherits NSValue while preserving its existing numeric behavior.
Its raw value getters use the stored boolean, integer or double representation.
These layouts are measured on macOS/Catalyst, not device iOS private records.
A designated initializer replaces and consumes the base-class placeholder.
Pointer and nonretained-object values use `^v` and never own the address.
`getValue:size:` requires exactly the encoded size: native short and oversized
destinations both raise NSInvalidArgumentException with recorded status 134.

The bounded encoding parser handles scalar and qualified pointer types,
arrays, structures, unions and quoted fields; legacy `l`/`L` encodings are
32-bit even on this 64-bit host, matching the native layout API. It also
exports `NSGetSizeAndAlignment`. Limits are 512 encoding bytes, nesting depth
16, 1024 array elements, 128 aggregate fields and a 1 MiB payload. Bitfields,
opaque aggregate encodings, mutable copies, coding and private bridges remain
unimplemented. Byte and encoding buffers retire through the existing storage
destructor even after a class change or caller-storage destruction.

All 61 programs build and 74 original generated C streams restore to their
recorded hashes. Thirteen host suites pass ASAN/UBSAN in both hashing modes.
Vinix passes fifteen Objective-C programs and 33 Swift/loader programs.
Value fixtures cover native layout/copy/equality behavior, both aggregate
calling conventions, copy associations, 100 class-change release cycles,
caller storage, two runtime cycles and seven explicit rejection children.
Generated-code checks confirm one sized byte array and copied encoding per
initialized box, no parser/equality/size-query scratch allocation, and cleanup
of both buffers. Failed native, fixture, allocation-audit and production-build
trials retain their sources, artifacts and actual statuses. The V compiler
lowers direct one-character C-string integer casts incorrectly; typed pointer
parameters preserve the address in native probes and fixtures.

Fortnite passes the NSValue binding and exits with status 1 before entry at
EOS's required `_OBJC_CLASS_$_NSHTTPURLResponse` import. The next-import probe
verifies the required dependency and reads installed runtime metadata without executing
application code. Evidence is under `build/ios/fortnite/value-checks`. Full
regression remains unpassed, the five published runners are unchanged, and
game entry, rendering and gameplay remain unverified.

`NSURLResponse` and `NSHTTPURLResponse` now implement public response metadata
in V. EOS imports NSHTTPURLResponse strongly and uses `statusCode`,
`allHeaderFields`, `valueForHTTPHeaderField:` and `expectedContentLength`.
The base initializer copies its MIME and encoding strings, retains the URL
through copying, and preserves signed content lengths. Immutable response
copies retain the same object, including copy associations.

HTTP initialization copies the header dictionary and field names while
retaining string values. Header getters return independent snapshots which
reject Objective-C setters, subscripts/removal and CF mutation. Native CF
snapshots report NSMutableDictionary ancestry despite rejecting mutation;
the implementation models this with a persistent storage flag. Fourteen
measured standard field names canonicalize; other names preserve spelling.
Lookups fold ASCII case. MIME and charset getters trim and lowercase their
parsed values; the first charset wins, and its quotes remain, matching the
native observations. Changes to retained mutable header strings affect MIME,
charset and content length getters. The copied dictionary remains independent
of subsequent changes to the input dictionary.

Missing HTTP length is -1. Decimal prefixes accept leading whitespace and
trailing junk, invalid digits produce zero, positive overflow saturates, and
negative lengths become -1. Parsing uses bounded string bytes, including
constant NSString storage. HTTP status preserves the native ten-bit storage
rule. English status descriptions were generated in V from 600 native
observations and checked against installed Foundation. A fresh response has
MIME type application/octet-stream; an explicitly initialized HTTP response
with no Content-Type has nil MIME type. Fresh HTTP responses have status 200.

The measured base/HTTP records are 24/32 bytes, with private ivars at offsets
8, 16 and 24. These are macOS Foundation measurements, not private device iOS
ABI measurements. The private slots remain reserved zero-filled storage;
a separate fixed state owns four references and retires after class changes
and caller-storage destruction. The profile allows 128 fields, 256-byte ASCII
field names and 64 KiB strings. Names differing only by case reject, and
retained mutable values must stay within the validated string profile.
Suggested filenames, coding, response equality/hash, private CFNetwork
bridges, the HTTP inherited base initializer and transport remain unimplemented.

All 62 programs build and 76 original generated C streams restore to their
recorded hashes. Fourteen host suites pass ASAN/UBSAN in both hashing modes.
Vinix passes sixteen Objective-C programs and 33 Swift/loader programs.
Response fixtures check the measured data behavior and calling conventions,
100 class-change release cycles, copy associations, caller storage and two
runtime cycles. Thirteen rejection children check invalid inputs, immutable
snapshots and unsupported APIs. Generated-code checks verify fixed state
ownership, allocation-free retirement/length/trim parsing and canonical key
cleanup. Native and host trials retain their sources and actual statuses;
the premature cache-probe run is preserved and excluded from validation.

Fortnite passes the response class binding and exits with status 1 before
entry at EOS's required `_OBJC_CLASS_$_UIAlertController` import. The
next-import probe verifies that dependency without executing application code. Evidence is
under `build/ios/fortnite/response-checks`. Full regression remains unpassed,
the five published runners are unchanged, and game entry, rendering and
gameplay remain unverified.

`UIAlertController` and `UIAlertAction` now implement a bounded public alert
model in V. EOS imports the controller strongly and names dismissal and the
WKUIDelegate JavaScript alert callback. Its selector table has no alert factory
or text-field selectors. Installed Catalyst UIKit supplied typed native
measurements without native presentation or executing application code.

Factories and setters copy title/message text. Controllers retain actions
and return immutable action snapshots; existing snapshots keep their contents.
Duplicate default/destructive actions are allowed. A second cancel action and
a preferred action outside the list reject, matching native exceptions.
Action copies are separate objects and preserve style/enabled state. Captured
handlers promote from stack blocks once and share that capture lifetime through
copies; disposal runs on the final owner. Fresh actions are disabled, factory
actions enabled; fresh controllers use alert style and default severity.

Vinix presents simple title/message panels and action buttons through its
existing desktop protocol. Disabled buttons are marked disabled and ignored.
Selection pins the controller, action and handler while removing presentation
ownership, then invokes the handler with its selected action. A handler can
present a replacement immediately. Presenting-controller links and button
targets are weak, and dismissal uses the recorded presenter relationship.
Resize rebuilds the panel with bounded children and releases old view ownership.

The 1400/144-byte controller/action records come from Catalyst, not private
device iOS ABI measurements; bytes after isa remain reserved zero-filled.
One fixed sidecar owns three references, up to 32 actions and a copied block.
Storage flags preserve retirement after isa changes and caller-owned destruction.
The profile covers controller styles 0/1, action styles 0/1/2, severity 0/1
and text up to 64 KiB. Native accepts controller style 99, which Vinix rejects.
Text fields, keyboard interaction, popovers, private UIKit bridging, animations
and controller copying remain unimplemented. The JavaScript alert delegate
callback still requires a WebKit execution engine.

All 63 programs build and 78 original generated C streams restore to their
recorded hashes. Fifteen host suites pass ASAN/UBSAN in both hashing modes;
the alert suite runs as Catalyst against native UIKit and the V runtime.
Catalyst host compilation disables Apple LLVM ARC optimizations and its
aarch64 objc retain/release register-call rewrite: the first trial redirected
Vinix ownership calls into native libobjc. Native empty action arrays can
reuse identity; populated snapshots are checked independently. Original trial
sources, binaries, logs and actual exits remain retained. Two headless turn
interruptions also retain unfinished C and driver sources. Completed checks
were reused only after validating their joined statuses and original C hashes;
detached V supervisors recorded the final driver exits.

Vinix passes seventeen Objective-C and 33 Swift/loader programs. Alert checks
cover native properties, calling conventions, copy associations, 100 isa-change
release cycles, caller storage and two clean runtime cycles. Selection fixtures
cover visible text/buttons, resize, disabled actions and 20 pool-drained callback
lifetime cycles with weak zeroing and reentrant replacement. Nine rejection
children cover invalid inputs, cancel/preferred restrictions, immutable arrays
and unsupported APIs. Generated-code checks cover fixed-state retirement and
layout constructor ownership; the prior allocation checks also pass.

Fortnite passes the alert controller binding and exits with status 1 before
entry at EOS's required `_OBJC_CLASS_$_NSMutableSet` import. Evidence is retained under
`build/ios/fortnite/alert-checks`. Full regression remains unpassed, the five
published runners are unchanged, and game entry, rendering and gameplay
remain unverified.

`NSSet` and `NSMutableSet` now implement set membership and mutation in V.
EOS imports NSMutableSet strongly through CoreFoundation and uses it for
snapshotted windows, with membership, insertion, anyObject, clearing and
fast enumeration. Installed Foundation APIs supplied typed measurements;
no application code executed during native RE.

Construction and insertion deduplicate equal members and retain the first
canonical object. Lookup uses member hashes and equality; native app hash
and isEqual: implementations are invoked, with existing Foundation value
comparisons as the fallback. Equal NSValue byte/type boxes share a hash
bucket. Set equality ignores order and its public hash is the member count.
Values must keep their hash/equality stable while inserted.

Immutable copies retain the same object. Copying a mutable set creates an
immutable membership snapshot, and mutableCopy always creates a separate
mutable set. allObjects returns an immutable array snapshot. Set union,
intersection, subtraction and replacement handle self operands. Nil arrays
and sets initialize empty; nil union/subtraction preserve membership, while
nil intersection/replacement clear it. Nil member queries return nil/false;
individual insertion/removal and single-object construction reject nil.

Every mutator invalidates fast enumeration, including duplicate insertion
and removal of an absent member, matching native behavior. Members and
receivers stay pinned while callbacks run. Mutation during membership or
algebra callbacks rejects. An input array changed by a hash callback also
rejects; insertion pins its member through release of the array ownership.
Removal drops the array entry before releasing the member, and clearing
uses existing member-array retirement without a scratch ownership list.

Abstract set records are eight bytes on the measured Mac. Public members
use the existing owned noslices array in runtime metadata. The storage flags
preserve retirement after isa changes and caller-owned destruction. Scene
URL contexts now construct and populate an initialized set through this
implementation. Linear lookup is bounded to 4096 members/input slots/capacity.
Private class clusters, CFSet APIs, custom set subclasses, variadic factories,
block/predicate enumeration, ordered-set operations and coding are outside
this profile. Array/dictionary indexing and mutation aliases fail explicitly.

All 64 programs build and 80 original generated C streams restore to their
recorded hashes. Sixteen host suites pass ASAN/UBSAN in both hashing modes.
Vinix passes eighteen Objective-C and 33 Swift/loader programs. Shared set
fixtures cover native properties, hash collisions and custom equality,
copy/member ownership, algebra, no-op mutation, CF equality/hash, 100 copy
associations and isa-change releases, caller storage and two clean cycles.
Thirteen rejection children cover invalid inputs, immutable writes/snapshots,
bounds, aliases, unsupported APIs, reentrant mutation and input-array release
during hashing. Generated C checks verify allocation-free lookup/equality/
algebra, member pins and reuse of generic owned-array retirement.

Fortnite passes the mutable-set binding and exits with status 1 before entry
at EOS's required `_OBJC_CLASS_$_NSThread` import. Evidence is retained under
`build/ios/fortnite/set-checks`. Full regression remains unpassed, the five
published runners are unchanged, and game entry, rendering and gameplay
remain unverified.

`NSThread` now implements Foundation thread identities and basic workers in V.
EOS strongly imports the class and contains currentThread and isMainThread
selectors. Installed Foundation supplied typed metadata and behavior probes;
native RE never executed application code.

The class has the measured 64-byte opaque record and private ivar offsets.
Public state lives in an owned sidecar, so isa changes and caller-provided
storage keep the same retirement path. Main/current identities are stable,
including on foreign pthreads, and each thread lazily owns a mutable dictionary.
The main identity uses the Vinix label Main Thread; native process labels
are platform-dependent. Names are copied; configured stack size defaults to
512 KiB. State distinguishes unstarted, executing, finished and cooperatively
cancelled threads.

Target/selector constructors retain their target and object argument. Block
constructors promote stack blocks through the existing copy/dispose helpers.
start and both detach factories use real native pthreads through the existing
Mach lifetime wrapper. TLS owns an executing identity; its destructor releases
captures, drains autoreleases and publishes completion on normal return and
explicit pthread_exit. Cancellation before entry skips the callback; cancellation
while executing leaves the callback running until it returns or exits.

A small join record keeps the native handle until pthread_join finishes every
key-destructor iteration. Completed workers are reaped on later starts and all
remaining workers join before runtime and application mappings are retired.
Dispatch/Swift workers and foreign app pthreads must finish before thread TLS
is deleted. The main identity cache also releases at shutdown.

The native Mac retains a block cancelled before start even after the thread
is released and its pool drained. That observation has a separate bounded
probe with valid persistent capture storage. Shared native sanitizer cases
use a block-free thread for pre-start cancellation; Vinix additionally verifies
that its cancelled block is disposed. Normal and explicit-exit block disposal
are checked against native Foundation. Failed exploratory assumptions and
compiler trials remain archived with their actual exit statuses.

This profile caps 256 unreaped workers, accepts unstarted configured stacks in
16 KiB multiples through 8 MiB, and implements finite sleeps through one day.
Scheduling/QoS, thread run loops, call-stack introspection, notifications and
perform-selector routing remain outside the profile. Main-thread exit, restart,
reinitialization, invalid stack sizes, nil blocks and currentThread during TLS
destruction reject explicitly. Dictionary mutation requires application
synchronization; no private Foundation thread ivar layout is emulated.

All 65 programs build and 82 original generated C streams restore to recorded
hashes. Seventeen host suites pass ASAN/UBSAN in both hashing modes. Vinix
passes nineteen Objective-C and 33 Swift/loader programs. Thread fixtures cover
target/argument retention, block promotion/disposal, explicit exit, cooperative
and pre-start cancellation, detached callbacks, two simultaneous foreign
identities, copied names, dictionaries, stacks and sleeps. They also cover 100
isa-change releases, caller storage, seven rejected operations and two shutdown
cycles with zero live objects, heap blocks, workers and TLS identities.
Generated C audits check sidecar/context/join-record retirement and verify
that TLS cleanup allocates no scratch state. Earlier checks remain enabled.

Fortnite passes the NSThread binding and exits with status 1 before entry at
EOS's required `_OBJC_CLASS_$_ASWebAuthenticationSession` import.
Evidence is retained under
`build/ios/fortnite/thread-checks`. Full regression remains unpassed, the five
published runners are unchanged, and game entry, rendering and gameplay
remain unverified.

`ASWebAuthenticationSession` now supports the measured configuration and
missing-presentation path in V. EOS strongly imports the class and contains
the old URL/scheme/completion constructor, presentation-provider and anchor
selectors, start and cancel. Installed Mac and Catalyst AuthenticationServices
supplied typed metadata and behavior probes; no application code or login
request was executed during native RE.

The native instance record is 136 bytes and remains opaque. An owned sidecar
retains the URL, copies the callback scheme and promotes the completion block.
The presentation provider uses the existing zeroing-weak storage, and the
ephemeral flag defaults to false. Disposal releases all these references
independently of isa and supports caller-provided storage. Constructor probes
also accept nil configuration; native starts with nil handlers were not tested.

With no provider or a nil anchor, canStart returns false without completing.
start returns false and synchronously reports NSError code 2 in
com.apple.AuthenticationServices.WebAuthenticationSession once. Inactive cancel
does not call the handler or prevent a later start. Receiver and block pins
allow completion to release its owning session. Presentation checks require
the runtime main thread, and nonatomic configuration needs app synchronization.

A native exploratory callback that called start recursively reached ASAN
stack overflow with joined status 134; its source and logs are retained.
A bounded follow-up confirms two callbacks for one nested native start.
Shared native sanitizer cases avoid this recursion. Vinix publishes completion
before calling user code and independently tests its reentrant start/cancel
guard. This deliberate guard differs from the native recursive error path.

Real authentication-browser presentation and login tokens remain unsupported.
A nonzero anchor rejects explicitly. Modern callback matching, additional
headers, copy, unavailable construction and reinitialization also reject.
No private AuthenticationServices state or browser engine is emulated.

All 66 programs build and 84 original generated C streams restore to recorded
hashes. Eighteen host suites pass ASAN/UBSAN in both hashing modes. Vinix passes
twenty Objective-C and 33 Swift/loader programs. Authentication fixtures cover
block promotion/disposal, weak providers, nil-anchor checks, ephemeral flags,
synchronous errors, inactive cancellation and repeat suppression. They also
check URL retention after pool drainage, scheme copying after source mutation,
owning release in completion, caller storage, 100 isa changes, eleven exact
rejection reasons and two shutdown cycles with zero live objects and blocks.
Generated C audits verify sidecar retirement and receiver/block pins. Earlier
compatibility checks remain enabled; failed compiler trials are retained.

Fortnite passes the authentication-session binding and exits with status 1
before entry at EOS's required `_OBJC_CLASS_$_UIImageView` import. Follow-up
metadata RE through installed Catalyst UIKit measures a 512-byte UIImageView
subclass of UIView; its constructors and application code were not executed.
Evidence is retained under `build/ios/fortnite/auth-checks`.
Full regression remains unpassed, the five
published runners are unchanged, and game entry, rendering and gameplay
remain unverified.

`UIImageView` now supports static bitmap images in V, including desktop
publication. EOS strongly imports the class and contains initWithImage and
setContentMode selectors. Installed Catalyst UIKit supplied its 512-byte
instance size, UIView superclass and method encodings. V probes measured
constructors, image sizing, flags, opacity and copied animation arrays;
no native window or application code was executed.

The opaque native record has an owned sidecar for normal/highlighted images,
immutable animation snapshots and one cached PNG path. Frame and zero-origin
bounds setters, sizeToFit, intrinsicContentSize, sizeThatFits and the measured
configuration properties preserve their argument/return ABI. Intrinsic size
uses the normal image, or the highlighted image when normal is absent;
changing highlighted state does not change that size. Empty views report
(-1,-1) intrinsic metrics and zero sizeThatFits. Initial image constructors
size the frame; later image assignment preserves its geometry.

Static rendering uses the existing CPU bitmap pipeline for thirteen content
modes, including aspect fit/fill and directional alignment. PNGs retain
premultiplied alpha through encoding and decoding. Highlighting selects the
alternate bitmap. Desktop serialization emits an image widget with the
configured interaction flag. Unchanged content reuses its PNG; updates get
a new pathname and remove the previous publication. Nil images clear it.
Raster contexts, wrappers and autorelease pools retire after encoding.

Sidecar disposal releases images/arrays and removes the cached file even
after isa changes or caller-owned storage destruction. Retained immutable
snapshots can outlive their view. Apps using VINIX_IOS_EXIT_ON_CLOSE remove
all image-view publications, including unattached views, before _Exit without
destroying storage that native workers may still read. Publication requires
the runtime main thread; nonatomic configuration needs app synchronization.

Active animation playback, nonzero bounds origins and unrepresentable
unclipped desktop overflow reject explicitly. Animation configuration copies
at most 256 bitmap images, and empty start/stop remain idle. Finite frames
accept nonnegative sizes through 8192 points per dimension; desktop rasters
cap 4096 pixels per dimension. Private ivars, symbol images, transforms and
broader inherited UIView behavior remain outside the profile.

All 67 programs build and 86 original generated C streams restore to their
recorded hashes. Nineteen host suites pass ASAN/UBSAN in both hashing modes.
Vinix passes twenty-one Objective-C and 33 Swift/loader programs. Image-view
fixtures compare five construction paths and public properties with native
UIKit. Runtime checks cover alpha/coverage for thirteen modes, highlighted
pixels, cache replacement and zero-size recovery, desktop serialization,
retained snapshots, explicit-exit cleanup, caller storage, 100 isa changes,
fourteen exact rejection reasons and two zero-live-object shutdown cycles.
Generated C checks verify geometry/retirement/close cleanup allocate no
scratch state and raster intermediates are released. Earlier checks remain.

Failed native/header compiler trials and a controlled validation restart
are retained. The restart source archive raced an edit; both snapshots are
preserved and the pre-edit snapshot was restored against the prior validated
source and generated C. Every final program was rebuilt with close cleanup.

Fortnite passes the UIImageView binding and exits with status 1 before entry
at EOS's required `_OBJC_CLASS_$_GCKeyboard` import. Evidence is retained under
`build/ios/fortnite/imageview-checks`. Full regression remains unpassed, the
five published runners are unchanged, and game entry, rendering and gameplay
remain unverified.

`GCKeyboard` now resolves its class and metaclass imports and supports
no-device discovery in V. Installed Mac GameController supplied the measured
32-byte NSObject subclass and `@16@0:8` coalescedKeyboard encoding. This Mac
returns nil when no physical keyboard is connected. Native explicit
construction creates a keyboard input profile, uses the main handler queue,
and reports Generic Keyboard/Keyboard vendor and product strings; assigning
nil clears the queue. EOS contains coalescedKeyboard, keyboardInput and
setKeyChangedHandler selectors. Native RE injected no input and ran no app code.

Vinix's desktop protocol currently delivers text pulses without physical key
press/release transitions. coalescedKeyboard therefore returns nil, including
through subclasses and concurrent callers. It allocates no device state and
synthesizes no connection notifications. Explicit construction, input profiles,
held-key polling and key callbacks remain unsupported. Selected construction,
profile and queue operations reject explicitly. Raw Objective-C storage retains
the measured opaque layout; private native ivars are not emulated.

All 68 programs build and 88 original generated C streams restore to recorded
hashes. Twenty host suites pass ASAN/UBSAN in both hashing modes. Vinix passes
twenty-two Objective-C and 33 Swift/loader programs. Keyboard checks cover
class/metaclass resolution, method encodings, inherited discovery, 5,000 queries
per cycle across main/worker threads, caller storage, six exact rejection
reasons and two shutdown cycles with zero live objects and blocks. Generated C
checks confirm the discovery functions allocate no scratch state. Earlier
checks remain enabled.

The first rejection fixture used a 64-bit V int array for pipe's 32-bit
descriptors and waited for EOF with its writer open. Its failed run and exact
source were archived before correction. A second failed trial caught the
missing respondsToSelector hook; both final sanitizer modes pass.

The batch also retains the stopped waiting verifier, a premature module replay
that failed before its host binary existed, and a missing native C++ fixture.
The recorded fixture hashes verified its restoration. Module replay was moved
after host completion; successful guest phases kept their original zero statuses,
serial logs and retirement hashes. Production source stayed frozen throughout.

Fortnite passes the GCKeyboard binding and exits with status 1 before entry at
EOS's required `_OBJC_CLASS_$_NSUUID` import. Follow-up V measurements show an
8-byte NSUUID class whose constructors return a 24-byte __NSConcreteUUID
subclass; canonical string parsing, copied bytes and version-4 generation were
measured against installed Foundation. No NSUUID runtime implementation changed
in this batch. Evidence is retained under `build/ios/fortnite/keyboard-checks`.
Full regression remains unpassed, the five published runners are unchanged,
and game entry, rendering and gameplay remain unverified.

`NSUUID` now supports its measured value APIs in V. EOS strongly imports the
class and contains UUID and UUIDString selectors. Installed Foundation probes
confirm the 8-byte NSUUID base, 8-byte _NSUUIDBridge and 24-byte __NSConcreteUUID
class cluster. Allocation returns the concrete class with zero bytes; new, init
and UUID generate secure version-4 identifiers through the existing entropy
adapter. No native application code was executed.

Canonical 36-byte UUID strings parse case-insensitively and render uppercase.
Invalid or nil strings return nil and consume the allocated initializer
receiver. Byte initializers copy sixteen bytes; nil bytes produce zero. Public
reinitialization matches native behavior, and immutable copies retain the same
object. UUIDString and description create independent autoreleased strings.
Equality and hashing use value bytes; comparison inspects all sixteen bytes
without stopping at the first difference. Foundation and CF collection paths
share these semantics, and classForCoder returns NSUUID.

UUID bytes live in the existing object metadata, so no sidecar or caller data
pointer is retained. Generic retirement frees them with their object even after
isa changes. Raw concrete caller storage is supported. Abstract or custom
subclass construction, coding, mutable copies, nil byte output, non-UUID
comparison, and invalid initializers that would consume caller-owned storage
reject explicitly. Private native ivars and archive formats remain unsupported;
reinitialization and other nonatomic access require app synchronization.

All 69 programs build and 90 original generated C streams restore to recorded
hashes. Twenty-one host suites pass ASAN/UBSAN in both hashing modes. Vinix
passes twenty-three Objective-C and 33 Swift/loader programs. Shared UUID cases
compare native allocation, defaults, copied buffers, canonical parsing, copy
identity, reinitialization, comparisons and 256 distinct version-4 IDs per
cycle. Runtime checks also cover collection equality/hash, owned descriptions,
caller storage, 100 isa changes, eight exact rejection reasons and two shutdown
cycles with zero live objects and blocks. Generated C verifies the UUID helpers
allocate no scratch state; formatting creates only an owned NSString.

A retained compiler trial caught the build driver's deeply nested fixture
expression. An explicit match now preserves all mappings and compiles, with
every mapped file checked for existence. The native C++ storage fixture was
restored from its recorded gzip/raw hashes before validation. Guest phases run
sequentially, and native module replay waits for the host binary to complete.

Fortnite passes the NSUUID binding and exits with status 1 before entry at
EOS's required `_OBJC_CLASS_$_NSFileManager` import. Evidence is retained under
`build/ios/fortnite/nsuuid-checks`. Full regression remains unpassed, the five
published runners are unchanged, and game entry, rendering and gameplay remain
unverified.

`NSFileManager` now resolves its class/metaclass imports and supports POSIX
directory creation and path queries in V. Installed Foundation measures a
32-byte NSObject subclass. EOS contains defaultManager and
createDirectoryAtPath:withIntermediateDirectories:attributes:error:. Native
probes exercised owned temporary files; no application code was executed.

The runtime owns one lazily created default manager until quiescent shutdown.
Explicit construction remains distinct. Existence queries follow symlink
targets and leave isDirectory untouched on failure. Readable, writable and
executable queries use native access checks. A nil delegate is supported;
nonzero delegate callbacks and copies reject explicitly.

Path and file-URL directory creation use actual POSIX mkdir/chmod operations.
Recursive creation accepts existing directories, including symlink targets,
and preserves their permissions. Each newly created parent and child receives
an explicit NSFilePosixPermissions attribute, overriding umask; defaults obey
umask. Nil and empty attribute dictionaries are accepted. Ordinary filesystem
paths and app synchronization apply; private native ivars remain opaque.

Failures return false and autorelease an owned NSError graph with a copied
NSFilePath and an underlying NSPOSIXErrorDomain error. Measured missing-path,
existing-item, non-directory, dangling-link and permission failures preserve
Cocoa codes 4, 516, 512 and 513 and the failing path component. Success leaves
a preexisting error output untouched. Other native errors currently use the
generic Cocoa write code 512; exhaustive Foundation error mapping remains
outside this profile. Paths are bounded to 1,023 bytes without embedded NULs.
Other directory attributes, non-file URLs and broader file-manager APIs
remain unsupported.

All 70 programs build and 92 original generated C streams restore to recorded
hashes. Twenty-two host suites pass ASAN/UBSAN in both hashing modes. Vinix
passes twenty-four Objective-C and 33 Swift/loader programs. Shared native and
runtime fixtures exercise real files, fourteen directory cases, error
ownership, permission/umask behavior, file URLs and guarded output bytes.
Runtime checks cover 8,000 concurrent singleton queries, caller-owned storage,
100 isa changes per cycle, ten exact rejection reasons and two shutdowns
with zero live objects and blocks. Generated C checks verify stack-only
path/stat/permission helpers, singleton retirement and error graph ownership.

Compiler trials retain the missing native header, V fixture declaration
corrections and an allocation-auditor variable collision. An archival helper
also moved a validation tool; the failed launch and original bytes are kept,
and the tool/source were restored byte-identically before the successful batch.
The native C++ fixture was restored from its recorded hashes. Guest phases
run sequentially and retire their payloads only after joined success; native
module replay waits for the host build.

Fortnite passes the NSFileManager binding and exits with status 1 before entry
at the required `_OBJC_CLASS_$_NSAutoreleasePool` import. Evidence is retained under
`build/ios/fortnite/filemanager-checks`. Full regression remains unpassed, the
five published runners are unchanged, and game entry, rendering and gameplay
remain unverified.

`NSAutoreleasePool` now resolves its class/metaclass imports and supports
manual pool scopes in V. Installed Foundation measures a 40-byte NSObject
subclass with retainCount 1. EOS contains addObject:, retainCount, release,
alloc and init selectors. Native probes measured pool lifetimes using a bare
NSObject probe class; no application code was executed.

New/init and allocWithZone:/initWithCapacity: create scopes shared with
objc_autoreleasePoolPush/Pop. drain and release consume the pool's constructor
reference. Both addObject: routes target the current innermost pool, even when
the receiver is an outer pool. Draining an outer boundary releases nested
contents and retires their Vinix pool wrappers. Destructor autoreleases and
new nested scopes remain within the draining boundary. Capacity is a hint;
native deprecated-method diagnostics and private pool caches are not emulated.

One reusable noslices boundary array accompanies each thread's existing
autorelease object list. Distinct opaque tokens cannot identify a different
thread's active scope. Fixed object metadata stores the owner thread and token,
so wrapper retirement still works after isa changes. Thread exit and quiescent
shutdown drain active scopes and free both arrays. Zeroing weak slots clear
when a wrapper retires; retained weak loads cannot bypass pool ownership rules.

At most 1,024 boundaries may be active on one thread. Retain, autorelease,
copy, reinitialization, subclass construction, caller-storage initialization,
active raw destruction, foreign tokens/thread drainage, nil addObject: and
reentrant drainage reject explicitly. Uninitialized caller storage can be
destructed normally. Exhaustive deprecated counters and private ivars remain
unsupported. Reentrant drainage uses a deliberate guard rather than attempting
to reproduce native undefined misuse.

All 71 programs build and 94 original generated C streams restore to recorded
hashes. Twenty-three host suites pass ASAN/UBSAN in both hashing modes. Vinix
passes twenty-five Objective-C and 33 Swift/loader programs. Shared native and
runtime fixtures verify nesting, C/class scope interoperation, current-pool
routing, capacity hints, destructor autoreleases, 500 empty boundaries and
404 threaded object retirements per cycle, including thread exit. Runtime
checks cover 100 isa changes with zeroed weak slots per cycle, uninitialized
caller storage, thirteen exact rejection reasons and two zero-live-object
shutdowns. Generated C confirms pop/retirement allocate no scratch and both
TLS arrays are freed. Earlier compatibility checks remain enabled.

The Mac restarted before the original RAM batch finished, losing its
temporary outputs. The final batch was rebuilt from persistent V helpers and
runs entirely on disk. No results from the lost RAM batch are reused. The compiler
executable is copied and pinned; its canonical V library and source/header
snapshots are hash-recorded and verified with the evidence. The native C++
fixture was restored from its recorded hash.

A retained disk trial found a driver argument list still selecting PATH v and
a native module-lookup helper inheriting Boehm C macros despite gc none. All
cross-build outputs were archived and rebuilt with the pinned compiler. The
helper's in-batch compile still failed after its passing preflight. Final
native-helper C is generated with the pinned compiler and compiled through
explicit Clang arguments, selecting malloc/free. Four native dyld orders
then pass. The seventy successful pinned cross-builds remain unchanged;
only the failed module fixture is rebuilt. Recovery-script differences
between driver templates and the earlier scoped-path compile failure are
retained. No production or fixture input changed during recovery.

Fortnite passes the NSAutoreleasePool binding and exits with status 1 before
entry at the required `_OBJC_CLASS_$_NSProcessInfo` import. Evidence is retained under
`build/ios/fortnite/autopool-checks`. Full regression remains unpassed, the five
published runners are unchanged, and game entry, rendering and gameplay remain
unverified.

`NSProcessInfo` now resolves its class/metaclass imports through a V adapter.
Installed Foundation measures a 48-byte NSObject subclass. EOS references
processInfo, arguments, operatingSystemVersion and isiOSAppOnMac. Shared typed
tests compare ordinary construction, singleton behavior, argument contents and
ownership, and the 24-byte OS version return/argument ABI against this Mac.
No application code is invoked by the native measurements.

The adapter supports that measured EOS selector subset, allocWithZone:,
isOperatingSystemAtLeastVersion: and isMacCatalystApp. Version queries share
the existing iOS 17.0 compatibility profile with UIDevice and Swift availability
checks. They use signed lexicographic comparison and Darwin ARM64's indirect
aggregate registers. The platform flags report the Vinix iOS profile.

App arguments are copied before image initialization, excluding the launcher's
command-line options. Each process-info instance owns a cached immutable array
in its existing metadata. Native Foundation may return fresh equivalent arrays;
the profile preserves contents and ownership while avoiding repeated allocations.
The shared instance and startup argument snapshot have one runtime-owned
reference each. Ordinary release, caller-storage destruction, isa changes and
quiescent shutdown retire arrays through existing ownership paths. Private
ivars, environment, process naming and hardware/power/activity APIs remain
unsupported. Argument mutation, late replacement, copies and missing aggregate
buffers fail explicitly.

All 72 programs build and 96 original generated C streams restore to recorded
hashes. Twenty-four host suites pass ASAN/UBSAN in both hashing modes; Vinix
passes 26 Objective-C and 33 Swift/loader programs. Process-info tests verify
copied Unicode arguments, retained snapshots after owner release, guarded
aggregate writes, signed comparison boundaries, 8,000 concurrent queries and
100 isa changes per cycle, caller storage, five exact rejection reasons and
two zero-live-object shutdowns. Generated C verifies owning cache retirement
and allocation-free repeated queries. Native module replay and earlier
compatibility suites remain enabled.

This batch runs on persistent disk with a copied pinned compiler and verified
canonical library/source snapshots. A fixture fixed-array compile failure and
an incorrect native array-identity assumption were corrected before the broad
batch. Its allocation-auditor trial is retained: V mangles the local name
array, so the audit now checks the owning field assignment without depending
on that spelling. Passed sanitizer outputs and their original generated C
were retained and audited. Guest payloads retire only after joined success.

Fortnite passes the NSProcessInfo binding and exits with status 1 before entry
at the required `_OBJC_CLASS_$_NSDate` import. Evidence is retained under
`build/ios/fortnite/processinfo-checks`. Full regression remains unpassed; the
five published runners are unchanged. Game entry, rendering and gameplay
remain unverified.

`NSDate` now resolves its Foundation and CoreFoundation class/metaclass
imports through a V adapter. The installed public class is eight bytes; this
Mac allocates a placeholder and replaces it with tagged or private dates.
Vinix uses its existing heap CFDate representation as an NSDate subclass,
with the immutable double and initialization flags in owned metadata. Apple
private/tagged layouts and bit-dependent hash values are not emulated.

EOS contains date, now, dateWithTimeIntervalSince1970:,
timeIntervalSinceReferenceDate, compare: and description selectors. Typed
Foundation/CFDate tests measure constructors, the 2001 reference epoch,
fractional intervals, FP/integer calling conventions, immutable copies,
ordering and UTC descriptions. Nil comparison returns equality, nil
earlier/later-date selection returns the receiver, and subtraction from a
nil date returns NaN, as measured. Equal ties select the receiver.

The adapter supports finite designated construction, current/distant dates,
epoch conversion, arithmetic, comparison, equality, hash, immutable copy and
whole-second UTC descriptions for years 1 through 9999. Its NSDate objects
share CFDate type/equality/hash/time operations and work with existing cookie,
condition, thread-sleep and certificate-date consumers. Existing CFDate
creation preserves its broader scalar profile and consumer bounds. Parsing,
coding, locale formatting, mutable copies, custom subclass construction and
reinitialization are outside the profile and reject explicitly. Native
NSDate alloc/init replacement is represented by one owned heap object.

This Mac tagged-date implementation turns a reference interval of -0.0 into
approximately -15.26 microseconds. The native measurement records that result
and its CFDate agreement separately. Vinix preserves direct double values,
and equal positive/negative zero dates have the same hash. Shared fixtures
use normal exact intervals; this difference is not claimed as native parity.

Distant dates have two runtime-owned cache references. Cache slots clear
before releasing their objects, and shutdown retires caches recreated by
autorelease destructors. All 73 programs build and 99 original generated C
streams restore to recorded hashes. Twenty-six host suites pass ASAN/UBSAN
in both hashing modes, including pure certificate calendar/trust regressions.
Vinix passes 27 Objective-C and 33 Swift/loader programs. Date fixtures cover
copied values and CF bridging, guarded caller bytes, 8,000 concurrent queries
and 100 isa changes per cycle, bare NSDate certificate-date acceptance, eight
exact rejection reasons, late cache creation and two zero-live-object
shutdowns. Queries/comparison/hash/copy/retirement allocate no scratch; UTC
formatting uses stack storage and one owned NSString. Native module replay
and earlier compatibility checks remain enabled.

Evidence runs on persistent disk with a copied pinned compiler and verified
canonical library/source snapshots. Preflight corrected a frame-accessor
name, a fixture umbrella-header dispatch_sync collision and an incorrect
negative-zero native assumption. Failed preflight outputs are not counted as
passed checks. Guest payloads retire only after joined driver success.

Fortnite passes the NSDate binding and exits with status 1 before entry at
the required `_OBJC_CLASS_$_NSInputStream` import. Evidence is retained under
`build/ios/fortnite/date-checks`. Full regression remains unpassed; five
published runners are unchanged. Game entry, rendering and gameplay remain
unverified.

`NSInputStream` now resolves its Foundation and CoreFoundation class/metaclass
imports through a V adapter, with the measured NSStream superclass. The public
classes have 8 and 136 bytes on this Mac; their private storage stays opaque.
Fixed owned metadata tracks initialization, cursor, status and descriptor.
Generic fields own a copied NSData snapshot or file path and an NSError graph.
The opened descriptor is statted once. Directory reads report POSIX EISDIR
even though the current guest kernel returns zero for a raw directory read.

The synchronous profile supports data, file-path and file-URL factories and
designated initializers, open/close, partial reads, availability, status/error
queries and getBuffer:length:. Mutable data is copied at initialization and
survives the source pool. Data snapshots retain the existing 16 MiB CFData bound
and paths retain the 1023-byte POSIX bound. Network URLs, default/abstract
construction, custom subclasses, reinitialization, copying, delegates,
run-loop scheduling, coding and seeking are outside the profile. Unsupported
operations reject explicitly; unsupported properties return nil/false.
EOS contains delegate/scheduling selectors, so those paths remain work ahead.
HTTPBodyStream and CFReadStream functions remain unsupported.

Typed installed Foundation calls measure both constructors and read/query
ABI. A data stream reaches EOF with its last bytes; a file stream reaches EOF
when a read returns zero, including a zero-length read. An empty data stream
can reach EOF during getBuffer:length:. Open streams offer no direct buffer
and leave its pointer output untouched while setting length to zero. Closed,
unopened and errored streams return the measured null/-1 outputs. Close
preserves errors and streams do not reopen. Retained NSError values outlive
the stream; native error object identity is not part of the contract.

All 74 programs build and 101 original generated C streams restore to recorded
hashes. Twenty-seven host suites pass ASAN/UBSAN in both hashing modes. Vinix
passes 28 Objective-C and 33 Swift/loader programs. Stream fixtures cover
mutable snapshots, pool-independent inputs and errors, partial/empty reads,
guarded outputs, 136-byte caller storage, 100 descriptor retirements after isa
changes per cycle, 12 explicit rejections and two zero-live-object shutdowns.
Descriptors are invalidated before close and retire independently of isa;
generic object destruction releases inputs/errors. Reads and queries allocate
no scratch. Earlier checks and native module replay remain enabled.

Evidence uses persistent disk, a copied pinned compiler and verified canonical
libraries/source inputs. Failed preflight assumptions about buffer pointer
outputs, empty-stream state and NSError identity were corrected before the
full batch; their outputs are not counted as passed checks. The first guest
batch exposed the directory-read difference and failed;
its joined outputs remain in inputstream-preflight-checks. The corrected
implementation was rebuilt and checked in a fresh stage. Guest payloads
retire only after joined driver success.

Fortnite passes the NSInputStream binding and exits with status 1 before entry
at the required `_OBJC_CLASS_$_NSURLConnection` import. Evidence is retained under
`build/ios/fortnite/inputstream-checks`. Full regression remains unpassed; five
published runners are unchanged. Game entry, rendering and gameplay remain
unverified.

`NSURLConnection` now resolves its Foundation class/metaclass imports through
a V adapter. Its measured NSObject subclass has 16 public bytes; private
Foundation state remains opaque. Fixed metadata tracks the lifecycle and
generic object fields own the original request, delegate and transport
snapshot. Delayed construction retains the supplied request: both getters
observe later mutations before start, as measured on this Mac. Vinix takes
an immutable transport snapshot at start and retains the original separately.

The local-file profile provides synchronous NSData/NSURLResponse loading and
asynchronous delegate callbacks on the main dispatch queue. Lifecycle calls
and scheduling use the main thread and default run-loop mode. Unscheduling
pauses delivery; scheduling resumes it. Cancellation before delivery sends no
callbacks, and cancellation from didReceiveResponse suppresses data and
completion. Delegates and connections stay alive through callback return.
Successful synchronous loads leave the NSError output untouched. Missing
files report NSURLErrorDomain/-1100 and directory reads NSPOSIXErrorDomain/21,
with failing URL information. Both outputs have guarded typed native cases.

Only regular local files are in the profile, with a 16 MiB body limit and
1023-byte POSIX paths. MIME classification distinguishes simple ASCII text
from binary bytes; full platform sniffing and extension mappings are absent.
HTTP/HTTPS loading remains unsupported and rejects explicitly. canHandleRequest
therefore reports this local-file capability rather than the Mac's broader
HTTP/HTTPS/data-URL protocol set. Other run-loop modes, background lifecycle,
operation-queue completion blocks, custom connection subclasses, default
construction, copying, coding, private properties and reinitialization are
unsupported. setDefersCallbacks: is ignored, matching the installed Foundation
measurement. Scheduling changes during callbacks and callback-driven runtime
shutdown reject explicitly.

All 75 programs build and 103 original generated C streams restore to their
recorded hashes. Twenty-eight host suites pass ASAN/UBSAN in both hashing modes.
Vinix passes 29 Objective-C and 33 Swift/loader programs. Shared native/Vinix
fixtures cover real file loading, errors, request ownership, callback order,
cancellation and delegate lifetimes. Runtime cases cover transport isolation,
pause/resume, guarded 16-byte caller storage, 100 pending isa changes per cycle,
13 exact rejections including real callback shutdown, and two zero-live-object
shutdowns with pending callbacks discarded. Every opened descriptor closes on
all returns. Body and registry arrays use noslices storage; generic fields
retire inputs and snapshots independently of isa. Dispatch stops before pending
connection references retire, and queued work has one explicit registry pin.

Evidence uses persistent disk, copied pinned tooling and verified inputs.
Preflight corrected mutable-request ownership, NSError output assumptions,
fixture dispatch initialization and the generated array-push symbol. These
failed outputs are not counted as passed checks. Disk pressure was relieved
by retiring only a quiescent failed prior run's temporary binaries/payloads
and duplicate toolchain; its logs, generated C and retirement hashes remain.
A later disk-full interruption during audit preparation was retained as a
failed attempt. Audits resumed through a joined V driver. Completed host and
guest executables are retained as gzip archives with verified restoration
hashes; runtime runners and module replay remain available. Guest payloads
retire after joined success; five published runners are unchanged.

Fortnite passes the NSURLConnection binding and exits with status 1 before entry
at the required `_$sBOWV` import. Evidence is retained under
`build/ios/fortnite/connection-checks`. Full regression remains unpassed.
Game entry, rendering and gameplay remain unverified.

`Builtin.UnknownObject` now resolves its Swift value-witness table
(`_$sBOWV`) through a V implementation measured against this Mac's installed
Swift runtime. All eight slots implement the eight-byte non-POD reference
layout, unknown-object retain/release, copy/take/assignment/destruction and
single-payload enum tags. Assignments publish the replacement before releasing
the previous owner, allowing destructor reentry without holding the registry
lock. The table occupies one read-only page per runtime lifetime and retires
after ARC workers and owned storage drain. Enum accesses support guarded,
unaligned eight/nine-byte storage without reading or writing adjacent bytes.
Builtin.NativeObject (`_$sBoWV`) and UnknownObject metadata imports remain
unsupported.

All 76 programs build; 105 original generated C streams restore to their
recorded hashes. Twenty-nine host suites pass ASAN/UBSAN in both hashing modes,
and Vinix passes 29 Objective-C and 34 Swift/loader programs. The shared native
and Vinix fixture checks Objective-C and native Swift owners, cross-domain
assignments, nil/tagged references, self copy/take, concurrent copies, enum
boundaries, eight concurrent publishers, destructor reentry and two drained,
sealed/unmapped runtime lifetimes. Generated-C audits confirm no scratch
allocations in the witness operations.

Evidence remains on persistent disk under `build/ios/fortnite/unknown-checks`,
with pinned tooling and input hashes. APFS cloning reclaims duplicate retained
tooling blocks while preserving every byte hash. Completed executable archives
restore to their original hashes, and guest payloads retire after joined success.
Five published runners remain unchanged. Fortnite passes this import and exits
with status 1 before entry at
`iOS: Objective-C metadata string exceeds 1023 bytes`. Full regression remains unpassed;
game entry, rendering and gameplay remain unverified.

The launch reaches EOSSDK metadata registration, whose longest method type
encoding is a valid 1,605-byte C++ unordered-map signature. The existing
1,023-byte metadata-string limit rejects it before image initializers run.
The initial next-blocker recorder expected another import failure; its failed
attempt remains recorded. A corrected V recorder and joined continuation
complete native module replay and generated-C validation.

`Objective-C type encodings` now use a separate bounded image reader
for methods and ivars. EOSSDK's exact 1,605-byte C++ method signature is accepted
and reflected by this Mac's installed Objective-C runtime, and Vinix retains
those bytes without widening selector, class-name or ivar-name limits. Types
remain opaque and bounded to 65,535 bytes. Every byte, including the terminator,
must lie in a file-backed loaded segment. Parsing returns borrowed views;
registered method/ivar metadata keeps its existing owned-copy lifetime. The
new oversized-type error borrows a static record instead of boxing a new error.

All 77 programs build and 107 original generated C streams restore to their
recorded hashes. Thirty host suites pass ASAN/UBSAN in both hashing modes.
Vinix passes 30 Objective-C and 34 Swift/loader programs. The encoding fixture
checks lengths 0, 1, 1,023, 1,024, 1,605 and 65,535; rejects 65,536 and missing
file-backed terminators; reads protected and guard-adjacent storage; handles
absolute, direct-relative and indirect-relative method lists; and verifies
owned reflection after unmapping the image storage across two drained lifetimes.

Evidence is retained under `build/ios/fortnite/encoding-checks`, with pinned
tooling, native metadata measurements, generated-C allocation audits and
verified executable/debug archives. Initial fixture-shutdown and error-boxing
audit failures remain as rejected trials. APFS cloning preserves pinned
library bytes while sharing canonical blocks; five published runners remain
unchanged. Fortnite passes the former short-type rejection and exits with
status 1 before entry at `__os_log_impl`. Full regression remains unpassed;
game entry, rendering and gameplay remain unverified.

`OS logging` now decodes measured compiler-produced records
through the fixed six-argument `_os_log_impl` family, rather than treating the
encoded buffer as varargs. Both MarketplaceKitWrapper formats are supported:
public C strings and public Objective-C descriptions. The installed Mac's
canonical log handles, disabled enablement, privacy descriptors and scalar
payloads are measured from V. LLVM decodes the scoped Swift error-type getter
as `mov w0, #16; ret`; a guarded raw call verifies preserved x20/x21.

The local policy writes complete messages to stderr, enables default/info/error/
fault and disables debug. Default and disabled data symbols name objects
directly. Textual subsystem/category pairs intern thread-safe runtime-owned
handles, recognized by Objective-C and Swift unknown-object ARC. Handle storage
is reclaimed after worker and Objective-C shutdown. Decoding and emission use
stack storage; public object descriptions run outside registry/sink locks and
drain temporary owners through a nested pool. Private/default dynamic content
is redacted without dereferencing its pointers. The entire record envelope and
format are checked before public content is read.

Labels are limited to 255 bytes, the cache to 256 pairs, records to 64, format
strings to 1,023 bytes, public content to 1,024 bytes and message bodies to
4,095 bytes. Basic signed/unsigned/hex/octal/pointer/character/floating scalars,
C strings, object descriptions and literal percent signs are supported. Width,
precision, errno/raw-data records and unsupported annotations reject explicitly.
Native OS_os_log methods, persistent log storage and configuration remain
unimplemented. The sink preserves errno and serializes each completed write.

All 78 programs build and 109 generated C streams restore to their hashes.
Thirty-one host suites pass ASAN/UBSAN in both hashing modes; Vinix passes
31 Objective-C and 34 Swift/loader programs. The logging fixture compares
Clang-produced buffers, checks guard-adjacent truncated records and bounded
strings, rejects mismatched formats before pointer reads, exercises reentrant
descriptions and 8,000 concurrent ownership cycles, invokes all four logging
entry points and drains two runtime lifetimes. The initial passing sanitizer
trial with a rejected generated-C stack-buffer allocation is retained.

Evidence is retained under `build/ios/fortnite/oslog-checks`, with pinned
tooling and inputs, native measurements, allocation audits and executable/debug
archives. Five published runners remain unchanged. Fortnite passes the former
OS logging import and exits with status 1 before entry at `_memset_s`.
Full regression remains unpassed; entry, rendering and gameplay are unverified.

`Secure memory filling` now implements the measured Darwin memset_s ABI
with fixed pointer/size/int32/size arguments and an int32 errno_t result.
The V implementation matches this Mac's libSystem: a null destination returns
EINVAL22 first; a maximum above RSIZE_MAX returns E2BIG7 without accessing
memory. An oversized count returns E2BIG7 above RSIZE_MAX or EOVERFLOW84 when
it only exceeds the declared maximum, and still overwrites that bounded
destination. Fill values convert to an unsigned byte; errno remains unchanged.
Zero-length calls with a nonnull destination perform no access. Destination
extent remains the caller's contract.

The implementation uses relaxed atomic byte stores so the secure overwrite
remains observable under optimization. LLVM inspection of an O3 caller whose
16-byte buffer is never read confirms that all 16 byte stores remain. The leaf
allocates no owner or scratch and introduces no runtime cache or lifetime.

All 79 programs build and 111 generated C streams restore to their hashes.
Thirty-two host suites pass ASAN/UBSAN in both hashing modes; Vinix passes
32 Objective-C and 34 Swift/loader programs. The new fixture compares the
installed native function's complete return/write matrix across null, zero,
RSIZE_MAX, oversized bounds/counts and three fill values; verifies unchanged
errno; and tests protected zero-length pointers and guard-adjacent overwrites.

Evidence is retained under `build/ios/fortnite/memset-checks`, with pinned
tooling and inputs, native and optimized-code measurements, allocation audits
and executable/debug archives. Initial ENOSPC build and host-control failures
are preserved as rejected trials; validated completed caches were reused while
incomplete suites reran without source changes. Five published runners remain
unchanged. Fortnite passes the former secure-memory import and exits with
status 1 before entry at `_$sS2SycfC`. Full regression remains unpassed;
entry, rendering and gameplay are unverified.

`Swift empty strings` now resolve the measured zero-argument constructor
`_$sS2SycfC` from libswiftCore. The installed Mac implementation returns the
canonical empty ASCII words `0` and `0xe000000000000000` directly in x0/x1.
LLVM decodes two constant moves and a return; guarded raw calls confirm
ignored incoming registers and preserved Swift context/error registers x20/x21.
The V constructor returns the same frozen two-word value without an owner,
metadata argument, cache or allocation, and matches the existing empty literal.

All 80 programs build and 113 generated C streams restore to their hashes.
Thirty-three host suites pass ASAN/UBSAN in both hashing modes; Vinix passes
32 Objective-C and 35 Swift/loader programs. The constructor fixture checks
exact library/symbol scoping, guarded direct and raw result registers before,
during and after two drained runtime lifetimes, 20,000 constructions with
unchanged owner/metadata registries, and the existing empty UTF-8 buffer's
trailing NUL and release lifetime. Other String APIs remain separately scoped.

Evidence is retained under `build/ios/fortnite/empty-string-checks`, with
pinned tooling and inputs, native instruction/ABI measurements, allocation
audits and executable/debug archives. Unjoined control attempts during disk
exhaustion are retained as rejected trials; validated completed caches were
reused with unchanged source. Transparent filesystem compression preserves
all prior evidence byte hashes. Five published runners remain unchanged.
Fortnite passes the former empty-string constructor import and exits with
status 1 before entry at `_$sSS10describingSSx_tclufC`. Full regression remains unpassed;
entry, rendering and gameplay are unverified.

`Swift describing values` now implement the measured consuming constructor
`_$sSS10describingSSx_tclufC` from libswiftCore. Native LLVM inspection and the
actual MarketplaceKitWrapper call at `0x8e28` show an indirect value in x0 and
type metadata in x1, followed by an owned String result in x0/x1. The wrapper
retains the caught Error before this consuming call. Guarded native calls
verify exactly one consumed error reference and preserved x20/x21 registers.

The V constructor transfers concrete String ownership and formats signed Int,
Void and concrete CFError values. Canonical one-word Error existential metadata
is sealed in the existing error arena and resolves the bounded `s5Error_p`
mangled name and the actual seven-byte indirect Error protocol reference plus
`_p`. CFError descriptions copy their fields before releasing the
input, matching native `Error Domain=... Code=...` text, including an empty or
one NSString `NSLocalizedDescription` userInfo field. General reflection,
arbitrary conformances, Swift error boxes, other error classes and additional
userInfo fields remain explicitly unsupported. Checked rejection leaves the
input unconsumed and borrows a static error without boxing an allocation.

All 81 programs build and 115 generated C streams restore to their hashes.
Thirty-four host suites pass ASAN/UBSAN in both hashing modes; Vinix passes
32 Objective-C and 36 Swift/loader programs. The new fixture covers protected
value boundaries, empty/inline/long/Unicode Strings, signed integer limits,
owned String transfer, concrete and existential errors, descriptions surviving
input release, invalid metadata/owners/fields, and two drained runtimes.

Evidence is retained under `build/ios/fortnite/describing-final-checks`, including
pinned tooling and inputs, native measurements, the actual image callsite,
allocation audits, and verified executable/debug archives. Prototype and
rejected native/compiler trials are retained with their sources. Transparent
filesystem compression preserves prior evidence bytes. Five published runners
remain unchanged. Fortnite passes the former describing constructor import and exits
with status 1 before entry at `_$sSS11withCStringyxxSPys4Int8VGKXEKlF`.
Full regression remains unpassed; entry, rendering and gameplay are unverified.

`Swift C strings` now implement the measured borrowed closure call
`_$sSS11withCStringyxxSPys4Int8VGKXEKlF` from libswiftCore. Native library and
MarketplaceKitWrapper measurements establish closure/context arguments in
x0/x1, borrowed String words in x2/x3, result metadata in x4, and caller-owned
indirect result storage in x8. The closure receives NUL-terminated UTF-8 bytes
in x0, its context in x20 and the original result pointer in x8. Native raw
calls verify preserved caller context, exactly one closure invocation, direct
callback result registers and the thrown error in x21; input String ownership
is unchanged. The native arm64e fixture signs its closure with discriminator
63553; Vinix ARM64 uses ordinary function pointers.

The V adapter copies the existing supported inline/native-tail String extent
into one owned UTF-8 buffer and adds NUL, including for an exactly bounded
large literal without readable source termination. It invokes the closure
outside registry locks and releases the temporary after success or a throw.
Generic result storage and thrown-error ownership remain with the caller.
The sealed adapter page is unmapped after callbacks drain at runtime teardown.
Foreign/shared String storage remains explicitly unsupported, and the CString
pointer expires when the closure returns. Rejected representations borrow a
static error without an additional allocation.

All 82 programs build and 117 generated C streams restore to their hashes.
Thirty-five host suites pass ASAN/UBSAN in both hashing modes; Vinix passes
32 Objective-C and 37 Swift/loader programs. The new fixture covers protected
Int/String/Void output boundaries, owned nontrivial String results, CFError
throws without ownership changes, empty/inline/long/Unicode/embedded-NUL
inputs, borrowed input ownership, bounded source copying, reentrant workers,
four concurrent readers, exact import scoping, rejected unsupported storage
and two drained/unmapped runtimes.

Evidence is retained under `build/ios/fortnite/cstring-final-checks`, with pinned
tooling and inputs, native ABI/instruction and actual callsite measurements,
allocation audits and verified executable/debug archives. Five published
runners remain unchanged. Fortnite passes the former CString import and exits
with status 1 before entry at `_$sSS8UTF8ViewV13_foreignCountSiyF`. Full regression remains unpassed;
entry, rendering and gameplay are unverified.

`Swift foreign UTF-8 counts` now implement the measured borrowed view helper
`_$sSS8UTF8ViewV13_foreignCountSiyF` from libswiftCore. Native library
measurements and MarketplaceKitWrapper's guarded call establish the borrowed
two-word UTF8View in x0/x1 and signed UTF-8 byte count in x0. Five real native
NSString-backed views verify UTF-16 code-unit counts versus UTF-8 byte counts,
Unicode expansion, surrogate pairs and embedded NUL, with unchanged ownership.
The application's call checks the foreign storage flag before this helper.

The V implementation accepts full UTF-16-indexed views over live registered
NSString owners or loader-validated constants, bounded to 1 MiB of UTF-8 text.
It validates the owner before reading isa or fields and keeps borrowed bytes
under the registry lock through UTF-8 and full UTF-16 extent validation.
UTF-16 constants use the loader's existing decoded UTF-8 cache. No owner,
temporary buffer, cloned text or boxed error is allocated; reference counts
remain unchanged. Native/inline/shared views and foreign UTF-8 indexing are
explicitly rejected by this foreign-only helper. Other Swift String operations
retain their existing storage limitations.

All 83 programs build and 119 generated C streams restore to their hashes.
Thirty-six host suites pass ASAN/UBSAN in both hashing modes; Vinix passes
32 Objective-C and 38 Swift/loader programs. The new fixture covers full UTF-16
extents, Unicode/NUL, decoded constants, four concurrent readers, guarded/dead
owners, invalid type/flags/count/UTF-8/bounds and two drained runtime lifetimes.
Evidence is retained under `build/ios/fortnite/foreign-count-checks`, with pinned
source/toolchain inputs, native ABI and actual callsite measurements, allocation
audits and verified executable/debug archives. Five published runners remain
unchanged. Fortnite passes the former foreign-count import and exits with
status 1 before entry at `_$sSS8UTF8ViewV13_foreignIndex5afterSS0D0VAF_tF`.
Full regression remains unpassed; entry, rendering and gameplay are unverified.

`Swift foreign UTF-8 indices` now implement the measured borrowed successor helper
`_$sSS8UTF8ViewV13_foreignIndex5afterSS0D0VAF_tF` from libswiftCore. Native
library and MarketplaceKitWrapper measurements establish the input index in
x0, borrowed UTF8View words in x1/x2 and returned raw index in x0. Every
successor matches native across five foreign Strings, all UTF-8 widths,
Unicode, embedded NUL, combining marks and surrogate pairs, without changing
input ownership. Additional native checks verify unmarked index alignment,
including a UTF-16 position inside a surrogate pair.

The V helper reuses the checked foreign view and its static borrowed errors.
An outer recursive registry lock protects borrowed text throughout validation
and scalar lookup. Bits 16..63 store the UTF-16 offset, bits 14..15 the UTF-8
position inside a scalar, and successor flags are 8 inside a scalar or 9 at
the next boundary. An unmarked surrogate interior aligns to its scalar start.
UTF-8-only indices, end/past-end positions, invalid transcoding and falsely
scalar-aligned surrogate interiors reject. The helper allocates no owner,
scratch, mapping or error box. It uses a linear scalar lookup over the existing
full UTF-16-indexed NSString/constant subset bounded to 1 MiB; other String
storage limitations remain.

All 84 programs build and 121 generated C streams restore to their hashes.
Thirty-seven host suites pass ASAN/UBSAN in both hashing modes; Vinix passes
32 Objective-C and 39 Swift/loader programs. The new fixture checks exact raw
successors, scalar alignment, four concurrent readers, decoded constants,
guarded/dead/empty/mismatched views, bad indices and two drained lifetimes.
Evidence is retained under `build/ios/fortnite/foreign-index-checks`, with pinned
source/toolchain inputs, native ABI and actual callsite measurements, allocation
audits and verified executable/debug archives. Five published runners remain
unchanged. Fortnite passes the former foreign-index import and exits with
status 1 before entry at `_$sSS8UTF8ViewV13_foreignIndex_8offsetBySS0D0VAF_SitF`.
Full regression remains unpassed; entry, rendering and gameplay are unverified.

`Swift foreign UTF-8 offsets` now implement the measured borrowed movement helper
`_$sSS8UTF8ViewV13_foreignIndex_8offsetBySS0D0VAF_SitF` from libswiftCore.
Native library and MarketplaceKitWrapper measurements establish the index in
x0, signed byte distance in x1, borrowed UTF8View in x2/x3 and raw result in x0.
The fixture compares 4,744 exact native results across five foreign Strings,
including forward/backward/zero movement, endpoints, Unicode, embedded NUL,
combining marks and surrogate pairs, without changing input ownership.

The V helper reuses the checked foreign view and static borrowed errors under
an outer recursive registry lock. Two linear scans map UTF-16/transcoding
indices to byte positions and back. Zero distance preserves the exact input
without reading the view. Positive movement sets flags 9 at scalar boundaries
or 8 inside a scalar; negative movement sets flags 8. Bounds are checked before
signed addition, including INT64_MIN/MAX. The helper allocates no owner,
scratch, mapping or error box. It supports the existing full UTF-16-indexed
NSString/decoded constant subset bounded to 1 MiB. UTF-8-only indices, invalid
transcoding, falsely scalar-aligned surrogate interiors and negative movement
from surrogate interiors reject; unmarked forward interiors align to the
scalar start. Other String storage limitations remain.

All 85 programs build and 123 generated C streams restore to their hashes.
Thirty-eight host suites pass ASAN/UBSAN in both hashing modes; Vinix passes
32 Objective-C and 40 Swift/loader programs. The new fixture also checks four
concurrent readers, constants, guarded/dead/empty/mismatched views, invalid
indices, signed bounds and two drained runtime lifetimes. Evidence is retained
under `build/ios/fortnite/foreign-offset-checks`, with pinned source/toolchain
inputs, native ABI and actual callsite measurements, allocation audits and
verified executable/debug archives. Five published runners remain unchanged.
Fortnite passes the former foreign-offset import and exits with status 1
before entry at `_$sSS8UTF8ViewV17_foreignSubscript8positions5UInt8VSS5IndexV_tF`.
Full regression remains unpassed; entry, rendering and gameplay are unverified.

`Swift foreign UTF-8 subscripts` now implement the measured borrowed byte helper
`_$sSS8UTF8ViewV17_foreignSubscript8positions5UInt8VSS5IndexV_tF` from
libswiftCore. Native code and MarketplaceKitWrapper measurements establish
the index in x0, borrowed UTF8View in x1/x2 and UInt8 in the low byte of w0.
Native returns can leave packed scalar data in upper w0 bits; native fixtures
read a UInt32 and mask its low byte instead of assuming C UInt8 zero extension.
All 375 byte reads match native across five foreign Strings, including all
UTF-8 widths, Unicode, NUL, combining marks, surrogate pairs and canonical,
directional and unmarked indices, without changing input ownership.

The V helper reuses checked foreign view validation and static borrowed errors
under an outer recursive registry lock. A linear scalar lookup maps UTF-16
offset/transcoding bits to an existing UTF-8 byte without encoding a scalar or
allocating an owner, scratch, mapping or error box. It supports the existing
full UTF-16-indexed NSString/decoded constant subset bounded to 1 MiB. UTF-8-only
indices, end/past-end positions, invalid transcoding and all UTF-16 surrogate
interiors reject. Other String storage limitations remain.

Connection fixtures use private directories and accept the measured native
NSURL or POSIX directory error with its matching domain; the runtime must
still report EISDIR. The failed prototype remains retained separately.

Game probes and audits completed on a temporary RAM disk after a disk-backed
archive was truncated. The failed construction hashes are retained alongside
the passed evidence.

All 86 programs build and 125 generated C streams restore to their hashes.
Thirty-nine host suites pass ASAN/UBSAN in both hashing modes; Vinix passes
32 Objective-C and 41 Swift/loader programs. The new fixture also checks four
concurrent readers, decoded constants, guarded/dead/empty/mismatched views,
invalid indices and two drained runtime lifetimes without retained storage.
Evidence is retained under `build/ios/fortnite/foreign-subscript-final-checks`, with
pinned source/toolchain inputs, native ABI and actual callsite measurements,
allocation audits and verified executable/debug archives. Five published
runners remain unchanged. Fortnite passes the former foreign-subscript import
and exits with status 1 before entry at `_$sSS9UTF16ViewV5index_8offsetBySS5IndexVAF_SitF`.
Full regression remains unpassed; entry, rendering and gameplay are unverified.

`Swift UTF-16 offsets` now implement the measured borrowed index helper
`_$sSS9UTF16ViewV5index_8offsetBySS5IndexVAF_SitF` from libswiftCore.
Installed macOS code and the MarketplaceKitWrapper callsite establish index
in x0, signed UTF-16 distance in x1, borrowed view in x2/x3 and raw result
in x0. All 18,706 native raw-index comparisons match across inline,
native-tail and bridged foreign Strings, forward/backward/zero/endpoints,
large distances, Unicode, NUL, combining marks and surrogate interiors.
Zero distance normalizes encoding/alignment flags; native backward jumps
of at least 64 units to zero use the cached start index. The initial native
flag mismatch and its original input/C/binary are retained separately.

The V helper uses stack inline scratch, bounded UTF-8 validation and linear
scans under the recursive registry lock, without allocation or ARC changes.
Foreign views retain their UTF-16 encoded offset; native views use UTF-8
encoded offsets with one transcoding unit inside a surrogate pair. Supported
storage is inline or native-tail String and the existing full registered
NSString/decoded constant subset, bounded to 1 MiB. Cross-encoding index
repair and shared/non-tail native storage reject; immortal native-tail bytes
remain caller-borrowed. Mortal native storage must be registered and fit its
capacity. Signed bounds are checked before addition, including INT64_MIN/MAX.

All 87 programs build and 127 generated C streams restore to their hashes.
Forty host suites pass ASAN/UBSAN in both hashing modes; Vinix passes
32 Objective-C and 42 Swift/loader programs. The fixture also tests four
concurrent readers, owned native storage, decoded constants, normalized
zero flags, guarded/dead/malformed/index/encoding rejection and two drained
runtime lifetimes. Evidence is retained under
`build/ios/fortnite/utf16-offset-checks` with pinned inputs and verified
executable/debug archives. The first broad run stopped at ENOSPC on the shared
Data volume. Completed evidence was preserved through a hash-verified move
to a verified owned 8 GiB RAM volume, where remaining checks resumed.
All evidence and compiler bytes are verified after persistence back to the
repository; both owned temporary RAM volumes are detached after retirement.
Five published runners remain unchanged. Fortnite passes the former UTF-16
offset import and exits with status 1 before entry at `_$sSTsE10compactMapySayqd__Gqd__Sg7ElementQzKXEKlF`.
Full regression remains unpassed; entry, rendering and gameplay are unverified.

`Swift Sequence compactMap` now implements the measured protocol-dispatched transform helper
`_$sSTsE10compactMapySayqd__Gqd__Sg7ElementQzKXEKlF` from libswiftCore.
Installed macOS code and the MarketplaceKitWrapper callsite establish
transform/context in x0/x1, Sequence/Result metadata in x2/x3, Sequence
witnesses in x4, borrowed self in x20, owned Array in x0 and thrown error
in x21. All 150 native comparisons match ordered Int/String/Objective-C
results, nil filtering, exhaustion, growth and throws. The actual Fortnite
closure casts Objective-C objects; registered Objective-C wrapper result
arrays now carry the measured verbatim capacity flag and use ARC witnesses.

The V implementation copies the borrowed Sequence before consuming
makeIterator, calls next and the throwing transform with indirect Optional
results, and destroys each owned input temporary and Iterator once.
Aligned stack scratch is bounded to 64 KiB per value; typed result tails are
bounded to 1 MiB. Relocation takes initialized elements and clears the old
count before releasing storage. Throws release partial results and forward
the original owned error; failed growth also destroys the produced Result.
No registry lock crosses a witness or transform. Complete direct associated
witnesses are supported; tagged mangled/accessor entries still reject.
Objective-C result metadata must be the canonical registered wrapper with
one-word ARC layout. Arbitrary Swift classes, class-constrained existential
result storage, covariance, reflection and NSArray bridging remain unsupported.

All 88 programs build and 129 generated C streams restore to their hashes.
Forty-one host suites pass ASAN/UBSAN in both hashing modes; Vinix passes
32 Objective-C and 43 Swift/loader programs. The compactMap fixture checks
exact input/result/error ownership, result-limit failure, four concurrent
readers, reentrant workers, guarded/tagged/mismatched/incomplete/retired
rejection, sealed adapters and two drained runtime lifetimes. Evidence is
retained under `build/ios/fortnite/sequence-checks`, including native protocol
and callsite inspection, original generated C, executable/debug archives
and pinned copies of the compiler and libraries actually used. The mutable
canonical V checkout is outside these build inputs. Checks ran on an owned
8 GiB RAM volume; evidence and compiler bytes were hash-verified after
persistence to the repository and that volume was detached. The initial
fixture compile failure is retained separately. Five published runners
remain unchanged. Fortnite passes the former compactMap import and exits
with status 1 before entry at `_$sSTsE5first5where7ElementQzSgSbADKXE_tKF`. Full regression remains unpassed;
entry, rendering and gameplay are unverified.

`Swift Sequence first(where:)` now implements the measured predicate helper
`_$sSTsE5first5where7ElementQzSgSbADKXE_tKF` from libswiftCore.
Installed macOS code and the MarketplaceKitWrapper callsite establish
predicate/context in x0/x1, Sequence metadata/witnesses in x2/x3, borrowed
self in x20, indirect Optional result in x8 and the original owned error
in x21. All 90 native comparisons match Int/String/Objective-C Optional
results, empty/missing/early matches, predicate throws and exact ownership.
The combined fixture also retains all 150 compactMap native comparisons.

The V helper shares checked complete direct Sequence/Iterator witnesses
with compactMap, copies borrowed self before consuming makeIterator, and
borrows each owned input temporary for the predicate. Rejected inputs are
destroyed; a match transfers ownership into the returned Optional. Iterator
is destroyed before successful output construction. Throws destroy input
and Iterator, forward the owned error without ARC changes, and leave output
untouched. Element's complete single-payload enum store-tag witness constructs
None/Some. Aligned stack scratch uses values bounded to 64 KiB; first(where:)
allocates no result array. Both helpers share one sealed adapter page per
runtime and hold no registry lock across a witness or callback. Tagged
associated-witness instantiation remains unsupported; caller metadata,
direct witnesses and borrowed storage must remain live throughout the call.

All 88 programs build and 129 generated C streams restore to their hashes.
Forty-one host suites pass ASAN/UBSAN in both hashing modes; Vinix passes
32 Objective-C and 43 Swift/loader programs. The combined Sequence fixture
checks four first(where:) readers and four compactMap readers, reentrant
lookup, guarded/tagged/missing-store/retired rejection and two drained
runtime lifetimes. Evidence is retained under
`build/ios/fortnite/sequence-first-checks`, with native and callsite inspection,
pinned copies of the actual compiler inputs, executable/debug archives and
verified committed sources. The mutable canonical V checkout is outside
the build inputs. Completed evidence and compiler bytes are hash-verified
after persistence from an owned 8 GiB RAM volume, which is then detached.
The first Swift guest staging stopped at a copied fixture-name mismatch;
its original build/staging evidence is retained separately. The one affected
fixture was rebuilt under its expected name, then remaining checks resumed.
Persistence was interrupted under shared-disk space pressure. The verified
RAM source was preserved, the identified partial copy was removed and the
copy resumed with additional free-space headroom before final verification.
Five published runners remain unchanged. Fortnite passes the former
first(where:) import and exits with status 1 before entry at `_$sSa28_allocateBufferUninitialized15minimumCapacitys06_ArrayB0VyxGSi_tFZ`.
Full regression remains unpassed; entry, rendering and gameplay are unverified.

`Swift Array buffer allocation` now implements the measured storage helper
`_$sSa28_allocateBufferUninitialized15minimumCapacitys06_ArrayB0VyxGSi_tFZ`.
Installed Swift code and the MarketplaceKitWrapper callsite establish minimum
capacity in x0, Element metadata in x1 and an owned one-word buffer in x0.
The native delegate reserves an aligned tail using Element stride, writes
count zero and derives capacity from allocated bytes. Vinix reserves the
exact requested minimum with the existing checked typed storage allocator.
Its count is zero before owner registration; callers construct the live
prefix and publish its count before release. Unused capacity is never
destroyed. Registered Objective-C wrapper elements keep their verbatim
capacity flag and ARC witnesses. Empty buffers share the immutable immortal
owner. Negative/overflowing capacities and unsupported or incomplete Element
layouts reject through the existing checks. Native capacity rounding,
arbitrary Swift storage classes, reflection and bridging remain unsupported.

The fixture checks the native and Vinix contract in 66 Int/String capacity
and initialized-count cases, owned String aliases, partially initialized
Objective-C buffers with a poisoned unused slot, custom alignments through
256, zero-sized elements, reentrant destroy callbacks, eight allocation
workers and two drained/unmapped runtime lifetimes. All 88 programs build;
130 original generated C streams restore to their hashes. Forty-two host
suites pass ASAN/UBSAN in both hashing modes, and Vinix passes 32 Objective-C
and 43 Swift/loader programs. Generated C confirms the stack out parameter
and initialized count before registration without hidden helper allocations.
Evidence is retained under `build/ios/fortnite/array-buffer-checks`, with
native/callsite inspection, pinned copies of actual compiler inputs, original
generated C and executable/debug archives. The mutable canonical V checkout
is outside the build inputs. Evidence and compiler bytes are hash-verified
after persistence from the owned 8 GiB RAM volume, which is then detached.
Five published runners remain unchanged. Fortnite passes the former buffer
allocator import and exits with status 1 before entry at `_$sSayxGSTsMc`.
Full regression remains unpassed; entry, rendering and gameplay are unverified.

`Swift Array Sequence conformance` now implements the measured generic table
`_$sSayxGSTsMc`. Native Swift and the installed interface establish nine
Sequence requirements, six callable operations and a two-word owned
IndexingIterator payload: Array owner and Int position. Complete canonical
tables are specialized by Element and publish direct associated metadata and
IteratorProtocol witnesses. Lookup accepts this registered Array/Iterator
family; other generic, resilient, conditional and foreign records still reject.

The V implementation transfers consuming Array ownership into the Iterator,
copies each returned Element and constructs Optional.some/none with Element
value witnesses. Count and the default contains optimization match native
Swift. Contiguous-array conversion transfers the native tail; copyContents
initializes the complete destination and returns its owned Iterator through
an explicit output pointer, with the end index in x0. Contiguous-storage
callbacks borrow a pinned owner, return owned Int/String/generic supported
results, forward the original x21 error and leave output untouched on throws.
No registry lock crosses an Element witness or closure. Code and descriptor
pages are sealed; specialization pages and caches retire after callbacks drain.
The records include instantiation callbacks using Swift's public
[generic witness-table layout](https://github.com/swiftlang/swift/blob/main/include/swift/ABI/Metadata.h).

Twelve native Int/String/Objective-C Array fixtures exercise all operations,
iterator copy/take/assignment and enum witnesses, repeated exhaustion,
contiguous callbacks and real Array integration with first(where:) and
compactMap. Runtime checks cover simultaneous first specialization, guarded
and forged metadata, insufficient destinations, retired lookup, constructor
trampolines and two drained/unmapped lifetimes. All 89 programs build and
132 original C streams restore to their hashes. Forty-three host suites pass
ASAN/UBSAN in both hashing modes; Vinix passes 32 Objective-C and 44 Swift/loader
programs. Evidence, native inspection, actual copied compiler inputs and
executable/debug archives are retained under
`build/ios/fortnite/array-sequence-checks`. Evidence and compiler bytes are
hash-verified after persistence from the owned 8 GiB RAM volume, which is then
detached. The initial fixture's malformed Int Optional.nil encoding and its
correction are retained separately. The first evidence recorder caught an
omitted fixture in the dedicated Swift VM staging and launch lists. Both lists
were corrected, PID 1 rebuilt and all 44 programs passed in a fresh VM; the
original logs and inputs remain under `guest-launch-recovery`. The mutable
canonical V checkout is outside the actual build inputs; five published
runners remain unchanged.

Supported storage consists of registered native typed tails and canonical
empty storage with complete supported Element witnesses. Foreign/bridged
arrays, arbitrary Swift classes, Collection witnesses, iterator reflection
and general conformance discovery remain unsupported. Caller metadata and
borrowed storage must stay live; callback Result values are bounded to 64 KiB.
Fortnite passes the former Array Sequence descriptor import and exits with
status 1 before entry at `_$sSayxGSlsMc`. Full regression remains unpassed;
entry, rendering and gameplay are unverified.


`Swift Array Collection conformance` now implements `_$sSayxGSlsMc` in V,
with usable direct associated tables for Int:Comparable, ArraySlice<Element>
and Range<Int>. Native SwiftCore, LLVM disassembly and the installed Swift
interface establish 24 Collection requirements, a four-word ArraySlice,
two-word Range and five-/three-word IndexingIterator payloads. Private
canonical metadata and tables are sealed after construction and cached by
the exact Element pointer. Unsupported metadata and mismatched conformance
families reject before dereferencing their contents.

The implementation supports borrowed subscript coroutines with normal/abort
cleanup, owned nested slices preserving original indices, indices ranges,
count/empty queries, signed index arithmetic, directional limits and early
range checks. Array/Slice search optimizations return the native unknown
result; Range<Int> supplies the known search/contains result. Slice and Range
Sequence tables support consuming iteration, contiguous copies, explicit
indirect copyContents results and contiguous-storage callbacks. Element
witnesses and closures run without registry locks; original x21 errors leave
the caller's output untouched. Larger value-buffer witnesses share compatible
registered Collection boxes and release the initialized payload at deallocation.

Twelve native Int/String/Objective-C Array fixtures exercise all operations
and the associated Slice/Range tables. Validation includes 100 signed Int
comparisons, copy/take/assignment, enum tags, boxed value buffers, callback
success/throws, constructor trampolines, concurrent first specialization and
two drained/unmapped lifetimes. Seven related host suites pass ASAN/UBSAN in
both hashing modes with errors configured to stop execution. Seven freshly
built suites pass in Vinix. All 17 host/guest programs, original C streams,
debug archives, input pins and actual game probe/audit logs are retained under
`build/ios/fortnite/array-collection-checks`. Native fixture input corrections,
the initial unaligned trampoline literal report and the executable archiver
path correction remain in the logs. The immutable predecessor compiler is
reused; compressed evidence is stored on Data and the owned RAM disk detached.

Support covers registered native typed Array tails, their native slices and
Int ranges. Foreign/bridged arrays, arbitrary Swift classes, general box
allocation, reflection/type discovery, generic conformance discovery and
Mutable/Bidirectional/RandomAccessCollection remain outside this subset.
Caller metadata and storage must stay live; callback results retain the
existing 64 KiB limit. Fortnite now passes the Array Collection import and
exits with status 1 before entry at MarketplaceKitWrapper's Set:Sequence
descriptor, `_$sShyxGSTsMc`. Full regression remains unpassed; entry,
rendering and gameplay remain unverified. Five published runners are unchanged.

The next implementation adds native Set:Sequence and Set.Iterator witnesses
in V, measured against this Mac's Swift library and its SDK interface. Set
metadata retains the exact Element/Hashable pair and its frozen ownership
word. Its complete Sequence table exposes direct Element/Iterator metadata,
the IteratorProtocol table and all six methods. The 40-byte iterator transfers
storage ownership and scans occupied bitmap buckets, including empty words;
it copies each element through the caller's value witnesses. Contiguous copying
builds an owned typed Array, `copyContents` returns an exhausted owned iterator,
and `withContiguousStorageIfAvailable` returns nil without invoking its closure.
Membership lookup uses the caller's raw-hash and Equatable witnesses with
linear collision probing. The native minimum-capacity constructor allocates
bounded typed storage or returns the sealed immortal empty singleton.

Iterator copies retain storage, takes transfer it, and ValueBuffer copies
share an owned box. Its measured enum layout has 126 spare payload cases;
additional cases use a tag byte after the 40-byte value. The heap destructor
destroys only occupied element slots before freeing its registered allocation.
Callbacks run outside the registry lock, and consuming copies keep storage live
until element callbacks finish. Generic witness construction only accepts
canonical Set/Iterator metadata, rejects mismatched families, and retires
specialization pages after owners and callbacks drain.

Twelve native Set fixtures and matching V fixtures cover dense and sparse
storage, collisions, reference elements, enum boundaries and boxed copies.
Additional cases use real Int hashing with signed limits. Both `first(where:)`
and `compactMap` preserve results, original x21 errors and element ownership.
Concurrent first specialization and two runtime lifetimes leave the Swift
ownership registries empty and the metadata pages unmapped. Nine focused
host suites pass ASAN/UBSAN in both hashing modes (18 runs); nine freshly
built suites pass in Vinix. All 21 programs and their original C streams,
debug archives, input hashes, fixture corrections and four VM logs are retained
under `build/ios/fortnite/set-sequence-checks`. Compressed evidence is persisted
on Data and the owned RAM build volume is detached before recording proof.

The supplied IPA now passes Set:Sequence and exits with status 1 before entry
at MarketplaceKitWrapper's required `Collection.first` getter,
`_$sSlsE5first7ElementQzSgvg`. This is a verified strong SwiftCore import in
the actual framework. Full regression remains unpassed; game entry, rendering
and gameplay remain unverified. The five published runners remain unchanged.

This subset covers registered native storage and complete caller-supplied
Hashable/value witnesses. Cocoa-backed sets, insertion/removal/resizing,
Set:Collection/SetAlgebra, native NSSet bridging, reflection and general generic
metadata/conformance discovery remain unsupported. The layout references are
Swift's public [Set storage](https://github.com/swiftlang/swift/blob/main/stdlib/public/core/SetStorage.swift),
[hash-table layout](https://github.com/swiftlang/swift/blob/main/stdlib/public/core/HashTable.swift)
and [metadata ABI](https://github.com/swiftlang/swift/blob/main/include/swift/ABI/Metadata.h).

`Collection.first` (`_$sSlsE5first7ElementQzSgvg`) now follows the caller's
Collection witnesses in V. Native SwiftCore disassembly and the installed SDK
interface establish Self metadata/table in x0/x1, borrowed Self in x20 and an
indirect owned Optional<Element> in x8. The getter obtains owned start/end
indices, compares them through Index:Equatable inherited from Comparable,
and destroys the end index before selecting the empty/nonempty path. For a
nonempty collection it copies the element while the subscript coroutine's
borrow is active, resumes that coroutine, destroys the start index and marks
the result as present. The empty path destroys both indices and returns nil.
An invalid yielded address invokes the valid continuation with abort cleanup
before rejecting; index cleanup leaves the destination untouched.

This supports the existing Array, ArraySlice and Range tables and caller
tables with complete direct associated metadata/conformances and supported
value witnesses. It uses aligned stack scratch and calls witnesses without
registry locks. It requires neither an iterator nor a copy or consumption of
Self. Tagged/incomplete associated witnesses still require instantiation;
general metadata or conformance discovery is outside this subset. The public
algorithm is described by Swift's [Collection implementation](https://github.com/swiftlang/swift/blob/main/stdlib/public/core/Collection.swift).

Ten ASan/UBSan runs pass across Collection, Set, Sequence, witness and Array
storage fixtures, each with normal and deterministic hashing. The same five
suites pass in a fresh Vinix ARM64 guest. Collection fixtures compare the
installed SwiftCore getter with the V implementation for twelve typed Array
cases, nested slices, Range limits and eight opaque caller tables. Owned
String indices verify destruction order; protected unused witness slots rule
out an iterator or Self-copy dependency. Runtime cases additionally verify
abort cleanup, untouched rejected output, lookup from another thread during
the borrow and two fully drained runtime lifetimes. Thirteen fresh generated-C
streams and executables, native measurements, input pins and VM probe/audit
logs are retained under `build/ios/fortnite/collection-first-checks`. These are
targeted regressions; the full iOS regression suite remains unpassed.

The supplied IPA passes this import and exits with status 1 before entry at
MarketplaceKitWrapper's required `UnsafeMutablePointer.deallocate` import,
`_$sSp10deallocateyyF`. Native disassembly on this Mac shows its shared pointer
deallocation entry sets size and alignment-mask arguments to -1 and tail-calls
`swift_slowDealloc`. That entry was unimplemented at that stage. Fortnite had
not entered application code.

Swift raw allocation now uses V adapters for `swift_slowAlloc`,
`swift_slowDealloc` and the typed/raw, mutable/immutable pointer `deallocate`
methods. Native SwiftCore disassembly and the installed SDK establish a raw
pointer in x0; the pointer methods replace size/alignment-mask arguments with
-1 and tail-call the raw deallocator. They inspect neither Pointee metadata
nor pointed-to values and perform no ARC release. The caller must deinitialize
stored values before freeing their storage.

Zero-size allocation provides one addressable byte. Valid masks request a
power-of-two alignment; -1 requests the native ARM64 default of 16 bytes.
Larger alignments use POSIX `posix_memalign`, and ordinary allocations use
`malloc`. Both return storage compatible with the runner's libSystem `free`.
The deallocator ignores its byte count, including the unknown-size sentinel,
and frees aligned storage through the same POSIX allocator. There is no
private header or Swift owner registry for raw memory. Overflowing allocation
sizes, malformed masks and allocation failures reject before returning a
pointer. These contracts follow Swift's public [heap implementation](https://github.com/swiftlang/swift/blob/main/stdlib/public/runtime/Heap.cpp).

Ten ASan/UBSan runs pass across raw allocation, heap, task allocation,
Collection and Array storage fixtures in normal/deterministic hashing modes.
The same five suites pass in a fresh ARM64 Vinix guest. Native comparisons
cover 63 raw layouts, 84 pointer frees and libSystem interoperability. Runtime
checks additionally preserve reference counts of stored objects, run eight
workers through 300 allocation/free cycles each, reject overflow/malformed
layouts and drain two runtime lifetimes. The dedicated `build-swift-raw-alloc`
target is included in public full-build, regression and Swift guest modes.
Thirteen generated-C streams/executables, native SDK/LLVM measurements and VM
evidence are retained under `build/ios/fortnite/raw-alloc-checks`. The initial
temporary driver catalogue omission and stale resume invocation are retained
as rejected trials; the missing fixture was freshly built before all five
guest suites passed. Generated C verifies only caller-owned payload allocation,
stack pointer scratch and borrowed static errors; its initial symbol-spelling
audit mismatch is also retained. Full iOS regression remains unpassed.

Both import audits resolve four more required imports across the supplied
images. The actual IPA probe now exits with status 1 before entry at
MarketplaceKitWrapper's required `UnsafeMutablePointer.deinitialize(count:)`
import, `_$sSp12deinitialize5countSvSi_tF`. Native disassembly records count in
x0, the raw pointer in x1 and the returned raw pointer in x0; the SDK describes
destroying initialized Pointee values without freeing their storage. This
entry was unimplemented at that stage. Fortnite had not entered application
code.

Pointer `deinitialize(count:)` and `swift_arrayDestroy` now use V adapters.
The method takes signed count/Self/Pointee metadata in x0/x1/x2 and returns
Self in x0. The runtime function takes pointer/unsigned count/Element metadata
in x0/x1/x2. Native SwiftCore disassembly confirms the method forwards to the
array runtime, which returns on zero count before reading metadata and skips
payload/destroy access for POD values. For non-POD values, the V implementation
reads the caller's complete direct value-witness table and calls its destroy
entry in ascending order at the advertised stride. It uses no iterator,
copy/take/tag witness, descriptor discovery, registry lock or scratch allocation.
The standard algorithm is documented in Swift's [array runtime](https://github.com/swiftlang/swift/blob/main/stdlib/public/runtime/Array.cpp).

Destruction preserves the caller's allocation and returns its original
pointer; a value's own destroy witness may modify its bytes. The caller frees
the storage separately. The adapter rejects negative method counts, malformed
metadata/table alignment, incomplete layouts, missing/misaligned destroy
entries, bad size/stride/alignment and address-range overflow before calling a
destroy witness. Complete caller-owned metadata and valid initialized payloads
remain prerequisites; general metadata instantiation is outside this subset.

Ten ASan/UBSan runs pass across pointer destruction, raw allocation, heap,
Collection and Array storage fixtures with normal/deterministic hashing.
The same five suites pass in a fresh Vinix ARM64 guest. Native comparisons
cover 24 typed ranges and 26 minimal caller-witness ranges, including owned
String/ObjC releases, padded and over-aligned elements, zero-size non-POD
callbacks, protected zero-count/POD paths and storage preserved until caller
free. Runtime cases additionally check lookup from another thread during
destruction, rejected layouts/range overflow and two drained lifetimes.
Generated C confirms no adapter allocation/free or registry lock, with
borrowed static failures. The public dedicated target, full build, regression
and Swift guest modes include the fixture. Evidence, thirteen generated-C
streams/executables and native measurements are retained under
`build/ios/fortnite/pointer-deinit-checks`. The initial name collision with
the existing Array value-witness destructor is retained as a rejected build;
the new bulk-destruction function uses a distinct name. Full iOS regression
remains unpassed.

Both audits resolve two more required imports across the supplied images.
The actual IPA now exits with status 1 before entry at MarketplaceKitWrapper's
required typed `allocate(capacity:)` import,
`_$sSp8allocate8capacitySpyxGSi_tFZ`. That entry was unimplemented at that
stage; Fortnite had not entered application code.

Typed `UnsafeMutablePointer.allocate(capacity:)` now resolves through a V
adapter. Native SwiftCore disassembly records signed count in x0, Pointee
metadata in x1 and the returned pointer in x0. It checks signed stride/count
multiplication overflow, normalizes alignments at most 16 to the default
manual-allocation path, and tail-calls `swift_slowAlloc`. The installed SDK
and Swift's [pointer implementation](https://github.com/swiftlang/swift/blob/main/stdlib/public/core/UnsafePointer.swift)
specify uninitialized storage occupying `count * stride` bytes. Native type
binding adds no runtime call in the measured body.

The V adapter requires complete direct value layout metadata, including at
zero capacity. It reads size, stride and alignment without calling any
copy/take/destroy/tag witness, discovering descriptors or initializing values.
Negative counts, missing/misaligned metadata tables, incomplete layouts,
invalid size/stride/alignment and signed allocation-size overflow reject
before allocation. The underlying raw allocator supplies one addressable
byte for zero capacity and enforces at least 16-byte alignment, including
zero-size element layouts. Storage has no private header, Swift owner or
registry entry. Callers initialize elements, deinitialize owned values, then
free the allocation separately.

Ten fresh ASan/UBSan runs pass across typed allocation, pointer destruction,
raw allocation, Collection and Array storage with normal/deterministic
hashing. These five suites also pass in a fresh Vinix ARM64 guest. Native
comparisons cover 60 Int/String/ObjC allocation/destruction/free lifecycles
and 20 minimal caller-layout cases with padded, over-aligned and zero-size
elements. Every unused witness points into protected memory. Checks write
the full stride extent, cover zero capacity, preserve object ownership until
explicit initialization, and observe four pointer deallocators and POSIX
free interoperability on this platform. That interoperability is a measured
native allocator property, not a portable Swift API guarantee. V checks also
exercise rejected layouts/overflow, eight concurrent workers and two drained
runtime lifetimes. Generated C verifies delegation to raw payload allocation
without scratch allocation or registry locking, and borrowed static failures.

The public dedicated `build-swift-pointer-alloc` target, full build,
regression and Swift guest modes include the fixture. Thirteen fresh
generated-C streams/executables, SDK/LLVM input pins, native measurements and
actual IPA probe/audit evidence are retained under
`build/ios/fortnite/pointer-alloc-checks`. An initial staging replacement
rejected before fixture generation is recorded; corrected staging completed
before the fresh cohort. Full iOS regression remains unpassed.

Both import audits resolve one more required import. The actual IPA passes
typed allocation linking and exits with status 1 before
entry at MarketplaceKitWrapper's required raw-buffer `copyMemory(from:)`
import, `_$sSw10copyMemory4fromySW_tF`. Its native disassembly is recorded for
the following implementation; Fortnite had not entered application code.

Raw-pointer and raw-buffer `copyMemory` now resolve through V adapters,
along with mutable/immutable raw-buffer `count`, `endIndex` and `baseAddress`
getters. Native SwiftCore disassembly and the installed SDK establish a
source/count/destination ABI in x0/x1/x2 for pointer copying. Buffer copying
takes source start/end in x0/x1 and destination start/end in x2/x3, checks
capacity, and forwards to the pointer method. The representation uses end
addresses, not element counts. Copying uses overlap-safe `memmove`, as
specified by Swift's [raw-pointer implementation](https://github.com/swiftlang/swift/blob/main/stdlib/public/core/UnsafeRawPointer.swift)
and [raw-buffer implementation](https://github.com/swiftlang/swift/blob/main/stdlib/public/core/UnsafeRawBufferPointer.swift.gyb).

The four count/endIndex getters share the native entry: Self start/end in
x0/x1 and signed Int result in x0. Complete nonnil buffers return end-start;
canonical nil buffers return zero. The base-address getters return the
original optional pointer word, with zero representing nil. Getters access
no viewed memory. The V checked span subset rejects malformed nil buffers,
reversed or oversized ranges, insufficient capacity, negative byte counts,
nonempty copies with null pointers and pointer/count overflow before copying.
Zero-byte copies access no payload. Callers still supply readable/writable
storage and follow Swift's raw-memory type rules. Valid calls need no owner
registry, value-witness call, allocation, free or ARC operation.

The final cohort passes ten fresh ASan/UBSan runs across raw copying,
typed allocation, raw allocation, Collection and Array storage in both hash
modes. These five suites also pass in a fresh Vinix ARM64 guest. Native
comparisons cover 140 whole-allocation copy cases, 28 page-edge ranges,
28 count/endIndex cases and 14 base-address cases. Checks include both
overlap directions, self/disjoint copies, unaligned bytes, protected empty
ranges, read-only sources, preserved neighbours/spare capacity, maximum
signed count and opaque address bytes without ARC changes. V cases also
reject malformed ranges before writes, run eight concurrent workers and
drain two runtime lifetimes. Generated C confirms `memmove`, no adapter
scratch allocation or registry locking, and borrowed static checked failures.

The public dedicated `build-swift-raw-copy` target, full build, regression
and Swift guest modes include the fixture. Thirteen final generated-C
streams/executables, native SDK/LLVM measurements and actual IPA probe/audit
evidence are retained under `build/ios/fortnite/raw-copy-checks`. Two passing
intermediate cohorts are retained with their sources as startup progressed
from copying to count and endIndex; every final stream was regenerated after
completing those accessors. Full iOS regression remains unpassed.

Both audits resolve three more required imports. MarketplaceKitWrapper's
three required raw-buffer imports now resolve. That cohort reached the
required generic `SetAlgebra` sequence initializer thunk,
`_$ss10SetAlgebraPyxqd__ncSTRd__7ElementQyd__ACRtzlufCTj`.

The generic `SetAlgebra.init(Sequence)` thunk now forwards through the caller's
witness table. Native Swift loads slot 20 (byte offset 160) from x4, passes
the selected slot address in x5 and its target in x6, then tail-branches.
The V entry emits the three ordinary ARM64 instructions for that dispatch;
native arm64e additionally authenticates the pointer with the storage address
and discriminator 62039. Integer arguments x0-x4/x7, indirect result x8,
Swift context/error x20/x21 and the original stack/LR reach the witness
unchanged. The caller supplies a valid table and callable initializer. The
witness consumes the source and initializes Self, including custom conformances;
the thunk reads no source, metadata or table header and performs no ARC,
allocation or registry locking. This implements dispatch, while concrete
SetAlgebra conformances and default initializer bodies remain separate work.
Swift's [protocol declaration and default implementation](https://github.com/swiftlang/swift/blob/main/stdlib/public/core/SetAlgebra.swift)
specify an owned Sequence and allow conforming types to provide the initializer.

The entry occupies 12 bytes at offset 960 in the existing Set code arena.
Instruction-cache flushing covers its end before the page is sealed RX;
the existing arena teardown releases it. Native comparisons exercise twelve
calls with protected table prefixes and opaque metadata, preserving register
and stack markers, 32-byte-aligned 48-byte indirect results, destination
canaries and witness-only source transfer or release. V checks also exercise
cross-thread lookup from inside the witness, repeated cached dispatch and
two drained runtime lifetimes. Generated C confirms fixed stack emission.

Ten fresh ASan/UBSan runs pass across SetAlgebra, Set, Sequence, witness and
Array storage in both hash modes. These five suites pass in a fresh ARM64
Vinix guest. The public `build-swift-set-algebra` target, full build, regression
and Swift guest modes include the fixture. Thirteen generated-C streams and
executables, native SDK/LLVM measurements and actual IPA probe/audit evidence
are retained under `build/ios/fortnite/set-algebra-checks`. Full iOS regression
remains unpassed.

Both audits resolve two more required imports, including MarketplaceKitWrapper's
SetAlgebra initializer dispatch. That cohort reached
`_$ss11_StringGutsV16_foreignCopyUTF84intoSiSgSrys5UInt8VG_tF`, the required
`_StringGuts._foreignCopyUTF8` import in MarketplaceKitWrapper.

Foreign UTF-8 copying now supports registered NSString owners and decoded
constant strings. Native ARM64 passes destination/count in x0/x1 and borrowed
guts in x2/x3; Optional<Int> returns its payload in x0 and nil discriminator
in the low byte of x1. The V implementation validates the span, existing
foreign discriminator, complete UTF-16 extent and stored UTF-8 before writing.
It holds the recursive registry borrow through `memmove`, copies exactly the
payload without a terminator, and adds no allocation, ARC or arena lifetime.
The caller supplies writable destination storage. Native/inline Swift guts,
unregistered owners and arbitrary NSString subclass methods remain outside
this checked foreign subset.

Insufficient capacity returns nil with the destination unchanged; empty
strings return zero without accessing the destination. Swift's
[copying contract](https://github.com/swiftlang/swift/blob/main/stdlib/public/core/StringGuts.swift)
leaves buffer contents unspecified on nil. A measured native deviation is
retained explicitly: some UTF-16-backed NSStrings treat zero capacity as a
length query and return a nonzero count without writes, while ASCII-backed
owners return nil. V consistently applies the capacity check, including zero.
The fixture records those native query outcomes separately from comparisons
of successful copying and positive insufficient capacities.

The new fixture passes both ASan/UBSan hash modes and a Vinix ARM64 guest.
Native measurements cover 285 capacity, unaligned and protected page-edge
cases, all UTF-8 widths, combining characters, embedded NUL, preserved buffer
neighbours and unchanged source ownership. V checks also cover decoded UTF-16
constants, nil/protected empty destinations, malformed spans/flags/counts,
unknown/protected/dead/wrong-type owners, invalid stored bytes, four concurrent
readers and two drained lifetimes. Generated host/guest C confirms borrowed
static checked errors, stack results and no adapter allocation or ARC.

Ten fresh sanitizer runs and five guest suites pass across foreign copying,
foreign count/subscript, UTF-16 offsets and raw copying. The dedicated public
`build-swift-foreign-copy` target, full build, regression and Swift guest modes
include the fixture. Thirteen final generated-C streams and executables,
native SDK/LLVM measurements, the original zero-capacity assertion trial and
actual IPA probe/audit evidence are retained under
`build/ios/fortnite/foreign-copy-checks`. Full iOS regression remains unpassed.

Both audits resolve one more required MarketplaceKitWrapper import. That cohort
reached `_$ss11_StringGutsVN`, its required `_StringGuts` type metadata.

`_StringGuts` now has independent canonical struct metadata, nominal descriptor
and complete accessor exports (`VN`, `VMn`, `VMa`). Native measurements show
size/stride 16, alignment 8, one field at offset zero and the same eight
value-witness entries and extra-inhabitant flags as String. The V records share
String's witness table while keeping distinct metadata and descriptor addresses.
The [frozen Swift declaration](https://github.com/swiftlang/swift/blob/main/stdlib/public/core/StringGuts.swift)
contains one `_object` field. String protocol conformances remain attached to
String; this does not add conformances for `_StringGuts`.

The records and 24-byte ARM64 accessor occupy unused space in the existing
two-page metadata arena. The accessor returns metadata/state Complete in x0/x1
for direct and relative descriptor calls. Cache flushing extends through byte
216 before RX/R sealing and publication. Repeated lookup adds no allocation,
ARC or new arena lifetime; the existing drained teardown retires both types.
The nominal descriptor has no Fields reflection record, matching the existing
nonreflectable subset. Textual `_StringGuts` mangled names and `_StringObject`
metadata remain separate work; existing bounded nominal accessor lookup works.

The new fixture passes both ASan/UBSan hash modes and a Vinix ARM64 guest.
Native comparisons cover nominal identity, complete accessor responses, all
eight witnesses, balanced native/ObjC/inline/immortal copy/take ownership and
single-payload enum tags through UINT32_MAX. Enum payloads respect eight-byte
alignment, with page guards and prefix/padding canaries. V checks also cover
eight concurrent lookup workers, distinct Array specializations for String and
`_StringGuts`, typed tail destruction and reentrant assignment deallocation from
another thread. Two runtime lifetimes drain their owners and metadata arenas.
Generated host/guest C confirms fixed emission and sealing order.

Ten fresh sanitizer runs and five guest suites pass across `_StringGuts`,
String metadata, Array storage, mangled lookup and protocol witnesses. The
dedicated public `build-swift-string-guts` target, full build, regression and
Swift guest modes include the fixture. Thirteen final generated-C streams and
executables, native SDK/LLVM measurements, retained fixture/audit correction
trials and actual IPA probe/audit evidence are under
`build/ios/fortnite/string-guts-checks`. Full iOS regression remains unpassed.

Both audits resolve the required `_StringGuts` metadata import. That cohort
reached MarketplaceKitWrapper's required
`_$ss13_StringObjectV10sharedUTF8SRys5UInt8VGvg` getter.

`_StringObject.sharedUTF8` and its `getSharedUTF8Start` delegate now return
borrowed storage through their measured ARM64 register ABI. Self occupies
x0/x1; the getter returns pointer/count in x0/x1, masking count to 48 bits;
the delegate returns the pointer in x0. Native disassembly and the
[Swift storage declaration](https://github.com/swiftlang/swift/blob/main/stdlib/public/core/StringObject.swift)
identify three paths: constant Cocoa owner+16, shared Swift owner+24, and
Cocoa `_fastCStringContents:` with NUL termination requested.

The checked subset validates owner registration before reading its fields.
UTF-8 NSString constants require matching byte counts. Ordinary Cocoa strings
provide stable ASCII backing with matching extent, using the existing 1 MiB
text bound; custom NSString subclasses can return borrowed UTF-8 through the
selector, invoked after releasing the registry lock. Shared Swift records
require a live registered heap allocation of at least 40 bytes and matching
count/flags at offset 32. Their initialized start pointer and backing lifetime
remain the caller's responsibility. The getter never copies, converts or
retains that payload. UTF-16 constants, unknown owners, tail/foreign/inline
representations, invalid flags, missing pointers and dead or undersized owners
are rejected. Shared-storage construction and general shared String operations
remain separate work.

Native fixtures compare constant Unicode/NUL and real Cocoa ASCII/NUL buffers,
getter/delegate pointer identity, unchanged ownership, both shared pointer
offsets and 48-bit counts with protected payloads. V fixtures also exercise
four readers, an unlocked reentrant subclass callback, rejected invalid states
and two drained runtimes. Ten fresh ASan/UBSan runs and five Vinix ARM64 guest
suites pass across shared UTF-8, foreign count/copy, String and heap ownership.
The public `build-swift-shared-utf8` target and full build/regression/Swift guest
modes include the fixture. Thirteen final generated-C streams and executables,
native SDK/LLVM measurements, the retained C-audit helper correction and actual
IPA probe/audit evidence are under `build/ios/fortnite/shared-utf8-checks`.
Generated C confirms the checked paths add no allocation or ARC and invoke
the subclass after unlocking. Full iOS regression remains unpassed.

Both audits resolve the required shared UTF-8 getter. That cohort reached
MarketplaceKitWrapper's required `_$ss23_ContiguousArrayStorageCMn` descriptor.

`_ContiguousArrayStorage` now has an independent canonical nominal declaration
in the existing Array arena. Native measurements identify a unique generic
class in module Swift, superclass `__ContiguousArrayStorageBase`, metadata
bounds of 3 negative and 19 positive words, one immediate member, no immediate
fields and one key `Element` parameter at metadata word 18. The V descriptor
provides that identity, superclass type mangling, bounds and generic header.
The [Swift descriptor ABI](https://github.com/swiftlang/swift/blob/main/include/swift/ABI/Metadata.h)
allows nullable accessor and reflection pointers. This declaration omits those
pointers, instantiation cache/pattern, overrides and native prespecializations;
its flags advertise only the supported unique generic class context.

Bounded mangled lookup now substitutes `Element` from either the canonical
Array or storage-class context, including nested Array expressions. It compares
context identities before reading arguments and leaves unused context/argument
pointers unread for nongeneric expressions. Arbitrary contexts and generic
descriptors supplied to the nongeneric accessor path are rejected. This is
declaration and context support: `CMa`, storage-class instantiation, reflection
and Objective-C inheritance remain unsupported. Existing Array owner headers
retain their private descriptor and are not exposed as class metadata.

The records occupy unused read-only space in the existing three-page Array
arena and are emitted before sealing and publication. They add no allocation,
map, executable code, ARC operation or teardown path. Native fixtures compare
the descriptor layout, three native complete class specializations and generic
context substitution at a protected argument boundary. V fixtures exercise
eight readers, unknown contexts without pointer reads, nested Array results,
private owner rejection and two drained/unmapped lifetimes. Mapping retirement
uses `mprotect` failure on macOS and `mincore` failure in the guest.

Ten fresh ASan/UBSan runs and five Vinix ARM64 guest suites pass across the
storage declaration, Array values/storage, mangled lookup and heap ownership.
The public `build-swift-array-class` target and full build/regression/Swift guest
modes include the fixture. Thirteen final generated-C streams and executables,
native SDK/LLVM measurements, retained compiler/C-string/retirement fixture
trials and actual IPA probe/audit evidence are under
`build/ios/fortnite/array-class-checks`. Generated C confirms fixed emission,
sealing order and the context comparison before argument reads. Full iOS
regression remains unpassed.

SwiftCore now exports `_$ss2eeoiySbx_xtSYRzSQ8RawValueRpzlF`, generic equality
for RawRepresentable values whose RawValue conforms to Equatable. Native
SwiftCore instructions and the installed SDK interface establish the call
sequence: borrow both Self addresses, obtain two owned raw values through the
getter's indirect result, call the caller's static equality witness with
RawValue metadata in `x20`, destroy the right value then the left, and return
only bit zero of the witness result. V preserves this sequence with two
16-byte-rounded stack temporaries, the existing getter adapter and a new
36-byte equality adapter in the existing sealed hashing page. It holds no
registry lock across getter, equality or destruction callbacks.

The checked subset requires caller-owned readable metadata, witness records,
code and Self spans to remain alive. It accepts complete raw-value layouts
through 64 KiB, power-of-two alignment through 16, compatible stride and
non-null required entries. Associated metadata can be direct or the existing
tagged String name. Unsupported layouts are rejected before getters execute;
this does not provide general pointer-span validation. No new heap owner,
registry or teardown path is added; callbacks must not retain temporary
addresses after returning.

Ten fresh ASan/UBSan runs and five Vinix ARM64 guest suites pass across
RawRepresentable equality/hashing, generic Hashable forwarding, Hasher and
integer hashing. The equality fixture compares native and V witness semantics,
arbitrary result high bits, indirect results and hidden contexts, reverse
destruction for POD/reference values and real Strings, tagged String metadata,
protected zero/odd/large values, reentrant callbacks and eight workers. Two
runtime lifetimes drain owners and retire the existing adapter page. The public
`build-swift-raw-equality` target and full build/regression/Swift guest modes
include it. Thirteen final generated-C streams and executables, native SDK/LLVM
inputs, generated-C allocation/callback audit and actual IPA probe/audits are
retained under `build/ios/fortnite/raw-equality-checks`. Full iOS regression
remains unpassed.

SwiftCore now supplies the `VN`, `VMn` and `VMa` records for Int8 and UInt8,
plus `_$sBi8_WV`. Native SwiftCore data, accessors and value-witness instructions
establish distinct canonical nominal identities with a shared one-byte POD
witness table. Each descriptor names its type in the Swift module, describes
one field at offset zero and points to an accessor returning complete metadata
for every request. Copy/take witnesses copy exactly one byte; destruction
reads nothing. Single-payload enum witnesses preserve native unaligned tag
bytes, tag-width transitions and UInt32 wrapping arithmetic. Reflection and
byte-type arithmetic/protocol conformances remain separate work.

The records and two complete accessors occupy unused space in the existing
integer arena, emitted before cache flushing and RX/RO sealing. They add no
mapping, owner, registry, ARC operation or teardown path. Callers must keep
borrowed value spans and metadata alive during witness calls. Existing
quiescent teardown retires both integer pages after owners and workers drain.

Ten fresh ASan/UBSan runs and five Vinix ARM64 suites pass across byte metadata,
integer hashing, Array values, mangled lookup and pointer destruction. Native
and V fixtures exercise all 256 byte patterns through every copy/take slot,
read-only sources and protected suffixes, self-copy, no-read destruction,
exact enum buffers through UInt32 wrapping, preserved `x20`/`x21`, complete
accessors, typed byte Arrays, symbolic nominal lookup and eight readers. Two
runtime lifetimes drain owners and unmap both arena pages. The public
`build-swift-byte-metadata` target and full build/regression/Swift guest modes
include the fixture. Thirteen final generated-C streams and executables,
native SDK/LLVM inputs, generated-C allocation/sealing audit, retained compiler
and native measurement trials, and actual IPA probe/audits are under
`build/ios/fortnite/byte-metadata-checks`. Full iOS regression remains unpassed.

SwiftCore now exports `_$sypN`, the full Any existential metadata record. The
export includes its value-witness prefix; the metadata address point is eight
bytes later, with kind `0x303`, no protocols and unconstrained existential
flags. Its eight value witnesses describe a 32-byte container: a three-word
value buffer followed by the contained type's metadata. Native SwiftCore data,
instructions and differential calls establish inline witness dispatch, boxed
ownership, exact take/copy behavior and enum encodings.

Same-type inline assignments call the contained assignment witness. A type
change moves the old inline payload into a 24-byte stack temporary, publishes
and constructs the new value, then destroys the old temporary or box. Boxed
copies share an existing owner; takes transfer it. Self assignment reads
nothing. Required callbacks are checked before mutation, with no registry lock
held across callbacks. The checked subset accepts complete inline layouts
through 24 bytes with alignment through eight, and canonical registered Any,
ArraySlice and Collection iterator boxes. Callers must keep readable initialized
containers, immutable metadata/witness records and code alive. Foreign boxes,
general `swift_allocBox`, protocol discovery and reflection remain unsupported;
this does not provide general pointer-span validation.

Full metadata, witnesses and private box records occupy unused space in the
existing error arena, emitted before cache flushing and RX/RO publication.
Private 48-byte Any boxes use the existing heap registry and ARC: their
destructor destroys the initialized inner value before exact deallocation.
They add no owner registry or arena teardown. Quiescent shutdown drains owners
and callbacks before retiring the existing metadata and code pages.

Ten fresh ASan/UBSan runs and five Vinix ARM64 suites pass across Any, String,
heap ownership, Collection and error-value metadata. Fixtures compare native
and V String/nested-box reference counts, same/different-type callback order,
publication, preserved `x20`/`x21`, protected 32-byte containers and 24-byte
buffers, unaligned enum buffers through UINT32_MAX, self assignment without
reads, reentrant lookup and eight readers. V additionally verifies registered
ArraySlice/iterator boxes, invalid layouts before writes and two drained heap
and arena lifetimes. The public `build-swift-any` target and full build,
regression and Swift guest modes include the fixture. Thirteen final generated
C streams and executables, native SDK/LLVM inputs, generated-C allocation and
lifetime audit, retained fixture trials and actual IPA probe/audits are under
`build/ios/fortnite/any-checks`. Final input pins include the newly added runtime
and test sources. Full iOS regression remains unpassed.

The exact Swift Core data export `__swiftEmptyArrayStorage` now returns the
existing canonical empty-array object directly. Native Swift confirms the
immortal reference bits, zero count, capacity flags and shared identity across
zero-capacity Int, String, Any, UInt8 and nested Array factories. Imported
payloads use the existing Array witnesses, ARC and Sequence count paths. The
existing lock publishes one read-only page; quiescent teardown retires it.
This adds no owner registry or arena. Its private typed-storage descriptor
still provides no native storage-class hierarchy, reflection, class casts or
ObjC bridging; `swift_getObjectType` rejects it as class metadata.

Ten fresh ASan/UBSan runs and five ARM64 Vinix suites pass across the singleton,
typed storage, Array Sequence, Collection and Any. Fixtures compare native
ownership and padded Array witnesses, concurrent lookup, immutable header
mapping permissions and two drained/unmapped lifetimes. The public
`build-swift-empty-array` target and full build, regression and Swift modes
include the fixture. Thirteen final C streams and executables, native SDK/LLVM
inputs, generated-C audit and actual IPA probe/audits are retained under
`build/ios/fortnite/empty-array-checks`. Full iOS regression remains unpassed.

Swift Core now exports `__swift_stdlib_bridgeErrorToNSError` for existing
CFError and ordinary Objective-C NSError instances, including registered
NSError subclasses. The SDK declares a consuming Error argument; native
Swift returns the same object, transferring its reference to the result.
The V bridge preserves identity and fields without allocation, retain,
release or autorelease. It checks live registered storage and class ancestry
before accepting an owner. Unknown, stale, releasing and private Swift heap
owners reject; native Swift error boxes still need lazy Error witnesses and
cache initialization and remain unsupported.
The CFError result keeps Vinix's private class and existing CF APIs/Error
witnesses; this export does not supply native NSError inheritance, class
casts or Objective-C property behavior for that private class. Ordinary
NSError instances retain their existing Objective-C behavior.

Ten fresh ASan/UBSan runs and five ARM64 Vinix suites pass across the bridge,
Error ARC, Error value extraction, localizedDescription and object type.
Thirty native/V field and ownership cases cover CFError, NSError and an ObjC
subclass, Int64 limits, repeated transfers, final domain disposal, preserved
`x20`/`x21`, eight workers, guarded rejection, weak zeroing and unlocked
destructor reentry. Native getter autorelease temporaries are drained before
reference-count measurements. The public `build-swift-error-bridge` target
and full build, regression and Swift modes include the fixture. Thirteen
final C streams and executables, native SDK/LLVM references, generated-C
allocation/lifetime checks, retained fixture trials and actual IPA probes
are under `build/ios/fortnite/error-bridge-checks`. Full iOS regression remains
unpassed.

Swift Core now exports `_swift_dynamicCast` for same-type complete value
metadata, canonical inline Any values and registered Objective-C class
wrappers. It follows the native ownership flags: bit 1 takes on success,
bit 2 destroys on conditional failure, and bit 0 requires success. A failed
conditional cast leaves the destination untouched. Successful casts invoke
the copy or take witness outside the runtime lock. Any construction publishes
contained metadata first; taking Any into Any transfers all 32 bytes,
including padding. Class-to-Any preserves the declared source class metadata.

The supported class path checks live registered storage and physical ancestry.
Swift classes, formal-class or `isKindOfClass:` overrides and Vinix's private
CFError class are excluded. Protocol discovery, optional/metatype conversion,
Foundation bridging, boxed Any conversions and unknown flag bits remain
unsupported. Same-type struct/enum/optional/tuple/metatype values up to
65,536 bytes require complete immutable caller-owned metadata, value witnesses
and callback code; pointer alignment and shape checks do not establish
arbitrary span safety.
Uninitialized destination storage must be disjoint from the initialized
source. Unsupported representations reject before writes or ownership changes
through static borrowed errors; unconditional failure terminates through panic.
Cast dispatch adds no allocator, registry, arena or teardown path.

Ten fresh ASan/UBSan runs and five ARM64 Vinix suites pass across dynamic
casts, Any, object type, String metadata and the error bridge. Native/V
fixtures compare ownership for long String and ordinary Objective-C
objects, Int/UInt8, inline Any wrap/unwrap/identity, class up/down/failing casts,
padding, preserved `x20`/`x21`, and custom value-witness traces for sizes
0/1/3/16/24/32. They also check unlocked reentry, guarded rejection and two
drained runtime lifetimes. The public `build-swift-dynamic-cast` target and
full build, regression and Swift guest modes include the fixture. Thirteen
final generated C streams and executables, pinned native SDK/LLVM references,
generated-C allocation/ownership checks, retained trials and actual IPA
probe/audits are under
`build/ios/fortnite/dynamic-cast-checks`; full iOS regression remains unpassed.

Swift Core also exports `_swift_dynamicCastObjCClass`. This conditional entry
takes a raw registered Objective-C class rather than Swift wrapper metadata.
It returns the same borrowed object on a matching class or superclass and nil
on an incompatible class, with no retain, release or autorelease. A nil input
returns nil before inspecting the target, including a protected target pointer.
Non-nil inputs require live registered storage, a matching ISA, positive
references and bounded registered physical class ancestry. Invalid targets,
tearing-down objects, Swift prefixes, private CFError storage, formal-class
overrides and `isKindOfClass:` overrides reject without calling a method or
changing ownership. Native Swift's overridden `class` and `isKindOfClass:`
behavior is measured separately and remains unsupported by this entry.

The cast reuses the existing ancestry check and borrowed static errors. It
creates no Swift metadata wrapper, arena, owner registry or teardown path.
Ten fresh ASan/UBSan runs and five ARM64 Vinix suites pass across this entry,
generic casts, object type, Any and the error bridge. The public
`build-swift-objc-cast` target and full build, regression and Swift
guest modes include its fixture. Native/V comparisons cover class/ancestor/
incompatible casts, repeated borrowed calls, nil before target reads, guarded
result buffers and `x20`/`x21`. V additionally checks concurrent readers,
registered constants, `object_setClass`, invalid or expired storage, cycles,
unlocked destructor reentry and two drained runtime lifetimes. Thirteen final
generated C streams and executables, pinned SDK/LLVM references, generated-C
allocation/ownership checks, retained fixture trials and IPA probe/audits are
under `build/ios/fortnite/objc-cast-checks`; full iOS regression remains unpassed.

Swift Core exports `_swift_getForeignTypeMetadata` for complete imported scalar
enum templates. MarketplaceKitWrapper's `UISceneActivationState` accessor passes
the request in `x0` and its complete enum template in `x1`; the response returns
metadata and state in `x0`/`x1`. Native comparisons confirm that separate templates
with the same imported identity return the first template, including an `N`
Clang-name override after the Swift name. Already complete templates return state
zero for blocking, nonblocking and abstract requests.

The entry accepts nongeneric imported enums with descriptor flags `0x60012`, no
payload, field metadata or initialization/completion callbacks, and complete
inline POD witnesses of size/stride 1, 2, 4 or 8. Names have a 1,023-byte bound;
related-entity/namespace tags, duplicate overrides, foreign classes/structs,
generic or payload enums, non-POD/incomplete witnesses and callbacks reject.
The image or caller supplies readable, immutable template, descriptor, witness
and name spans and keeps them mapped until quiescent runtime shutdown. A fixed
64-entry cache inside the runtime borrows those pointers and publishes canonical
identities under the existing lock, with no lookup allocation or ARC operation.
Shutdown clears its slots after workers drain. Additional identities and
incompatible widths reject without overwriting known entries.

Ten fresh ASan/UBSan runs and five ARM64 Vinix suites pass across foreign
metadata, metadata, ObjC casts, mangled lookup and Any. The public
`build-swift-foreign-metadata` target and full build, regression and Swift guest
modes include the fixture. Native/V comparisons cover imported identity aliases,
four scalar widths, all request bits, read-only templates, guarded response
storage and preserved `x20`/`x21`. V additionally checks concurrent publication,
malformed layouts/tags, cache exhaustion, retirement and two cleared cache
lifetimes before caller unmapping. Thirteen generated C streams/executables,
pinned SDK/LLVM references, the actual IPA accessor/template, generated-C
allocation checks and IPA probe/audits are retained under
`build/ios/fortnite/foreign-metadata-checks`; full iOS regression remains unpassed.

Swift Core additionally exports
`_swift_getTypeByMangledNameInContextInMetadataState`. Its five arguments are
request, bounded name, length, context and generic arguments; it returns a
metadata pointer. MarketplaceKitWrapper's abstract instantiation helper passes
request `0xff` and caches that pointer with a tag bit. Native Swift clears the
nonblocking bit before resolution, but nominal accessor traces show an abstract
request `0xff` for every tested public state, including complete lookup.

The entry supports requests `0`, `0x3f`, `0xff`, `0x100`, `0x13f` and `0x1ff`
within an active runtime. It reuses the existing bounded grammar and canonical
metadata caches, resolving through abstract accessor requests and requiring
complete nominal responses. Complete metadata satisfies every supported request;
incomplete responses, other state/flag combinations, generic nominal
initialization and deferred completion reject. Caller name, descriptor, accessor
and argument spans remain borrowed through the call. Accessors run outside the
runtime lock, and this entry introduces no cache, arena, ARC operation, owner
registry or teardown path. Existing four-argument lookup and direct nominal
helpers retain their complete request zero.

Ten fresh ASan/UBSan runs and five ARM64 Vinix suites pass across this entry,
legacy mangled lookup, foreign enum metadata, metadata and Array. Native/V
comparisons cover six public requests and abstract accessor traces, builtins,
nested Arrays, generic substitution, direct/indirect symbolic references,
embedded zeros, read-only descriptors/names, protected input boundaries,
guarded results and preserved `x20`/`x21`. V adds unsupported state/syntax/lifetime
rejection before callbacks, incomplete-response rejection, unlocked accessor
reentry, eight readers and two drained lifetimes. The public
`build-swift-mangled-state` target and full build, regression and Swift guest
modes include its fixture. Thirteen generated C streams/executables, pinned
SDK/LLVM references, actual IPA callers/type bytes, generated-C checks, retained
compiler/native expectation trials and IPA probe/audits are under
`build/ios/fortnite/mangled-state-checks`; full iOS regression remains unpassed.

Swift Core exports `_swift_initStackObject` for caller-owned object header
initialization. It takes opaque metadata and writable storage in `x0`/`x1`,
writes metadata and refcount word `5` into the 16-byte header, and returns the
storage pointer. The caller initializes and destroys its properties and owns
the storage lifetime. Metadata may be nil or inaccessible: this entry never
reads it. Native ARM64e signs nonzero metadata; Vinix stores its raw pointer,
as in the existing heap implementation. The SDK's stack-promoted refcount uses
two unowned references to prevent freeing the caller's memory.

Initialization requires naturally aligned, writable header storage and has no
runtime, allocator, lock, registry, destructor or ARC dependency. It changes no
bytes outside the header and retains no caller pointers. Stack ARC, unowned/
weak references, dynamic type queries, deallocation and full stack lifetime
tracking remain unsupported. Existing registry checks reject this storage before
reading it or freeing it; initialization does not create heap provenance.
MarketplaceKitWrapper's inspected StringGuts helper places the header at
`sp + 40` in a 112-byte frame. Supporting this initializer does not implement
that helper's full StringGuts behavior.

Ten fresh ASan/UBSan runs and five ARM64 Vinix suites pass across initialization,
owned heap, Array, object type and metadata-state lookup. Native/V comparisons
cover exact pointer-return ABI, native metadata signatures and refcount word,
nil/arbitrary/protected metadata, four header offsets, untouched property/guard
bytes, a header ending at a protected page, repeated real frame storage and
preserved `x20`/`x21`. V additionally checks runtime-independent initialization,
eight private frame workers, invalid storage, Core-only export spelling,
rejection of stack ARC/type/deallocation before and after caller unmapping, and
two empty runtime lifetimes. The public `build-swift-stack` target and full
build, regression and Swift guest modes include its fixture. Thirteen generated
C streams/executables, native SDK/LLVM references, actual IPA caller instructions,
generated-C allocation/ownership checks and IPA probe/audits are retained under
`build/ios/fortnite/stack-checks`; full iOS regression remains unpassed.

Swift Dispatch exports the DispatchWorkItemFlags metadata accessor and nominal
descriptor, `_$s8Dispatch0A13WorkItemFlagsVMa` and
`_$s8Dispatch0A13WorkItemFlagsVMn`. The installed runtime and SDK expose one
8-byte UInt field at offset zero, POD/inline value witnesses, no extra
inhabitants and a complete metadata response in `x0`/`x1`. Copies, takes and
assignments preserve the word; destruction performs no reads or ownership
work. Its single-payload tag store writes a nonzero tag's payload even with
zero empty cases, and writes the extra tag byte only with nonzero empty cases.

Vinix keeps this nominal identity distinct from Int and resolves both exports
only in `/usr/lib/swift/libswiftDispatch.dylib`. One runtime-owned adjacent
two-page arena contains an RX accessor and read-only metadata, witnesses and
Dispatch module/type descriptors. Publication follows both page protections
under the runtime lock. The complete accessor ignores its request, including
the tested all-ones request, and the existing symbolic metadata lookup reuses
its descriptor. The descriptor has the measured field offset and its accessor;
field reflection and native descriptor initialization extensions are omitted.
OptionSet/RawRepresentable conformances, named flags constants and Swift queue
adapters remain unsupported. SetAlgebra and basic QoS support are described
below.

The caller borrows metadata and accessor pointers through the active runtime
lifetime. Shutdown requires users and callbacks to have drained; it marks
resolution retired, unmaps the arena and clears its pointer. Resolution before
startup or after teardown rejects. Cached pointers must not be invoked after retirement.
MarketplaceKitWrapper has eleven inspected calls to the accessor, including
Array allocation and SetAlgebra witness lookup helpers; this metadata change
does not implement those helpers' complete behavior.

Ten fresh ASan/UBSan runs and five ARM64 Vinix suites pass across Dispatch flags,
String metadata, Array, mangled lookup and metadata-state lookup. Native/V
comparisons cover pointer/state returns, seven request forms, preserved
`x20`/`x21`, descriptor and witness layout, guarded copy/take/self-assignment,
protected eight-byte payloads and unused metadata, no-op destruction, enum
tag/payload bounds, UInt32 wrapping and canonical indirect symbolic lookup.
V additionally checks eight concurrent resolvers, exact library/export spelling,
RX/RO protections, unsupported exports before allocation and two drained,
unmapped lifetimes. Generated C verifies one arena allocation, both protections
before publication, failure/shutdown cleanup, static borrowed errors and POD
witnesses without extra allocation, ARC, locks or metadata reads. Thirteen C
streams/executables, SDK/LLVM references, actual IPA call sites, retained helper
and guard-expectation trials and IPA probe/audits are under
`build/ios/fortnite/dispatch-flags-checks`; full iOS regression remains unpassed.

The metadata-only IPA probe got past both flags metadata imports and exited
with status 1 at MarketplaceKitWrapper's required SetAlgebra conformance record,
`_$s8Dispatch0A13WorkItemFlagsVs10SetAlgebraAAMc`, in
`/usr/lib/swift/libswiftDispatch.dylib`.

Swift Dispatch now exports that conformance record. Vinix supplies a complete
concrete SetAlgebra table with all 21 requirements, inherited Equatable and
ExpressibleByArrayLiteral tables, and complete Flags metadata in both
associated-type slots. These are private concrete records, rather than the
installed runtime's resilient/generic descriptor with a null witness pattern.
Ordinary witness lookup validates the exact nominal Self metadata before
returning any of these tables. The existing Flags mapping holds the tables,
protocol descriptors and ABI bridges; its Swift module and Equatable protocol
identity come from the canonical Int arena, which outlives it.

Scalar operations borrow one-word operands. Swift carries Self in `x20`;
result-producing methods use `x8`, except insert's member result in `x0` and
Bool return in `w0`. Remove/update return a nine-byte Optional: the payload is
the overlapping bits, and zero overlap returns nil with a zero payload. Insert
returns the supplied member and reports whether any new bits were added.
Contains, subset, superset, disjointness, empty, unions, intersections,
differences and in-place operations follow the installed native witnesses.
Bridges preserve `x20`/`x21` and use allocation-free V scalar bodies.

Empty initialization returns zero. Array-literal and generic Sequence
initialization OR every element and consume exactly one source reference.
Generic initialization accepts canonical Vinix Array<DispatchWorkItemFlags>
metadata, its canonical Sequence table and registered POD storage, including
the immortal empty array. It receives source, Sequence metadata, Sequence
witness, Self metadata and Self witness in `x0` through `x4`, with the result
in `x8`. The existing SetAlgebra dispatcher selects this constructor at byte
offset 160. Foreign/custom sequences and malformed storage reject before
reading foreign headers or invoking callbacks, without publishing a result or
consuming the source. OptionSet/RawRepresentable conformance, named constants,
reflection and Swift queue adapters remain unsupported.

The supplied MarketplaceKitWrapper's default async flags constructor at
`0x70a8` prepares this exact argument order. Its witness accessor at `0xc098`
loads the required conformance and calls ordinary witness lookup with Flags
metadata. Both instruction sequences are retained without executing app code.
The first native constructor trial trapped because the fixture initially
placed Self metadata before the Sequence arguments; retained native
disassembly and the crash report established the corrected ABI.

Ten fresh ASan/UBSan runs and five ARM64 Vinix suites pass across Dispatch
SetAlgebra, Dispatch metadata, generic SetAlgebra dispatch, Array Sequence and
witness lookup. Checks compare every scalar/inherited equality operation over
zero, overlapping and high-bit values, guarded optional payload/tag writes,
preserved Swift context/error registers, literal/direct/dispatched construction
over empty and populated arrays, and one-reference source consumption. Vinix
also checks canonical associated metadata, protected foreign-profile rejection,
malformed counts without partial writes or release, eight concurrent resolvers
and two quiescent unmapped lifetimes. Generated C confirms no extra bridge or
scalar allocation, sealed publication, validation before foreign reads and one
unlocked Array release. Thirteen C streams/executables, SDK/LLVM/IPA references,
native trial diagnostics and guest probes/audits are retained under
`build/ios/fortnite/dispatch-algebra-checks`; full iOS regression remains unpassed.

The SetAlgebra-only IPA probe got past that conformance and exited with
status 1 at MarketplaceKitWrapper's required DispatchQoS.unspecified getter,
`_$s8Dispatch0A3QoSV11unspecifiedACvgZ`, in
`/usr/lib/swift/libswiftDispatch.dylib`. Fortnite has not entered application
code and remained unplayable at that stage.

Swift Dispatch now exports DispatchQoS's unspecified getter, complete metadata
accessor and nominal descriptor: `_$s8Dispatch0A3QoSV11unspecifiedACvgZ`,
`_$s8Dispatch0A3QoSVMa` and `_$s8Dispatch0A3QoSVMn`. The native getter initializes
the QoSClass byte to tag 5 and the relativePriority word at offset eight to zero,
through the indirect result in `x8`. It leaves seven padding bytes untouched.
Vinix adapts that ABI to a V body and preserves `x20`/`x21`.

The distinct nominal metadata describes a 16-byte POD value, stride 16,
alignment eight, packed u32 field offsets zero/eight and 250 extra inhabitants.
Copy, take and assignment move all 16 bytes, including padding, with both words
loaded before either is stored. Destruction reuses the existing no-op witness.
Optional populations through 250 use unused QoSClass byte values; larger
populations use a tag byte at offset 16 and a UInt32 payload. The get/store
witnesses reproduce native branches, wrapping arithmetic and exact payload/tag
writes, including large tags with zero empty cases. Metadata responses are
complete and ignore the request, and symbolic descriptor lookup reuses them.

QoS shares the existing runtime-owned adjacent Dispatch pages. Its getter and
accessor are RX; metadata, witnesses and a private nongeneric descriptor are RO.
Both protections precede publication under the runtime lock. Cached entries
remain borrowed until users have drained and the shared mapping is unmapped.
Reflection, native descriptor initialization extensions, QoSClass's separate
metadata/conformances, QoS equality, other named constants/constructors and
Swift queue adapters remain unsupported.

Ten fresh ASan/UBSan runs and five ARM64 Vinix suites pass across QoS, Dispatch
flags, SetAlgebra, String metadata and Array. Native/V checks cover getter
padding and result guards, protected unused arguments, Swift context/error
preservation, nominal layout, every metadata request, guarded 16-byte copies,
self-assignment and overlap, no-op destruction, all 256 class byte values,
both optional populations and UInt32 wrapping. Vinix checks exact export/library
scope, symbolic lookup, typed POD Array ownership, eight concurrent resolvers,
RX/RO protection and two quiescent unmapped lifetimes. Generated C confirms
allocation/ARC/lock-free value bodies and sealing before publication. Thirteen
C streams/executables, SDK/LLVM references, eight actual MarketplaceKitWrapper
QoS call sites, the retained header-generation trial and IPA probes/audits are
under `build/ios/fortnite/dispatch-qos-checks`; full iOS regression remains unpassed.

The QoS-only IPA probe got past the getter and metadata accessor and exited
with status 1 at MarketplaceKitWrapper's required DispatchQueue.main getter,
`_$sSo17OS_dispatch_queueC8DispatchE4mainABvgZ`, in
`/usr/lib/swift/libswiftDispatch.dylib`. Fortnite has not entered application
code and remains unplayable.

Swift Dispatch now exports that main queue getter. It returns the existing
registered Vinix main queue as an owned object in `x0`, preserving `x20`/`x21`
and ignoring `x8` and the incoming Swift context. The installed native getter
returns `_dispatch_main_q` through an autoreleased-return shim and then claims
the owned reference. Vinix uses its shared Objective-C retain path; the main
queue is immortal, so calls reuse its identity without reference-count churn.
Seven MarketplaceKitWrapper call sites use this direct object return.

Swift unknown-object ARC now recognizes registered dispatch queues before
checking Objective-C or Swift heap storage. Classification reads only the
scheduler registry, releases its mutex before taking the Objective-C lock,
and sends queue ownership to the existing dispatch retain/release functions.
Ordinary queues retain their scheduler reference counts. Queue identities
remain valid during worker/callback quiescence and expire at system-data
teardown. The getter requires an active scheduler and rejects after stopping.
Its bridge shares the existing sealed Dispatch mapping and expires when that
mapping is retired. Swift queue metadata, type queries, weak references,
async adapters and other methods remain unsupported.

Ten fresh ASan/UBSan runs and five ARM64 Vinix suites pass across the main
queue, QoS, SetAlgebra, unknown-object witnesses and the existing scheduler.
Checks cover native/V identity and ownership, protected unused arguments,
preserved Swift registers, value witnesses, ordinary queue reference counts,
eight concurrent resolvers, main-thread/reentrant callbacks, shutdown
cancellation and two retired/unmapped lifetimes. Generated C verifies no new
per-call allocation, registry-only classification and sealed publication.
Thirteen C streams/executables, native/IPA references, recovered archive and
VM trial evidence, and completed probes/audits are retained under
`build/ios/fortnite/dispatch-main-checks`; full iOS regression remains unpassed.

The main-queue-only IPA probe got past the getter and exited with
status 1 at MarketplaceKitWrapper's required
`DispatchQueue.async(group:qos:flags:execute:)` adapter in
`/usr/lib/swift/libswiftDispatch.dylib`:
`_$sSo17OS_dispatch_queueC8DispatchE5async5group3qos5flags7executeySo0a1_b1_F0CSg_AC0D3QoSVAC0D13WorkItemFlagsVyyXBtF`.
Fortnite has not entered application code and remains unplayable.

Swift Dispatch now exports the async adapter for the supplied IPA's default
profile: nil group, unspecified QoS and empty flags. The caller borrows QoS
and flags storage in `x1`/`x2`, the block in `x3`, and queue Self in `x20`, with
group in `x0`. A sealed bridge passes Self to the V body in `x4`, preserving
`x20`/`x21` and ignoring `x8`. Native and IPA instructions confirm this ABI
and seven MarketplaceKitWrapper calls using the default argument helpers.

The adapter validates active registered queue state and the argument profile
before reading block storage, copying captures or submitting work. It then
uses the existing dispatcher with all locks released. Stack blocks are
promoted, heap blocks retain one queued ownership, and global blocks preserve
their identity. Execution or shutdown cancellation releases queued captures.
Copy/dispose helpers may reenter queue/runtime locks. Main-thread callbacks
remain deferred, with callbacks posted from a callback running on a later turn.
Groups, non-default QoS/priorities, flags including barriers, WorkItem overloads,
`asyncUnsafe` exports and queue metadata/type queries remain unsupported and
reject explicitly. Cached bridge pointers expire after quiescent retirement.

Ten fresh ASan/UBSan runs and five ARM64 Vinix suites pass across async,
the main queue, QoS, SetAlgebra and the scheduler. Native/V comparisons cover
guarded borrowed values, register preservation, stack promotion, global
identity, heap-block ownership, captured queue ARC and reentrant callbacks.
Vinix additionally checks unlocked helper reentry, next-turn main callbacks,
shutdown cancellation, stop during copy, protected rejection before capture
reads, eight resolvers and unmapped lifetimes. Generated C verifies validation
and existing submission without additional wrapper allocation or ARC.
Thirteen C streams/executables, native/IPA references, the retained descriptor
lifetime trial, corrected sanitizer artifacts and completed probes/audits are
under `build/ios/fortnite/dispatch-async-checks`; full iOS regression remains unpassed.

The next step implements ObjectiveC.ObjCBool nominal metadata in
`swift_objc_bool_metadata.c.v`. The supplied MarketplaceKitWrapper contains one
indirect symbolic nominal type reference to its required
`_$s10ObjectiveC8ObjCBoolVMn` import. V/Mach-O inspection records the reference
and import cell; V/LLVM disassembly records the installed ARM64 Mac accessor
and all eight value witnesses, including every conditional return path.
The retained ARM64 SDK interface gives this frozen struct Swift Bool storage.
This is a native Mac comparison, without claiming an iOS device comparison.

The ObjectiveC overlay now exports exactly ObjCBool's `VMn` descriptor, `VMa`
accessor and `VN` metadata in addition to its existing two scalar conversions.
The metadata has a distinct ObjectiveC nominal identity, kind `0x200`, one field
at offset zero, size/stride 1, POD alignment 1 and 254 extra inhabitants.
Every request returns complete metadata in `x0` with state zero in `x1`.
Copy/take witnesses copy exactly one byte; destroy reads no value storage.
The enum witnesses use byte values 2 through 255 before an external tag is
needed, matching native unaligned little-endian widths and UInt32 count/tag
wrapping. Reflection, initialization extensions, constructors and additional
conformances remain unsupported. The checked resolver seals adjacent code/data
pages as RX/RO before publication, rejects inactive or retired lifetimes, and
unmaps both pages after workers, callbacks and owners drain. Scalar conversions
continue to work before startup and after teardown without metadata allocation.

Ten fresh ASan/UBSan runs and five ARM64 Vinix suites pass across ObjCBool
metadata, scalar conversions, byte metadata, String metadata and symbolic
metadata state lookup. The new native/V fixture covers every payload byte,
five exact-byte copy/take witnesses and a no-read destroy at protected page
boundaries, complete accessor requests, preserved `x20`/`x21`, extra-inhabitant
and external enum tags including UInt32 overflow, library/export rejection,
symbolic descriptor lookup, typed Array storage/POD destruction, eight readers
and two drained/unmapped lifetimes. Thirteen C streams/executables and the
joined probes, audits and native/IPA references are retained under
`build/ios/fortnite/objc-bool-metadata-checks`; full iOS regression remains unpassed.

The next step implements the ObjectiveC overlay's NSObject Equatable/Hashable
conformances in `swift_nsobject_hashable.c.v`, exporting exactly
`_$sSo8NSObjectCSH10ObjectiveCMc` and `_$sSo8NSObjectCSQ10ObjectiveCMc`.
The IPA has one required Hashable descriptor reference and one corresponding
`swift_getWitnessTable` call. V/Mach-O/LLVM inspection retains that caller and
V/native metadata lookup records distinct per-type tables with a shared
inherited NSObject Equatable table. The installed ARM64 Mac witnesses send
`hash` and `isEqual:` to borrowed Objective-C objects. Their hashValue getter
returns the raw hash word; hash(into:) combines that word into Hasher, and
rawHashValue uses the UInt64 seeded hashing entry. Local authenticated import
stubs were followed to verify both hashing targets. This is a native Mac
comparison and SDK reference, without claiming an iOS device comparison.

Vinix emits private generic conformance patterns against its canonical core
Hashable/Equatable protocols, with RX adapters, RO descriptors and separate
zero-filled RW generic caches. Explicit witness lookup creates a sealed table
page per canonical registered ObjC wrapper. Subclass Hashable tables inherit
the base NSObject Equatable table, matching the native lookup. Class ancestry,
wrapper identities, table identities and live owner registries are checked
before reading foreign metadata or object storage. Native Swift class layouts,
metaclasses, unknown/retired metadata, unregistered classes, foreign generic
records, additional overlay methods and runtime-wide conformance discovery
remain unsupported. Published Swift metadata already prevents dynamic class
disposal. Cached borrowed descriptors, adapters and tables expire at stop.

The witnesses call subclass overrides with no registry lock held, preserve
borrowed owner counts and perform no wrapper allocation or ARC. Built-in
Foundation values use the existing message/equality/hash backend. A false
isEqual: result is honored even for identical references, and nil messaging
reads no object storage. Swift's context and error registers are preserved.
At quiescent shutdown, Array/Set specializations retire before these tables,
then the core protocol metadata and ObjC wrappers retire.

Ten fresh ASan/UBSan runs and five ARM64 Vinix suites pass across the new
conformances, static witness lookup, generic hash forwarding, Hasher and
ObjCBool metadata. The native/V fixture checks inherited subclass overrides,
raw hash words including the sign bit, partial Hasher states, signed seeds,
nonreflexive equality, nil messages, guarded reference/state spans, borrowed
owner counts and preserved registers. Vinix additionally checks exact generic
instantiation spans, protected unsupported rejection, unlocked worker reentry,
typed Array ARC, Set metadata, eight concurrent initializers and two drained
lifetimes with every table/code/data/cache page unmapped. Thirteen C streams
and executables, native/IPA references, the original fixture-generation failure,
the corrected fixture, the native import-target assumption and joined startup
probes/audits are retained under `build/ios/fortnite/nsobject-hashable-checks`.
Full iOS regression remains unpassed and published runners remain unchanged.

The IPA startup probe at this stage got past NSObject conformances and exited
with status 1 at MarketplaceKitWrapper's required MainActor.shared getter,
`_$sScM6sharedScMvgZ`, in `/usr/lib/swift/libswift_Concurrency.dylib`.

The next step implements MainActor.shared and its nongeneric final class
metadata in `swift_main_actor.c.v`, exporting `_$sScM6sharedScMvgZ`,
`_$sScMMa` and `_$sScMMn`. V/LLVM inspection of the installed Mac runtime
shows the shared getter forwarding to `swift_initStaticObject`. Its instance
is sixteen bytes with immortal reference bits `0x80000004ffffffff`; native
and unknown-object ARC leave those bits unchanged. Its complete accessor
returns the class metadata and zero state, and its class value witnesses
operate on one eight-byte reference. IPA inspection retains the two actual
shared getter calls and three accessor calls, including the caller moving
the returned metatype into x20 before calling shared. No Fortnite code was
executed by these inspectors.

Vinix publishes one sealed RX/RO arena containing the accessor, independent
class descriptor and immutable singleton. It preserves the borrowed metatype
and error registers, returns the canonical immortal reference without heap
allocation or per-call ARC, and routes native/unknown ARC and object-type
lookup through its registered identity before reading owner storage. The
existing reference witnesses support copy/take/assignment/destruction and
exact bounded values. Typed Array storage additionally accepts this canonical
class metadata; arbitrary application class storage remains unsupported.
Separately allocated instances have a real Swift-context deallocating
destructor for the measured instance layout. At quiescent shutdown, Array
and heap owners drain before the actor arena retires, followed by ARC
adapters and borrowed value witnesses. Descriptors, getter entries and
singleton references expire with the runtime.

Ten fresh ASan/UBSan runs and five ARM64 guest suites pass across MainActor,
actor witness dispatch, heap allocation, unknown-object witnesses and
TaskPriority metadata. The native/V MainActor comparison checks complete
accessor requests, identity, unchanged immortal ARC, object type, exact
protected copy/take/destroy spans, a borrowed protected metatype, guarded
x20/x21 and eight getter/ARC workers. Vinix also checks eight concurrent
first publishers, nominal lookup, actual allocated-instance destruction,
typed-array ownership, explicit executor/conformance rejection and two
drained lifetimes with code and metadata unmapped. Thirteen fresh C streams
and executables, SDK/native/IPA observations, the original observer register
output failure and corrected observer, and joined startup probes/audits are
retained under `build/ios/fortnite/main-actor-checks`. Full iOS regression
remains unpassed and published runners remain unchanged.

The IPA startup probe at this stage got past MainActor.shared and its
metadata accessor and exited with status 1 at the required MainActor Actor
conformance, `_$sScMScAsMc`.

The next step implements that conformance and a main serial executor in
`swift_main_executor.c.v`. V/native inspection measures an unconditional
Actor descriptor and two-word witness table, whose sole getter borrows Self
and returns the main executor. The installed Mac runtime rejects legacy
`1/0` main-executor tagging. Its current main executor is a seventeen-byte
DispatchMainExecutor, with a `threaded` Bool at offset sixteen set to false,
and inherited Executor/SerialExecutor witness tables. V/LLVM inspection
retains the descriptors, all eight SerialExecutor requirement slots, native
main-identity queries and actual IPA witness lookup/dispatcher callers.

Vinix emits its own immutable executor reference, private nominal metadata,
Actor/Executor/SerialExecutor descriptors and complete static witness tables.
The Actor getter returns its canonical nonzero object/table pair without
ARC or dereferencing borrowed metadata/Self; its serial asUnowned witness
borrows the receiver. Enqueue witnesses route through the dispatch main
queue, exclusive-context equality compares references, checkIsolated
requires the main thread and the optional current-context default returns
none. Native and unknown-object ARC/type lookup recognize this private
immortal reference. Code, metadata, references and tables share the existing
MainActor arena and expire only after tasks, callbacks and owned values drain.
The concurrency library also exposes the main-executor identity query,
enqueue primitive and MainActor executor getters.

Supported jobs are actual registered tasks. Main enqueue consumes their
existing execution reference, preserving caller ownership, and publishes the
queue job atomically with the scheduler shutdown gate. Duplicate, started,
foreign or stopped jobs are rejected before consumption. Main jobs execute
on the main thread with current-task TLS and the existing completion/closure
ownership. Their queued callback counts remain live until the call returns,
even if completion frees the task/context. Runtime join releases its task
mutex before draining queued Swift main work, preventing shutdown from
waiting forever for a main-thread callback. The drain is requested only when
Swift main jobs exist. A private execution marker preserves the measured
public job/context layout; inherited priority is masked separately from it.
Same-main and same-generic task switches are genuine tail continuations.
Cross-executor parking/resumption, arbitrary non-task Job layouts, additional
executor profiles and structured tasks remain explicitly unsupported.

Twelve fresh ASan/UBSan runs and six ARM64 guest suites pass across the new
conformance/main executor, MainActor metadata, task creation, task switching,
actor dispatch and TaskPriority. The native/V comparison exercises real
manual and deferred main jobs, the direct enqueue primitive and both
inherited enqueue witnesses, plus an actual same-main tail continuation.
It checks static witness lookup, borrowed getters, preserved x20/x21, exact
executor layout, asUnowned, nil isolation, protected unused metadata, eight
concurrent readers and repeated drained/unmapped lifetimes. Vinix also
rejects invalid/unregistered jobs, duplicate enqueue, wrong queue execution
and cross-executor suspension before changing ownership. Fifteen fresh C
streams and executables, SDK/native/IPA observations, joined VM probes/audits
and three original fixture trials are retained under
`build/ios/fortnite/main-actor-witness-checks`. The trials record a native
header name collision before execution, the unmeasured private-byte
assumption, and a native shared-refcount sample that was invalid across
concurrent identity queries. The corrected fixture retains a quiescent ARC
comparison and all V immutable-header checks. Full iOS regression remains
unpassed and published runners remain unchanged.

Swift `os.Logger` now provides all three operations imported by
MarketplaceKitWrapper: complete nongeneric metadata, initialization with
subsystem/category Strings, and the `logObject` getter. Native LLVM inspection
on this Mac and actual IPA caller instructions establish an eight-byte value,
borrowed indirect Self in x20, an owned ObjC getter result, and initialization
through x8 that consumes both String arguments. The V implementation uses the
existing canonical logging handles, explicit reference copy/take/assignment/
destroy witnesses and optional payload encoding. Code and metadata occupy
sealed pages, retired after array/heap owners drain. Label handling supports
inline, immortal and owned native-tail UTF-8, including Unicode and embedded
NUL behavior, with the existing 255-byte logging limit. Shared/foreign String
storage, native compact-layout strings/reflection and additional Logger or
OSLogMessage exports remain outside this profile.

Twelve ASan/UBSan runs and six ARM64 guest suites pass across Logger, os_log,
unknown-object ownership, String, metadata and array storage. The differential
fixture checks retained ObjC results, consumed distinct/aliased owned Strings,
protected exact-size values/results, x20/x21 preservation, optional payloads
through UINT32_MAX, eight concurrent workers and two drained/unmapped lifetimes.
Fifteen final C streams and executables, SDK/native/IPA inspection, joined VM
probes/audits and five original fixture failures are retained under
`build/ios/fortnite/logger-checks`. The failures record a default-namespace
ObjC release lookup, native compact-layout self-assignment of its sole owner,
an unaligned fixture enum read, and two Linux-style mincore assumptions on
Darwin. The corrected fixture resolves libobjc directly, uses distinct
assignment storage, copies unaligned payloads with memcpy and inspects Mach
VM regions on macOS. Temporary disk exhaustion and an interrupted CLI build
are recorded separately; completed host archives were verified before resuming
remaining checks, and unfinished guest programs were rebuilt. Full iOS
regression remains unpassed and published runners remain unchanged.

The Logger implementation's IPA startup probe got past the three Logger
imports and exited with status 1 at MarketplaceKitWrapper's required Set bridge,
`_$sSh10FoundationE36_unconditionallyBridgeFromObjectiveCyShyxGSo5NSSetCSgFZ`.

The Foundation Set bridge now converts a borrowed registered NSSet or
NSMutableSet into an owned Swift Set of registered NSObject references and
subclasses, using canonical inherited Hashable witnesses. Native LLVM
inspection and differential calls establish ordinary x0/x1/x2 arguments,
an owned result in x0, unused Self x20, and nil returning the canonical empty
Set without reading generic arguments. The actual IPA's class-reference fixup
identifies `Set<UIScene>` and NSObject Hashable; its caller releases the source
after bridging and then invokes Sequence.compactMap. The V implementation
retains a member snapshot before hash/equality callbacks, materializes the
existing native bitmap/bucket storage and publishes element ownership for
the existing Set destructor and Sequence/Iterator implementation. It supports
up to 4,096 object members. Foreign/dead objects, incorrect element metadata,
noncanonical witnesses, raw CF pointers and value/scalar element conversion
fail explicitly. Concurrent mutation of the source collection is unsupported.

Twelve ASan/UBSan runs and six ARM64 guest suites pass across the new bridge,
Objective-C NSSet, Swift Set, NSObject Hashable, String unbridging and
unknown-reference ownership. The bridge fixture checks protected unused
generic arguments, preserved x20/x21, borrowed source/owned result ARC,
immutable/mutable source independence, collision probing, callback mutation,
unlocked cross-thread reentry, eight concurrent readers and two drained
runtime lifetimes. Fifteen fresh C streams and executables, SDK/native/IPA
observations and joined startup/audit VMs are retained under
`build/ios/fortnite/set-bridge-checks`. The original fixture failure records
using the dispatcher IMP return as a message result; the corrected fixture
calls the existing builtin message entry directly. Two SDK snapshot helper
failures and a class-reference address calculation failure are retained
separately. Full iOS regression remains unpassed and published runners remain
unchanged.

The Set bridge's IPA startup probe passed that import and exited with
status 1 at MarketplaceKitWrapper's required `_OBJC_CLASS_$_OS_dispatch_queue`
from `/usr/lib/libSystem.B.dylib`.

Dispatch queues now expose the required libSystem class identity, its
OS_dispatch_object/OS_object/NSObject ancestors, and the observed native
main/serial/global subclass hierarchy. Native runtime queries and Swift
metadata calls establish eight-byte public isa layouts and canonical ObjC
wrapper metadata. Vinix gives its existing scheduler-owned queues an isa;
their reference count, jobs, labels and destruction remain in the scheduler.
Class/self/superclass, ancestry/equality/hash queries, retain/release,
retainCount and autorelease messages use that storage. Existing Swift wrapper
value witnesses and DispatchQueue.main operate on the same owners. Class
lookup uses static names, and class imports resolve through libSystem or
libobjc. Generic allocation, caller-storage construction and isa changes
reject the dispatch family and subclasses before changing storage. Queue
copy/init and messages after Objective-C teardown also fail explicitly.
Descriptions, weak references, queue borrowing through Swift dynamic casts
or NSObject Hashable collections, serial-executor conformances and other
dispatch object families remain outside this profile.

Twelve final ASan/UBSan runs and six ARM64 guest suites pass across queue
classes, Dispatch main/async, unknown-object ownership, foreign metadata and
ObjC casts. Native differential checks cover physical/metaclass ancestry,
canonical wrappers, real main/serial/global queue identities, class-typed
getter ABI with preserved x20/x21 and protected x8, value-witness ARC and
eight concurrent readers. Vinix also checks autorelease ownership, guarded
foreign lookup, both initialization orders and two drained lifetimes. Fifteen
final generated C streams/executables and joined probe/audit evidence are
retained under `build/ios/fortnite/dispatch-queue-class-checks`. The first smoke
failure caught Foundation's generic class resolver accepting the new libSystem
class; native checks passed before that V assertion. The corrected resolver
restricts that import. A native discovery failure records assuming Darwin's
inline main-queue accessor was a dynamic function; the corrected helper reads
the actual `_dispatch_main_q` export. An LLVM inspector compile failure is
retained separately. The first complete passing cohort is also preserved;
final builds include the allocation-free symbol matcher and the additional
initialization-order checks. Full iOS regression remains unpassed and
published runners remain unchanged.

The queue bridge resolves two more strong imports, and both bundled
frameworks have zero unresolved strong imports in the C++/GLES/Text audit.
Before the CocoaError getter was implemented, the actual IPA startup probe
passed their binding and stopped in the main executable at Foundation's
required `_$s10Foundation10CocoaErrorV19fileWriteFileExistsAC4CodeVvgZ`.

The Foundation bridge now exports that `fileWriteFileExists` getter through
both the framework and Swift overlay install names. The installed native
implementation writes the eight-byte `CocoaError.Code` raw value `516`
through Swift's indirect result register x8. It reads no Self, metadata or
witness argument. V emits this entry in the existing Foundation arena, which
is published as RX code and RO data and retired by the existing drained
shutdown. The getter adds no per-call allocation, ARC work or callback.
Other CocoaError getters and constructors remain unsupported. Code metadata
and the conformance lookup described below are now available.

Native differential checks verify the eight-byte layout, native `rawValue`
consumption of V-produced values, protected unused arguments and Self,
preserved x20/x21, result canaries, both guarded page boundaries, concurrent
publication/use and two unmapped runtime teardowns. V/Mach-O/LLVM inspection
of the pinned IPA finds the required getter cell at `10dc981e8`, its stub at
`10c63a878` and a branch island at `107c28d54`. The actual caller at
`100073af4` sets x8 to its result buffer before the call. The first inspector
attempt missed the branch island; its source, executable and failed output
are retained separately.

Twelve ASan/UBSan runs and six ARM64 guest suites pass across the new getter,
Foundation logging, NSString unbridging, Error descriptions, Swift metadata
and unknown-object ownership. Fifteen final generated C streams/executables
and the four joined, retired VM runs are retained under
`build/ios/fortnite/cocoa-error-code-checks`, together with native SDK inputs,
instruction/caller evidence and staging/inspector failures. Full iOS
regression remains unpassed and published runners remain unchanged.

The getter's IPA launch passed that binding and exited with status 1 at
`_$s10Foundation10CocoaErrorV4CodeVAA01_cD8ProtocolAAMc`, the required
Code conformance to Foundation's `_ErrorCodeProtocol`.

The Foundation bridge now also provides complete nongeneric `CocoaError.Code`
metadata and its canonical concrete `_ErrorCodeProtocol` witness lookup.
Native Foundation/Swift/LLVM inspection on this Mac establishes an eight-byte
POD value with integer equality, a four-word witness table and associated
`CocoaError` metadata containing an owned NSError reference. V reuses the
existing integer and ObjC value witnesses and seals code/data in two pages.
The associated metadata supports reference copy/take/assignment/destruction;
runtime shutdown drains owners before unmapping these pages. Descriptor
identity checks reject retired conformance lookup before reading unmapped data.

The wider associated `_BridgedStoredNSError` conformance remains unsupported:
its CustomNSError, Objective-C bridging, Hashable, RawRepresentable and
FixedWidthInteger witnesses require further implementation. Swift's tagged
`FF 07` associated-conformance record contains a relative accessor function.
V directs it to a checked rejecting entry, including when native Swift performs
the lookup, instead of returning an incomplete witness table. Other CocoaError
constructors, raw-value accessors, nominal reflection and stored-error exports
remain unavailable. The actual IPA metadata import cell is `10dc981f8`; its
callers at `100073a48` and `100073fcc` request complete metadata. The conformance
cell at `10dc981f0` is loaded at `100073fd4` for `swift_getWitnessTable`.

Twelve ASan/UBSan runs and six Vinix ARM64 guest suites pass across the new
metadata/lookup, file-exists getter, witness lookup, metadata, unknown-object
ownership and NSError value operations. The new fixture compares native POD8
copy/take/assignment, optional payloads and equality, consumes V metadata with
native Swift lookup and associated-type lookup, verifies NSError copy/destruction
ownership, concurrent publication and two drained lifetimes, and checks that a
native associated-conformance request reaches the explicit rejection. Fifteen
final generated C streams/executables and four joined, retired QEMU phases are
retained under `build/ios/fortnite/cocoa-error-protocol-checks`. The original
host failure preserves the mistaken descriptor target and resulting data-page
fault. A cancelled guest build is retained separately; all final programs were
rebuilt after correcting the accessor. Full iOS regression remains unpassed and
published runners remain unchanged.

The Code metadata implementation's IPA launch resolved both new imports and
exited with status 1 at Foundation's required
`_$s10Foundation11JSONDecoderC6decode_4fromxxm_AA4DataVtKSeRzlFTj`.
Installed native Foundation instructions identify its class dispatch slot at
metadata offset 320, with Self in x20. Fortnite has not entered application code
and remains unplayable.

The Foundation bridge now exports that generic JSONDecoder virtual dispatch
entry through the framework and Swift overlay install names. It reads the
borrowed Self's metadata pointer and method slot at offset 320, then tail-branches
to the actual class implementation. Integer/vector arguments, the indirect
result pointer in x8, scalar results and Swift's x21 error channel pass through
unchanged by the forwarding entry. It performs no allocation, ARC operation or
callback under a runtime lock. The entry shares the existing sealed Foundation
arena and its drained shutdown lifetime. The caller owns valid readable Self
and vtable spans, as required by the Swift dispatch ABI.

This entry forwards an override. Its original implementation left JSONDecoder
construction, nominal metadata, configuration and the default decoding backend
unresolved.
The pinned IPA's dispatch import cell is `10dc98200`, its stub is `10c63a890`
and its forwarding branch island is `107c28ae0`. The actual caller at
`1000710ac` passes Self in x20, a two-word Data value in x1/x2, result storage
in x8 and the error channel in x21, then tests the returned error before reading
the result. No application code is executed by this inspection.

Eight ASan/UBSan runs and four Vinix ARM64 guest suites pass across the new
dispatch entry, CocoaError getter, Foundation logging and CocoaError metadata.
The differential dispatch fixture signs its native isa and method pointers,
uses actual method targets, and compares integer/vector arguments, indirect
and scalar results, and success/error returns through x21. Guarded header and
slot boundaries verify that dispatch reads no ARC header or unused metadata;
eight concurrent callers and two unmapped teardowns verify publication/lifetime.
The guest harness's original directory-setting failure is retained separately:
it failed before any VM, its new temporary C files were preserved and removed,
and every recorded artifact/source snapshot in the prior cohort was verified
unchanged. A later log-write failure while disk space was low is also retained;
all final guest programs were rebuilt to obtain fresh joined exit records.
Eleven final generated C streams/programs and the four joined, retired VM phases
are retained under `build/ios/fortnite/json-decoder-dispatch-checks`.
Full iOS regression remains unpassed and published runners remain unchanged.

The dispatch implementation's actual IPA startup probe resolves that entry and
exits with status 1 at Foundation's required JSONDecoder initializing constructor,
`_$s10Foundation11JSONDecoderCACycfc`. Fortnite has not entered application code
and remains unplayable.

The Foundation bridge now resolves the base JSONDecoder initializing constructor,
metadata accessor and nominal descriptor through the framework and Swift overlay
install names. Fortnite's actual call at `100072344` obtains base metadata,
allocates with its instance size/alignment, passes the object in x20 and stores
returned Self. The V implementation supplies a canonical native-ARC class profile
with 160-byte instances, the measured default-option extents, an immutable private
JSON5 key and empty userInfo constant, and an independent owned lock context.
Enum/bool padding remains untouched. Construction requires registered, unique,
uninitialized base storage; unknown, short, duplicate and retired owners reject
before mutation. Swift native/unknown ARC and reference value witnesses retain
the object; destruction releases its lock and deallocates Self exactly once.
After workers and heap owners drain, the sealed code/data pages retire before
their borrowed ARC/value-witness support.

The class has a private reflection profile. Subclassing, Objective-C exposure,
option methods, allocating-constructor exports and the default JSON decoding
backend remain unsupported. Unimplemented virtual entries fail explicitly;
no decoded values or successful game startup are synthesized.

Eight ASan/UBSan runs and four Vinix ARM64 guest suites pass for construction,
virtual dispatch, heap lifetime and UnknownObject witnesses. The constructor
fixture compares installed Foundation defaults and untouched padding, returned
Self and x20/x21, lock ownership independent of Self, reference copies, eight
concurrent constructors, concurrent metadata publication, RX/RO mappings and
two unmapped retirements. Ownership registries drain after each worker group.
A sanitizer failure in the fixture's unlocked map inspection was corrected;
its executed C, executable, debug symbols, source and diagnostic are retained
separately. Eleven final C streams/programs and four joined, retired VM phases
are retained under `build/ios/fortnite/json-decoder-initializer-checks`.
Full iOS regression remains unpassed and published runners remain unchanged.

The actual IPA startup probe now resolves all three construction imports and
exits with status 1 at Foundation's required JSONEncoder formatted-date enum case
discriminator,
`_$s10Foundation11JSONEncoderC20DateEncodingStrategyO9formattedyAESo15NSDateFormatterCcAEmFWC`.
Fortnite has not entered application code and remains unplayable.

The Foundation bridge now exports this formatted-date enum discriminator as
four-byte read-only data with value zero, through both Foundation install names.
Fortnite's GOT cell at `10dc98220` supplies the pointer to `ldr w1` at
`10006e624`; the caller passes the loaded tag to DateEncodingStrategy's
destructive enum-tag injection witness at offset 104. Native Foundation verifies
that this tag selects the owned DateFormatter payload and survives a retained
enum copy and destruction. The export uses the existing sealed Foundation data
page and its drained lifetime. Reading the constant introduces no code dispatch,
allocation or ARC operation.

Eight ASan/UBSan runs and four Vinix ARM64 guest suites pass for the enum data,
JSONDecoder construction, Foundation logging and CocoaError getter. The fixture
uses real ARM64 four-byte loads/stores, guarded input/output edges and canaries,
native payload witnesses, concurrent alias publication/readers, read-only mapping
checks and two unmapped retirements. The rejected consumer fixture's instruction
encoding, generated C, executable, debug symbols and diagnostic are retained
separately; all final fixtures were regenerated after correcting its observation
store. Eleven final C streams/programs and four joined, retired VM phases are
retained under `build/ios/fortnite/json-encoder-date-case-checks`.
At that point, strategy/encoder metadata, date formatting and JSON encoding
remained unsupported.
Full iOS regression remains unpassed and published runners remain unchanged.

The preceding IPA startup probe resolved the enum-case data export and exited with
status 1 at Foundation's required DateEncodingStrategy metadata accessor,
`_$s10Foundation11JSONEncoderC20DateEncodingStrategyOMa`.
Fortnite has not entered application code and remains unplayable.

Vinix now supplies DateEncodingStrategy's complete metadata accessor and a
private nongeneric enum descriptor through both Foundation install names. Native
measurements establish a 17-byte value, stride 24, alignment eight, two payload
cases, four empty cases and 253 extra inhabitants. Its ordinary and enum value
witnesses preserve exact payload/tag bytes and manage formatter-object or Swift
closure-context ownership. Copy/take assignment, destructive tag injection,
projection and optional-tag storage match the measured native behavior for
distinct source/destination storage. The private descriptor omits reflection and
Apple's layout-string extension. Metadata and code occupy separately sealed
read-only/executable pages, retired after Array and heap users drain.

Eight ASan/UBSan runs and four Vinix ARM64 guest suites pass for enum metadata,
enum-case data, JSONDecoder construction and CocoaError values. The enum fixture
checks every case transition, reference counts, unchanged padding, guarded tag
edges, concurrent copies from read-only storage, metadata request ABI, non-POD
Array destruction and two unmapped retirements. A rejected native comparison
passed aliased storage to assignment and released the sole formatter owner before
copying; its source, executed C, executable, debug symbols and diagnostic are
retained separately. The corrected native comparisons use distinct storage;
Vinix's defensive self-copy behavior is tested separately. Eleven final C
streams/programs and four joined, retired VM phases are retained under
`build/ios/fortnite/json-date-strategy-checks`. Encoder construction/options,
formatter methods, closure invocation and JSON encoding remain unsupported.
Full iOS regression remains unpassed and published runners remain unchanged.

That IPA startup probe resolved DateEncodingStrategy metadata and exited
with status 1 at the required import
`_$s10Foundation11JSONEncoderC20dateEncodingStrategyAC04DatedE0OvsTj`.
Fortnite has not entered application code and remains unplayable.

The JSONEncoder date-strategy setter dispatch thunk is now exported through both
Foundation install names. Native Foundation selects class metadata slot 128,
passes the consuming indirect enum in x0 and borrowed Self in x20, and uses x1
as its selected-method register. Vinix forwards these registers with a tail
branch to the actual override, preserving x8, x21 and vector-register behavior.
The thunk performs no ARC, enum access or option mutation and reuses the existing
sealed Foundation code page and its drained lifetime.

Eight ASan/UBSan runs and four Vinix ARM64 guest suites pass for setter dispatch,
DateEncodingStrategy metadata, JSONDecoder construction and CocoaError values.
The setter fixture compares native signed vtable/header pointers with the
unsigned Vinix metadata, guards exact header/slot reads and surrounding metadata,
checks scalar/vector/register observations, concurrent calls/publication, mapping
permissions and two unmapped retirements. A selected override consumes real
formatter-backed and empty enum values; the guard reference verifies that the
payload is released exactly once. Native uses NSDateFormatter ownership and
Vinix uses registered NSObject ownership. No date-formatting method or actual
encoder backend is invoked. Eleven final C streams/programs and four joined,
retired VM phases are retained under
`build/ios/fortnite/json-encoder-date-dispatch-checks`.
Default encoder construction, option storage and JSON encoding remain unsupported.
Full iOS regression remains unpassed and published runners remain unchanged.

That IPA startup probe resolved the setter dispatch import and exited with
status 1 at the required import
`_$s10Foundation11JSONEncoderC6encodeyAA4DataVxKSERzlFTj`.
Fortnite has not entered application code and remains unplayable.

The JSONEncoder generic encode dispatch thunk is now exported through both
Foundation install names. Native Foundation selects class metadata slot 272,
uses x8 for the selected method and calls it with a saved frame pointer/link
register frame. Vinix mirrors that call frame, forwards scalar/vector arguments,
returns the two Data words in registers and propagates the x21 error channel.
The thunk performs no ARC, input access or encoding and reuses the sealed
Foundation code page and its drained lifetime.

Eight ASan/UBSan runs and four Vinix ARM64 guest suites pass for generic encode
dispatch, date-strategy setter dispatch, enum metadata and CocoaError values.
The encode fixture compares native signed vtable/header pointers with unsigned
Vinix metadata, guards exact header/slot reads and surrounding metadata, checks
successful and failing override results, live frame observations, concurrent
calls/publication, mapping permissions and two unmapped retirements. It verifies
that x8 contains the method pointer and that no indirect result storage is
written. These overrides return synthetic Data words; no actual encoding runs.
Eleven final C streams/programs and four joined, retired VM phases are retained
under `build/ios/fortnite/json-encoder-dispatch-checks`.
Default encoder construction, option storage and JSON encoding remain unsupported.
Full iOS regression remains unpassed and published runners remain unchanged.

That IPA startup probe resolved the generic encode dispatch import and
exited with status 1 at the required import
`_$s10Foundation11JSONEncoderCACycfc`.
Fortnite has not entered application code and remains unplayable.

The JSONEncoder base initializing constructor, metadata accessor and nominal
descriptor are now exported through both Foundation install names. Native
Foundation measurements establish a 144-byte instance, alignment eight, two
stored fields and a class vtable starting at word 12. Vinix constructs the exact
default options while preserving enum padding, installs a canonical immortal
empty userInfo Dictionary and owns a separate 20-byte lock context. Initializing
Self is borrowed in x20, returned in x0 and the x21 register is preserved.
Private metadata uses native ARC and separately sealed code/data pages; the
class is not registered with Objective-C. Option mutation, subclasses, ObjC
exposure and actual JSON encoding remain explicitly unsupported.

Twelve ASan/UBSan runs and six Vinix ARM64 guest suites pass for encoder and
decoder construction, generic encode/setter dispatch, date-strategy metadata
and its formatted-case export. The initializer fixture compares native default
writes and padding, accessor requests, ARC copy/destroy witnesses and independent
lock retention. Eight concurrent workers repeatedly construct and release base
instances; registries drain completely. Invalid, short, duplicate, nonunique and
retired owners are rejected, concurrent publication is canonical, and both arena
lifetimes end in verified unmapping. Fifteen final C streams/programs and four
joined, retired VM phases are retained under
`build/ios/fortnite/json-encoder-initializer-checks`.
Full iOS regression remains unpassed and published runners remain unchanged.

That IPA startup probe resolved the encoder constructor and metadata
imports, then exited with status 1 at the required import
`_$s10Foundation14LocalizedErrorPAAE10helpAnchorSSSgvg`.
Fortnite has not entered application code and remains unplayable.

The initial guest link stopped because the former ARM64 sysroot was absent.
The final builds use pinned musl headers/libraries and GCC startup objects
already present in this checkout. The failed generated C and diagnostics are
retained separately; no failed guest executable ran.

The four LocalizedError protocol-extension default getters now resolve through
both Foundation install names: errorDescription, failureReason,
recoverySuggestion and helpAnchor. Installed Foundation returns a nil optional
String as two zero words in x0/x1, without reading Self, metadata, witnesses or
x8. Vinix mirrors these defaults with distinct entries in the existing sealed
Foundation code page. An empty String has a different representation. These
exports do not provide protocol metadata or custom witness dispatch.

Eight ASan/UBSan runs and four Vinix ARM64 guest suites pass for the defaults,
Error.localizedDescription, CocoaError protocol layout and JSONEncoder
construction. The new fixture executes all native and Vinix defaults with
null, invalid and protected inputs, readonly Self at a guard edge, register and
vector canaries, concurrent calls/publication and two unmapped retirements.
It verifies per-property alias identity and distinct addresses across properties.
Eleven final C streams/programs and four joined, retired VM phases are retained
under `build/ios/fortnite/localized-error-checks`. The private build uses
the previously pinned local musl/GCC SDK and C++/GLES dependencies.
Full iOS regression remains unpassed and published runners remain unchanged.

That IPA startup probe resolved the LocalizedError default getter
imports, then exited with status 1 at the required import
`_$s10Foundation18_ErrorCodeProtocolPAAE2teoiySbx_s0B0_ptFZ`.
Fortnite has not entered application code and remains unplayable.

The CocoaError.Code specialization of Foundation's `_ErrorCodeProtocol.~=`
now matches registered concrete CFError and NSError values by the exact
`NSCocoaErrorDomain` string and full-width integer code. Native Foundation
receives the borrowed indirect Code, Error owner, metadata and witness table
in x0/x1/x2/x3. Vinix validates the canonical Code metadata/conformance and
live registered error before reading fields. An unrelated domain returns false
without reading the match bytes. No bridge object or owned reference is created.
Swift error boxes, other code conformances and NSError subclass accessors remain
explicitly unsupported; the wider stored-error witness table stays unavailable.

Eight ASan/UBSan runs and four Vinix ARM64 suites pass for matching,
LocalizedError defaults, Error.localizedDescription and Cocoa protocol layout.
The matching fixture compares native and Vinix results across six domains,
CFError/NSError storage, matching/nonmatching codes and signed 64-bit extrema.
It checks protected wrong-domain inputs, readonly Code at a guard edge, borrowed
ARC, x20/x21, concurrent calls/publication, invalid owners/fields/metadata and
two drained runtime lifetimes. Eleven final C streams/programs and four joined,
retired VM phases are retained under `build/ios/fortnite/cocoa-error-match-checks`.
The private build reuses the pinned local musl/GCC SDK and C++/GLES dependencies.
Full iOS regression remains unpassed and published runners remain unchanged.

That IPA startup probe resolved the error-code matching import, then
exited with status 1 at the required import `_$s10Foundation22_convertErrorToNSErrorySo0E0Cs0C0_pF`.
Fortnite has not entered application code and remains unplayable.

Foundation's Error/NSError conversions now resolve through both Foundation
install names for registered CFError, NSError and Objective-C NSError subclasses.
The installed `_convertErrorToNSError` retains its borrowed Error in x0 before
tail-calling the consuming Core bridge. Vinix validates the live object and
retains it once under the recursive runtime lock, returning the same object as
an owned NSError.
The caller's original reference survives disposal of that result. Domain, code
and userInfo ownership stay intact. Native Swift error boxes remain explicitly
unsupported; the existing Core bridge keeps its consuming ownership rule.

The inverse `_convertNSErrorToError` also retains a borrowed nonnil input and
returns the same object as an owned Error. Native nil input returns a cached
Swift `_GenericObjCError` box; its NSError bridge has domain
`Foundation._GenericObjCError`, code zero and empty userInfo. Vinix explicitly
rejects that unimplemented boxed nil-error fallback.

Eight ASan/UBSan runs and four Vinix ARM64 suites pass for both Foundation
conversions, the Core bridge, Error extraction/value witnesses,
Error.localizedDescription and Cocoa matching.
The extended bridge fixture compares thirty field/ownership cases for each of
three entry points with native libraries, including signed 64-bit extrema,
NSError subclasses, x20/x21,
invalid and protected owners, concurrent calls/alias publication, weak zeroing
and reentrant destruction across two drained lifetimes. Eleven final generated
C streams/programs and four joined, retired VM phases are retained under
`build/ios/fortnite/error-nserror-checks`. The private build reuses the pinned
local musl/GCC SDK and C++/GLES dependencies. Full iOS regression remains
unpassed and published runners remain unchanged.

That IPA startup probe resolves both Foundation error conversion imports,
then exits with status 1 at the required import `_$s10Foundation3URLV19_bridgeToObjectiveCSo5NSURLCyF`.
Fortnite has not entered application code and remains unplayable.

Foundation's `URL._bridgeToObjectiveC()` now resolves through both Foundation
install names. Native inspection measures an indirect two-word URL containing
an implementation object and witness table. The bridge calls `swift_getObjectType`
for its formal metadata, then dispatches through witness slot 432 with metadata
in x0, table in x1, slot address in x8 and borrowed implementation in x20.
It performs no implementation ARC and returns the witness's owned NSURL.
URL constructors, metadata and concrete URL implementations remain unsupported;
the caller supplies readable Self/table storage and a working bridge witness.

Eight ASan/UBSan runs and four Vinix ARM64 suites pass for URL bridging, Swift
heap ownership, JSON encoder dispatch and Error/NSError bridging. The URL fixture
compares the native and Vinix contracts with signed native witnesses, real NSURL
results, exact implementation/result ownership, protected Self/slot boundaries,
preserved context, concurrent calls/publication and two drained, unmapped
lifetimes. Eleven final C streams/programs and four joined, retired VM phases
are retained under `build/ios/fortnite/url-bridge-checks`, including native stub
resolution and the IPA's actual bridge consumers. The private build uses the
pinned local SDK; full iOS regression remains unpassed and published runners
remain unchanged.

That IPA startup probe resolves the URL-to-NSURL bridge, then exits with
status 1 at `_$s10Foundation3URLV22appendingPathComponent_11isDirectoryACSS_SbtF`.
Fortnite has not entered application code and remains unplayable.

`URL.appendingPathComponent(_:isDirectory:)` and `deletingLastPathComponent()`
now resolve through both Foundation install names. They borrow URL's
implementation and dispatch through witness slots 336 and 368 with its formal
type metadata. Appending forwards the borrowed String words and Bool unchanged.
Both return an owned two-word URL through x8: a nonnil witness result passes
through unchanged; a nil result retains the original implementation with
`swift_unknownObjectRetain` and returns its original table. The original URL
survives releasing either result. Concrete URL construction and path backends
remain unsupported; these operations require the caller's working witnesses.

Eight ASan/UBSan runs and four Vinix ARM64 suites pass for path operations,
URL bridging, heap ownership and formal object type lookup. The path fixture
compares native and Vinix ownership for Swift and Objective-C implementations,
replacement and identity results, empty/nonempty String arguments, both Bool
values, signed native witnesses, protected Self/slot/result boundaries,
preserved context, concurrent calls/publication and two unmapped lifetimes.
Eleven final C streams/programs and four joined, retired VM phases are retained
under `build/ios/fortnite/url-path-checks`, with both actual IPA consumers and
native helper targets. Full iOS regression remains unpassed and published runners
remain unchanged.

That IPA startup probe resolves both URL path operations, then exits with
status 1 at the required metadata accessor `_$s10Foundation3URLVMa`.
Fortnite has not entered application code and remains unplayable.

Foundation's URL metadata accessor and nominal descriptor now resolve through
both Foundation install names. The accessor returns canonical, complete
metadata for the native sixteen-byte inline value. Its eight value witnesses
copy, move and destroy the implementation owner with unknown-object ARC while
preserving the inert table word. Native copy assignment publishes the owner
before releasing the old value, retains the replacement afterwards, then
publishes the table; take assignment releases before publishing either word.
Single-payload enum witnesses match the native extra-inhabitant encoding,
including its seventeenth byte for more than 2,147,483,647 empty cases.
The private nominal descriptor supports indirect symbolic type lookup through
its accessor. Constructors, concrete URL backends and field reflection remain
unsupported; the descriptor does not advertise Apple's compact layout string.

Eight ASan/UBSan runs and four Vinix ARM64 suites pass for URL metadata, path
operations, URL bridging and unknown-object ownership. The metadata fixture
compares all eight witnesses with the installed native libraries, checks exact
Swift/Objective-C ownership and destructor reentry ordering, protected and
unaligned enum storage, preserved context, concurrent publication and values,
and two drained lifetimes with unmapped metadata/code pages. Eleven final C
streams/programs and four joined, retired VM phases are retained under
`build/ios/fortnite/url-metadata-checks`, including the IPA's accessor consumers
and indirect nominal type references. The private build reuses the pinned local
SDK; full iOS regression remains unpassed and published runners remain unchanged.

That IPA startup probe resolves both URL metadata imports, then exits
with status 1 at `_$s10Foundation4DataV11referencingACSo6NSDataCh_tcfC`
(`Data.init(referencing:)`). Fortnite has not entered application code and
remains unplayable.

`Data.init(referencing:)` now resolves through both Foundation install names.
It borrows built-in NSData or NSMutableData and snapshots their bytes, matching
the installed native constructor: empty data has a fixed tag, up to fourteen
bytes are stored inline, and larger values hold a compact range and owned Swift
storage. The source's retain count stays unchanged and releasing or mutating it
does not change the result. The storage frees its independent byte buffer and
deallocates through the Swift heap lifetime. This profile supports the existing
NSData limit of 16 MiB; custom NSData subclasses, large-range values, general
Data metadata and public Data value witnesses remain unsupported.

Eight ASan/UBSan runs and four Vinix ARM64 suites pass for Data snapshots,
URL metadata, unknown-object ownership and Swift heap allocation. The Data
fixture compares empty/inline/slice layouts and storage fields with native
libraries, including the 14/15-byte boundary and 16 MiB limit, mutable inputs,
no-copy NSData, independent bytes after source release, exact storage ownership,
protected byte/result spans, register context, concurrent calls/publication and
two drained lifetimes with unmapped storage descriptor/destructor pages.
Eleven final C streams/programs and four joined, retired VM phases are retained
under `build/ios/fortnite/data-reference-checks`, alongside actual IPA consumers
and native constructor inspection. Full iOS regression remains unpassed and
published runners remain unchanged.

The Data referencing checkpoint resolves that constructor, then
exits with status 1 at `_$s10Foundation4DataV19_bridgeToObjectiveCSo6NSDataCyF`
(`Data._bridgeToObjectiveC()`). Fortnite has not entered application code and
remains unplayable.

`Data._bridgeToObjectiveC()` now resolves through both Foundation install names.
It borrows the two Data words in registers and returns an owned NSData. Empty
values and empty slices share an immortal `_NSZeroData`; 1–14-byte values copy
into `_NSInlineData`; registered snapshot storage produces a
`Foundation.__NSSwiftData` wrapper that retains its Swift owner and shares the
selected byte range. Copies retain the immutable result, while mutable copies
and re-referencing constructors make independent byte snapshots. The wrapper
releases storage before association callbacks, without holding the registry
lock. Weak loads return nil during teardown; native raw weak slots clear after
association cleanup. The private snapshot profile retains the 16 MiB bound;
external storage, large-range Data, metadata and general value witnesses remain
unsupported.

Eight ASan/UBSan runs and four Vinix ARM64 suites pass for Data bridging, Data
snapshots, Objective-C supplied storage and Swift heap ownership. The bridge
fixture checks native class sizes, register preservation and protected x8,
both destruction orders, slice sharing, independent mutable copies and
re-referencing snapshots, weak behavior, reentrant association cleanup,
concurrent first publication, invalid storage rejection and two drained runtime
lifetimes with unmapped descriptor pages. Eleven final C streams/programs and
four joined, retired VM phases are retained under
`build/ios/fortnite/data-bridge-checks`, with actual IPA consumers and native
bridge/next-import inspection. Earlier test assumptions about empty mutable
bytes and raw weak slots, and the missing native storage fixture, are retained
as failed trials. Full iOS regression remains unpassed; published runners are
unchanged.

The Data bridge checkpoint resolves that bridge and exits with status 1 at
`_$s10Foundation4DataV19base64EncodedString7optionsSSSo27NSDataBase64EncodingOptionsV_tF`
(`Data.base64EncodedString(options:)`). Fortnite still has not entered
application code and remains unplayable.

`Data.base64EncodedString(options:)` now resolves through both Foundation
install names. The V implementation borrows Data in x1/x2, takes options in
x0 and returns an owned ASCII Swift String in x0/x1. It handles empty, inline
and registered snapshot slices through the existing 16 MiB Data limit, with
padding, 64/76-column wrapping and CR/LF selection. Both line-length flags
select 64 columns; separators appear only between lines. Small results are
inline, while larger results own independent native-tail String storage.
External or large-range Data and undeclared option bits remain unsupported.
The actual IPA consumers pass zero options. An exploratory native run with
all option bits set failed while extracting the result's UTF-8; that trial is
preserved separately from the declared-option measurements.

Eight ASan/UBSan runs and four Vinix ARM64 suites pass for Base64, Data
bridging, Data snapshots and String interpolation. The new fixture compares
native output with V's standard Base64 encoder and independent line splitting,
checks all 16 declared option combinations and the 64/76-column boundaries,
empty/inline/sliced inputs, the small/heap String boundary, padding, 16 MiB
inputs and independent results after releasing Data. It also checks exact ARC,
concurrent encodes, read-only input spans ending at protected pages, a protected
x8 register, invalid input rejection and two empty runtime teardowns.

Eleven final C streams/programs and four joined, retired VM phases are retained
under `build/ios/fortnite/data-base64-checks`, alongside the actual IPA call
sites and native inspection. The native-symbol lookup and oracle cleanup
failures are retained as earlier trials. Full iOS regression remains unpassed
and published runners remain unchanged.

The Base64 checkpoint resolves that encoding API, then exits with status 1 at
`_$s10Foundation4DataV36_unconditionallyBridgeFromObjectiveCyACSo6NSDataCSgFZ`
(`Data._unconditionallyBridgeFromObjectiveC(_:)`). Fortnite has not entered
application code and remains unplayable.

`Data._unconditionallyBridgeFromObjectiveC(_:)` now resolves through both
Foundation install names. A borrowed nullable NSData arrives in x0 and the
owned Data result returns in x0/x1. Nil returns canonical empty Data without
allocating snapshot storage or its descriptor arena. Non-nil built-in NSData
uses the checked snapshot constructor, including mutable, no-copy and Swift
wrapper inputs. The result survives source mutation/release and owns fresh
storage when larger than 14 bytes. Native wrapper conversion uses a different
capacity/deallocator flag layout; Vinix normalizes these inputs into its
existing private snapshot layout. Custom NSData subclasses, general Data
metadata/value witnesses and large-range values remain unsupported.

Eight ASan/UBSan runs and four Vinix ARM64 suites pass for optional NSData
conversion, Base64, Data bridging and reference snapshots. The new fixture
checks nil without descriptor allocation, unchanged source reference counts,
the 14/15-byte boundary and 16 MiB limit, native ordinary/compact storage
variants, mutable and no-copy source isolation, independent bridge roundtrips,
guarded byte/result spans and x8, concurrent nil/snapshot calls and two drained
runtime lifetimes with unmapped storage pages.

Eleven final C streams/programs and four joined, retired VM phases are retained
under `build/ios/fortnite/data-unbridge-checks`, with actual IPA consumers and
native nil/storage inspection. Earlier assertions that assumed one native
storage layout are retained as failed trials. Full iOS regression remains
unpassed; published runners remain unchanged.

The next milestone implements
`_$s10Foundation4DataV5write2to7optionsyAA3URLV_So20NSDataWritingOptionsVtKF`
(`Data.write(to:options:)`) in V. The actual IPA caller selects atomic writing.
The entry borrows URL through x0, options through x1 and Data through x2/x3;
it returns nil or one owned Error through Swift's x21 channel. It uses the
existing URL-to-NSURL witness bridge and registered Data snapshots, including
empty, inline and bounded slices up to 16 MiB. General Swift URL construction
and Data metadata/value witnesses remain separate unsupported profiles.

Options 0, 1 and 2 perform direct truncation, atomic replacement and exclusive
creation respectively. Atomic writes exclusively create a random temporary
file beside the destination, complete the write, close it and rename it into
place. Failure closes the descriptor and removes the temporary file. Ordinary
existing files preserve POSIX permission bits. Direct writes follow links;
atomic writes replace the link and leave other references to its target
unchanged. Native replacement attributes differ between APFS and HFS+, so
filesystem-specific link attributes, extended attributes, ACLs and file
protection are outside this profile. Protection/unknown options and the
invalid atomic-plus-exclusive combination fail explicitly. Paths retain the
existing 1,023-byte file URL bound. Unsupported special files fail instead of
opening a potentially blocking device or pipe.

Filesystem failures return owned Cocoa NSError values with the POSIX cause,
path and NSURL; non-file URLs return Cocoa code 518 with empty userInfo. The
tests compare native behavior, borrowed storage reference counts, guarded URL
and witness spans, unused x8 and preserved context, independent error ARC,
replacement inode/mode, links, slices, concurrent complete atomic writes and
two drained runtimes with no live objects and unmapped code pages. Eight
ASan/UBSan runs and four ARM64 suites pass for writing, Base64, bridging and
reference snapshots. Eleven final C streams/programs and four joined,
retired VM phases are retained under `build/ios/fortnite/data-write-checks`,
with native APFS/HFS+ measurements and actual IPA consumers. Failed fixture
and native attribute assumptions are retained as trials. Full iOS regression
remains unpassed; published runners remain unchanged.

The next milestone implements the actual IPA's `Date.distantPast` and
`Date.timeIntervalSince(_:)` imports in V. The resilient Date getter stores
the exact eight-byte native representation of -63114076800.0 through x8;
unused arguments and Self are not read. The interval method borrows another
Date through x0 and Self through x20, returning Self minus the other value
as a Double in d0. Both entries use the sealed Foundation arena and perform
no ARC or per-call allocation. Foundation.framework and its Swift overlay
resolve to the same entries. Date construction, metadata, equality and
coding conformances were not included in that milestone.

The fixture compares native getter bits, an actual native interval consumer,
and 576 interval pairs/guard placements per runtime, including signed zero,
finite overflow, infinities and quiet NaN payloads. It checks read-only Date
spans at both page edges, protected unused x8, exact result spans and context,
concurrent getter publication/calls, unchanged ownership counts and two
unmapped teardowns. Eight ASan/UBSan runs and four ARM64 suites pass for Date,
Data writing, Base64 and reference snapshots. Eleven final C streams/programs
and four joined, retired VM phases are retained under
`build/ios/fortnite/swift-date-checks`, with native disassembly and required
IPA fixups/consumers for both imports. The unavailable native property-getter
trial and analysis-helper include-path failure are retained. Full iOS
regression remains unpassed; published runners remain unchanged.

The following milestone implements the IPA's `Date.==` and `Date()` imports
in V. Equality borrows two eight-byte values through x0/x1 and returns a
canonical Bool in w0, including zeroed upper register bits. It compares the
stored Doubles: signed zeros compare equal, while quiet and signaling NaNs
compare unequal even when both arguments alias the same word. Neither
input is changed. The constructor reads the realtime clock's seconds and
nanoseconds, subtracts the 2001 epoch before adding the fractional second,
and stores its eight-byte result through x8. Its timestamp is explicitly
stack allocated; generated C inspection confirms no allocation on this
normal path. Both entries preserve Swift context and avoid ARC.

Eight ASan/UBSan runs and four ARM64 suites pass for Date, Data writing,
Base64 and reference snapshots. The Date fixture adds 1,024 equality
pair/guard placements per runtime, aliases, subnormals and quiet/signaling
NaNs; native equality comparisons; and fresh constructor results bounded
by the CF clock, guarded result edges and concurrent calls. The probe seeds
d0 with NaN so storing an old floating return cannot satisfy construction.
Ownership counts stay unchanged across two unmapped teardowns, and both
Foundation install names resolve to the same entries. Eleven final C
streams/programs and four joined, retired VM phases are retained under
`build/ios/fortnite/date-value-checks`, with native constructor tail-body
inspection, IPA equality call sites and constructor function-address
references. Full iOS regression remains unpassed; published runners remain
unchanged. Date metadata and protocol conformances were not included in that
milestone.

The following milestone implements Date's metadata accessor and nominal
descriptor in V. Both Foundation install names publish one complete metadata
identity for every request. Its eight-byte size/stride, alignment, native
`0x02000007` witness flags, zero extra inhabitants and field offset match the
installed runtime. Copy/take operations preserve every Double bit pattern,
including signaling NaNs, without ARC; destruction is a no-op. Single-payload
enum witnesses preserve present values and use the native ninth tag byte and
wrapping UInt32 empty-case payload. The private descriptor supports nominal
symbolic lookup; field reflection and Apple's initialization extensions remain
outside this profile. Metadata and code share the existing sealed Foundation
arena and retire with it.

Eight ASan/UBSan runs and four ARM64 suites pass for Date, Data writing,
Base64 and reference snapshots. Tests compare native metadata and all value
witnesses, exact unaligned/read-only/guarded spans, copy aliases, enum tag
boundaries, accessor result/context registers, protected unused arguments,
bounded symbolic names, eight-worker publication and two unchanged-ownership,
unmapped teardowns. Eleven final C streams/programs and four joined, retired
VM phases are retained under `build/ios/fortnite/date-metadata-checks`, with
native disassembly, generated-C allocation checks and required IPA accessor
calls and indirect nominal type references. The initial descriptor audit
that searched only text consumers and the next-blocker helper's attempt to
disassemble conformance data are retained. Full iOS regression remains
unpassed; published runners remain unchanged.

The following milestone implements Date's Encodable conformance and public
`encode(to:)` entry in V, together with the canonical Swift Encodable protocol
and its requirement descriptor. The concrete table uses the existing witness
lookup. Encoding borrows Date and Encoder, obtains an owned single-value
container, sends the Date's stored Double to its encoding witness, and destroys
the container on both success and error. The Swift error value passes through
x21 unchanged. Serialization belongs to the supplied encoder. Borrowed Encoder
values may be inline or boxed; mutable containers must fit the inline buffer.
General boxed-container uniqueness/copying remains unsupported.

The fixture compares the installed Date method and native-instantiated witness
with 432 encoding calls per runtime: signed zeros, subnormals, infinities and
quiet/signaling NaN bits, inline/boxed borrowed encoders, guarded read-only
inputs at both page edges, exact callback metadata/table/Self, container
mutation/destruction order, opaque error propagation, preserved Self/d8 and
eight-worker calls. Both Foundation aliases resolve to the same implementation,
and two runtime lifetimes drain and unmap. Eight ASan/UBSan runs and four ARM64
suites pass for Date, Data writing, Base64 and reference snapshots. Eleven final
C streams/programs and four joined, retired VM phases are retained under
`build/ios/fortnite/date-encoding-checks`. Native inspection follows authenticated
dispatch stubs to the Encoder/container requirements, and the IPA's required
conformance fixup and address consumers are retained. The indirect-protocol
inspection trial and missing-sysroot/link-library build trials are retained.
All 1,772 pinned files from the missing shared sysroot were recovered byte for
byte into a private SDK, with five empty musl compatibility archives pinned
for implicit C++ link dependencies. Full iOS regression remains unpassed;
published runners remain unchanged.

The following milestone supplies Date's Equatable conformance in V. Its sealed
concrete table points to the existing Date floating comparison entry and the
canonical Swift Equatable protocol. Native's instantiated witness and public
operator have identical five-instruction bodies: two borrowed Double loads,
floating comparison and a canonical Bool return. Signed zeros compare equal;
quiet/signaling NaNs compare unequal, including aliases. This table needs no
new call path, ARC work, per-call allocation or resilient witness factory.

Tests compare 1,024 witness pair/guard placements per runtime plus aliases,
64 generic Equatable dispatch pairs, protected unused metadata/x8, canonical
Bool/context returns, eight-worker conformance publication, Foundation aliases
and two drained, unmapped runtime lifetimes. Eight ASan/UBSan runs and four
ARM64 suites pass for Date, Data writing, Base64 and reference snapshots.
Eleven final C streams/programs and four joined, retired VM phases are retained
under `build/ios/fortnite/date-equality-checks`, with native witness disassembly,
required IPA conformance/address consumers and inspection of the next native
Decodable dependency. The builds reuse the previous milestone's verified private
SDK. Full iOS regression remains unpassed; published runners remain unchanged.

The following milestone implements Date's Decodable conformance and public
`init(from:)` in V. Its concrete table uses the canonical Swift Decodable
descriptor and throwing initializer requirement. The initializer consumes its
Decoder, obtains an owned single-value container, and reads a Double through
the container's witness. Either callback can throw: a failed getter leaves no
container to destroy, while a failed decode still destroys the initialized
container. Both paths consume the Decoder and forward the owned error through
x21 without reading its storage or retaining it. Only success initializes the
indirect eight-byte Date result.

Readonly projection supports inline values and boxed payloads. Destroying a
boxed existential releases its owner, preserving shared boxes until the final
reference; inline values use their destroy witness. General Decoder factories,
JSON parsing, mutable box copying and unsupported existential layouts remain
outside this profile. The callback dispatch uses the existing sealed arena and
adds no per-call allocation.

The Date fixture compares native Foundation's public initializer and instantiated
witness with Vinix's entries. Each runtime runs 1,440 calls across nine Double
bit patterns, both failure stages, guarded result/input spans, inline and boxed
Decoder/container combinations, retained boxes and eight workers. It checks
exact destruction counts and order, unreadable error pointers, preserved Swift
context and d8, scoped framework/protocol exports and two drained, unmapped
runtime lifetimes. Evidence is retained under
`build/ios/fortnite/date-decoding-checks` with the prior verified private SDK.
Eight ASan/UBSan runs and four Vinix ARM64 suites pass for Date, Data writing,
Base64 and reference snapshots. Eleven final C streams/programs and four joined,
retired VM phases are retained. Full iOS regression remains unpassed; published
runners remain unchanged.

The next milestone implements Swift `Locale.init(identifier:)`, nominal
metadata, value witnesses, the identifier getter and the Objective-C bridge
in V. Both constructor call sites in this IPA pass the frozen small String
`en_US_POSIX`. The constructor consumes its String and writes an owned
sixteen-byte implementation/table pair through x8. A built-in NSLocale owns
an independent NSString snapshot; copying the Swift value retains its owner,
and final destruction releases that snapshot through ordinary Objective-C ARC.
This private implementation has no permanent locale cache.

The fixed-locale profile accepts empty, C/POSIX roots and the modern language
codes en, de, fr, ru, zh, sr, es, pt, ja, ko, it, ar, he, hi, id and yi, plus
the measured iw/in/ji aliases. It canonicalizes supported script/region/POSIX
components within 128 bytes. Region separators are preserved; scripts use a
hyphen; underscore POSIX variants are uppercase and hyphen variants lowercase.
Legacy underscore scripts require their canonical spelling. ICU keywords,
extensions, other variants, Unicode identifiers and the broader alias database
remain unsupported. The borrowed getters dispatch through implementation slots
64 and 488 with formal class metadata; their String and NSLocale results are
owned and survive release of the original Swift value.

The new Locale fixture compares the installed Foundation APIs with Vinix for
24 identifier cases, inline/immortal/owned String inputs, guarded result/Self
spans, copy and take assignment, optional-value tags, result lifetimes and
eight-worker construction/publication. Two private runtimes drain their object,
String and Swift heap registries and unmap their sealed arena. The public V
harness registers `swift-locale-checks` and `build-swift-locale`; full iOS
regression remains unpassed. Evidence is retained under
`build/ios/fortnite/locale-checks` using the prior verified private SDK.
Ten ASan/UBSan runs and five Vinix ARM64 suites pass for Locale, Date, Data
writing, Base64 and reference snapshots. Thirteen final C streams/programs
and four joined, retired VM phases are retained; published runners are unchanged.

The Locale milestone's IPA probe resolves the constructor, bridge and nominal
metadata, then exits with status 1 at
`_$s10Foundation8CalendarV10IdentifierO7iso8601yA2EmFWC`
(`Calendar.Identifier.iso8601`).

The next milestone supplies that resilient enum case as a read-only, aligned
four-byte discriminator containing 7, through both Foundation and the Swift
Foundation overlay. The IPA loads it into w1 and passes it to the identifier
enum's tag-injection witness at offset 104. Native Foundation constructs the
one-byte ISO 8601 enum value from this discriminator; the exported data itself
is four bytes. Calendar construction, identifier metadata and other calendar
cases remain unsupported.

The `swift-calendar-case-checks` fixture compares native and Vinix data loads,
guarded four-byte read/write spans, canaries, framework scoping and eight-worker
publication/readers. On the Mac, the exported value also passes native enum
injection, tag, copy and destruction checks. Two private runtime lifetimes
retire and unmap the sealed arena without retaining objects or Swift storage.
The public V driver registers `build-swift-calendar-case` and includes the
fixture in its Swift and full-regression inventories.

Evidence is retained under `build/ios/fortnite/calendar-case-checks` using the
prior verified private SDK. Twelve ASan/UBSan runs and six Vinix ARM64 suites
pass for the Calendar case, Locale, Date, Data writing, Base64 and reference
snapshots. Fifteen final C streams/programs and four joined, retired VM phases
are retained; published runners are unchanged. Full iOS regression remains
unpassed.

The case-only IPA probe links past ISO 8601 and exits with status 1 at
`_$s10Foundation8CalendarV10IdentifierOMa`
(`Calendar.Identifier` metadata).

The next milestone supplies that metadata accessor, its nominal descriptor and
all eleven value/enum witnesses in V. Native Identifier is an inline one-byte
POD enum with 27 cases and 229 extra inhabitants. Copy/take witnesses transfer
exactly one byte; destruction and payload projection do no work. Tag injection
stores the low byte. Single-payload enums consume spare values before adding
one, two or four tag bytes. The implementation follows native's conservative
width thresholds and UInt32 wraparound, including truncated results for extreme
empty-case counts.

The accessor returns complete metadata in x0/x1 for all request values tested.
Its private nested `Foundation.Calendar.Identifier` descriptor has a Calendar
parent context without exposing Calendar metadata or construction. Bounded
symbolic type lookup uses the descriptor's accessor. Both Foundation aliases
publish the same sealed arena; two runtime lifetimes drain and unmap it.

The existing Calendar fixture now checks all 27 values, all copy/take slots,
one-byte guarded spans, optional-tag boundary/wraparound byte effects, borrowed
read-only inputs, protected unused metadata/Self/result registers, nominal
identity, accessor responses, bounded symbolic lookup and eight-worker
publication/use against installed Foundation. Other case exports, Calendar
construction and field reflection remain unsupported.

Evidence is retained under `build/ios/fortnite/calendar-identifier-checks` using
the prior verified private SDK. Twelve ASan/UBSan runs and six Vinix ARM64 suites
pass for the Calendar case/metadata, Locale, Date, Data writing, Base64 and
reference snapshots. Fifteen final C streams/programs and four joined, retired
VM phases are retained; published runners are unchanged. The generated C
confirms that the new witnesses and metadata emitter allocate no memory.
Full iOS regression remains unpassed.

The Identifier-metadata probe links past that accessor and exits with status 1 at
`_$s10Foundation8CalendarV10identifierA2C10IdentifierOh_tcfC`
(`Calendar.init(identifier:)`).

The next milestone implements that constructor, the Calendar metadata/accessor
and its identifier getter in V. The consuming input is a one-byte indirect
Identifier; the owned Calendar result is a sixteen-byte implementation/table
pair written through x8. All 27 identifier values are retained independently in
private, registered Swift heap storage. Ordinary unknown-object ARC witnesses
implement copy/take assignment and destruction; the last release deallocates
the owner. There is no permanent Calendar cache.

Calendar's descriptor completes the same parent context already used by
`Calendar.Identifier`, preserving nominal identity. The borrowed identifier
getter obtains the implementation's formal class metadata, calls table slot 24
with native context, and writes exactly one result byte through x8. A custom
implementation-table test checks this dispatch against native Foundation,
including native pointer authentication. The private storage class is an
implementation detail; Objective-C bridging, calendrical operations, mutation
and field reflection remain unsupported.

The existing Calendar fixture now checks all 27 constructors with guarded
one-byte input and sixteen-byte result spans, read-only borrowed values,
independent copied values, initialize/assign copy/take slots, optional tags,
eight-worker construction/publication and two drained runtime lifetimes. Its
registry assertions use the runtime lock and allocation generations, so
concurrent address reuse does not masquerade as a retained owner.

Evidence is retained under `build/ios/fortnite/calendar-checks` using the prior
verified private SDK. Twelve final ASan/UBSan runs and six Vinix ARM64 suites
pass for Calendar/Identifier, Locale, Date, Data writing, Base64 and reference
snapshots. Fifteen final C streams/programs and four joined, retired VM phases
are retained; published runners are unchanged. Generated C shows the explicit
24-byte Swift heap allocation and its matching deallocation; the successful
getter and emitter paths add no hidden allocations. Full iOS regression remains
unpassed.

The Calendar-construction IPA probe links past that constructor and exits with status 1
at `_$s10Foundation8CalendarV10startOfDay3forAA4DateVAG_tF`
(`Calendar.startOfDay(for:)`).

The next milestone implements that method's borrowed implementation-table
dispatch in V. It passes the one-byte `Component.day` value to slot 160 with
the owner's formal metadata, implementation table and borrowed owner. The
callback returns an optional sixteen-byte DateInterval plus a discriminator;
the method writes exactly one eight-byte Date through x8. A present interval
returns its start without interpreting the duration. A missing interval returns
the original input minus one second, matching installed Foundation.

The callback's input is clamped to -211845067200 through 15927175497600 seconds
since 2001. Native floating-point comparisons send NaNs to the lower bound,
preserve signed zero, and clamp infinities. The fallback still uses the original
input. These behaviors, the callback ABI, native pointer authentication and
the discriminator's byte offset were measured against the Mac's Foundation.

The IPA's setup at `0x100067118` constructs an ISO 8601 calendar, assigns
`en_US_POSIX`, constructs `TimeZone(secondsFromGMT: 0)` at `0x100067184` and
assigns that timezone at `0x1000671b4`. Its borrowed start-of-day call is at
`0x100069094`. The V/Mach-O/LLVM inspection retains the import fixups, branch
islands and annotated calls under `calendar-day-checks/setup-inspect.log`.

This completes the public forwarding adapter only. Vinix's private Calendar
storage currently holds an identifier snapshot; its day-interval callback
explicitly reports that a timezone-aware backend is unavailable. It does not
invent a UTC day boundary. Calendar locale/timezone mutation, timezone rules,
the private interval backend and Objective-C bridging remain unsupported.

The Calendar fixture checks native and Vinix dispatch with read-only borrowed
Date, Calendar and callback-table pages, guarded eight-byte results, bound
neighbors, infinities, signed zeros, quiet/signaling NaNs, present/missing
intervals and eight concurrent callers. Callbacks returning no interval leave
the payload uninitialized so only the discriminator may be read. Each suite makes
285 calls, and both Vinix runtime lifetimes drain and unmap their arenas.

Evidence is retained under `build/ios/fortnite/calendar-day-checks`. Twelve
ASan/UBSan runs and six Vinix ARM64 suites pass, with fifteen final C streams
and executables and four joined, retired VM phases. Generated C confirms that
the emitter adds no allocations. Published runners are unchanged; full iOS
regression remains unpassed.

The start-of-day IPA probe links past that export and exits with status
1 at `_$s10Foundation8CalendarV6localeAA6LocaleVSgvs`
(`Calendar.locale` setter).

The next milestone implements the Calendar locale getter and consuming setter
in V for built-in Calendar and fixed Locale values. The setter consumes a
sixteen-byte indirect optional Locale in x0 and updates the Calendar through
x20. Assigning nil preserves the current setting, matching the native copy
operation. An equal fixed locale consumes the supplied owner without changing
the snapshot; a changed locale transfers that owner to fresh immutable storage.
Copied Calendars keep their previous settings. Foreign Calendar or Locale
implementations are rejected by the setter.

Calendar's private heap owner grows to forty bytes to own its Locale pair. Its
last release drops that locale before deallocating the owner. The borrowed
getter calls implementation-table slot 32 with the owner's formal metadata and
table, then maps a missing implementation locale to an owned empty-identifier
Locale. The ISO 8601 identifier instead starts with `en_001`, as measured for
all 27 identifiers against installed Foundation. Getter results remain valid
after Calendar mutation or destruction.

The Calendar fixture exercises 54 guarded mutation cases across all identifiers,
consuming read-only optional inputs, nil and equal assignments, canonical
aliases, owned results and preserved copies. Eight workers make 128 mutations
of separate values copied from one shared Calendar. Two runtime lifetimes must
drain their heap and Objective-C owners and unmap the sealed metadata arena.
Timezone mutation, the private day-interval backend and Objective-C Calendar
bridging remain unsupported.

Evidence is retained under `build/ios/fortnite/calendar-locale-checks`. Twelve
ASan/UBSan runs pass. The first guest run passed Calendar, Locale and Date, then
failed during Data-write directory cleanup with `Directory not empty` (39).
The same executables passed all six suites in a fresh guest. The failed serial
log and payload hashes remain in `guest-cleanup-trial`; no fixture or production
code was changed for the retry. Fifteen C streams/programs and four completed
VM phases are retained; published runners are unchanged. Generated C confirms
explicit forty-byte owner allocation/deallocation and Locale transfer/release without hidden allocations
in the new successful paths. Full iOS regression remains unpassed.

The locale-assignment IPA probe links past that setter and exits with
status 1 at `_$s10Foundation8CalendarV8timeZoneAA04TimeD0Vvs`
(`Calendar.timeZone` setter).

The next milestone implements fixed-offset TimeZone construction, metadata and
identifier access, Calendar timezone assignment/getting, and actual Gregorian
and ISO 8601 day intervals in V. The IPA explicitly constructs GMT+0 and assigns
it after `en_US_POSIX`; that sequence can now compute `startOfDay(for:)` using
the private Calendar backend.

TimeZone is an owned sixteen-byte implementation/table pair. Its private
twenty-four-byte Swift heap owner preserves exact offset seconds in the inclusive
range -64800 through 64800; offsets just outside that range return nil. Native
identifiers round to minutes, with half-minutes rounded away from zero, while
the offset used in date calculations remains exact. Native timezone equality
uses the rounded identifier: assigning GMT+1 second over GMT+0 preserves the
old exact offset. The setter matches that behavior and consumes the supplied
TimeZone on both changed and equal assignments. The native minimum-Int probe
trapped; its source, executable and failed log are retained in
`native-minimum-trial`. Vinix checks bounds before arithmetic or allocation.

Calendar's immutable owner grows to fifty-six bytes to own both Locale and
TimeZone. Changing either property preserves the other, and copied Calendars
and owned getter results remain independent. The last release drops both
settings and deallocates the owner. A new Calendar has no implemented default
timezone snapshot: timezone access and day calculations require an explicitly
assigned fixed TimeZone. Named zones, daylight-saving rules, other calendar
calculations and Objective-C TimeZone/Calendar bridging remain unsupported.

The day-interval callback accepts `Component.day` and the public method's
clamped Date, returns a POD DateInterval of 86400 seconds, and writes
the optional discriminator after its two Doubles. It floors the timestamp
before dividing by the day length, so even the smallest negative subnormal
selects the previous day. Native checks cover bound neighbors, signed zero,
infinities, NaNs, minute rounding, exact-second offsets and negative dates.

The Calendar fixture exercises 88 guarded constructor/setting cases across
Gregorian and ISO calendars and both span boundaries, consuming read-only
timezone inputs, independent locale/timezone snapshots and getter lifetimes.
Eight workers perform 224 timezone assignments on values copied from one
fixed-zone Calendar; equal rounded identifiers must preserve its previous exact
seconds. Every runtime lifetime must drain all Calendar, TimeZone and
Objective-C owners before unmapping its
sealed metadata pages.

All twelve normal/deterministic ASan/UBSan host runs and six ARM64 Vinix guest
suites pass. The native comparison, fifteen archived generated C streams and
executables, four retired VM phases and pinned inputs are retained under
`build/ios/fortnite/calendar-zone-checks`. Generated C confirms explicit
Calendar/TimeZone allocation and matching destruction without hidden allocations
in the new successful paths. Published runners remain unchanged; the full iOS
regression remains unpassed.

The fixed-zone IPA probe links past the TimeZone constructor, metadata and
Calendar timezone setter, then exits with status 1 at
`_$s10Foundation8TimeZoneV19_bridgeToObjectiveCSo06NSTimeC0CyF`.

The next milestone implements that borrowed Swift TimeZone bridge in V. Native
dispatch uses implementation-table slot +128, passing the formal owner type,
table, owner and slot address, and returns an owned NSTimeZone in x0. The
private callback creates a fresh immutable Objective-C snapshot on each call;
the snapshot survives destruction of the Swift value and autorelease-pool
drain. Its public class layout is eight bytes, with exact fixed-offset seconds
stored in owned Vinix metadata. No Swift owner is retained by the bridge.

The fixed NSTimeZone profile provides `name`, abbreviations, exact
`secondsFromGMT` queries, equality/hash, retained immutable copies, fixed DST
queries, method type encodings and the bounded `timeZoneForSecondsFromGMT:`
factory. Names and equality use the native minute rounding while calculations
retain exact seconds. Abbreviations use the native form, such as `GMT+5:30`;
fixed zones have no DST or future transition. Default/current/named zones,
custom subclasses, coding, localized formatting, reverse Swift bridging and
Calendar Objective-C bridging remain unsupported.

The Calendar fixture compares 44 guarded bridge cases with native Foundation,
including nine-byte abbreviations such as `GMT+17:01`.
It checks repeated independent bridges, immutable copies, retained names,
source and autorelease-pool teardown, twelve equality pairs, typed date/DST
queries, a substituted generic bridge witness and 256 concurrent bridges from
one borrowed Swift value. Each private runtime must drain every snapshot before
unmapping its sealed Swift metadata.

All twelve normal/deterministic ASan/UBSan host runs and six ARM64 Vinix guest
suites pass. Native reference tools, fifteen generated C streams and executables,
four retired VM phases and pinned inputs are retained under
`build/ios/fortnite/timezone-bridge-checks`. Generated C confirms explicit owned
Objective-C allocation without hidden V allocations in the new successful paths.
Published runners remain unchanged; the full iOS regression remains unpassed.

The TimeZone-bridge IPA probe links past that bridge and NSTimeZone class import,
then exits with status 1 at
`_$sSD10FoundationE19_bridgeToObjectiveCSo12NSDictionaryCyF`
(Swift Dictionary's Objective-C bridge).

The next milestone implements that Dictionary bridge in V. Its native ARM64 ABI
passes a borrowed storage word, Key/Value metadata and Key:Hashable table in
x0 through x3 and returns an owned NSDictionary in x0; Self and x8 are unused.
Tagged Cocoa dictionaries retain their original Objective-C identity without
reading the generic arguments. Their positive low-bit bridge tags now also
support the runtime's bridge-object retain/release operations.

For registered native `Swift._DictionaryStorage`, the bounded profile validates
the generic class descriptor and arguments, allocation extent, count/capacity,
scale, key/value tail pointers and occupied bitmap. String keys and String, Int,
inline Any containing those values or NSObject references are supported, with
at most 4096 entries, scale 14, a 16 MiB source allocation and 1 MiB per String.
Conversion creates
an independent immutable NSDictionary, retaining object values and copying
Strings. Two zeroed arrays belong to the result; a bounded temporary hash table
detects duplicate bridged keys and is freed on success and conversion errors.
Partially populated results release every converted key/value before returning
an error. Dictionary construction/copy/resize, other key types, boxed/nested Any
and general Swift-to-Objective-C value boxing remain unsupported.

The required `__swiftEmptyDictionarySingleton` export uses the measured immutable
header, sentinel pointers and bitmap in the sealed Foundation arena. Its native
ARC state is immortal, and canonical empty dictionaries bridge to the runtime's
cached immutable NSDictionary. Existing empty JSON userInfo dictionaries share
that conversion path.

The dedicated fixture compares native Foundation and Vinix across 25 populated
or empty cases, including mixed Any values, sparse bitmap boundaries and 4096
entries. It checks source/pool teardown, independent owned results, six Cocoa
tag forms with protected generic arguments, tagged ARC, eight concurrent readers,
invalid storage fields and partial-error cleanup in two drained runtimes.

All 14 normal/deterministic sanitizer runs and seven ARM64 guest suites pass.
The 17 generated C streams and executables, native library measurements,
actual IPA call sites, four retired VM phases and pinned inputs are retained
under `build/ios/fortnite/dictionary-bridge-checks`. The generated C audit checks
the result arrays, temporary hash-table cleanup and partial-result ownership.
Published runners remain unchanged; the full iOS regression remains unpassed.

The Dictionary-bridge IPA probe links past that bridge and the empty Dictionary
global, then exits with status 1 at
`_$sSa10FoundationE36_unconditionallyBridgeFromObjectiveCySayxGSo7NSArrayCSgFZ`
(NSArray to Swift Array conversion).

The next milestone implements that Array bridge in V. Native ARM64 inspection
shows a borrowed optional NSArray in x0, Element metadata in x1 and an owned
Array result in x0. Self and x8 are unused; nil returns the immortal empty Array
without reading Element metadata. The actual IPA call at `0x100074598` passes
the result of Foundation's URL metadata accessor, so this path must handle
`[URL]` as well as reference elements.

The bounded implementation accepts registered NSArray/NSMutableArray storage
with at most 4096 non-nil object members. It retains an ordered member snapshot
under the runtime lock, then constructs existing typed Swift Array storage.
Supported elements are String, URL and canonical NSObject-derived wrappers.
String conversion copies up to 1 MiB per value; object values retain their
identity. Duplicates and order are preserved. The initialized count advances
only after constructing each element, so failure releases the initialized
prefix and the entire source snapshot. The result works with existing Array
value witnesses and Sequence operations after source mutation, release and
autorelease-pool teardown. Any, numeric/value coercions, custom conversions and
general native storage reflection remain unsupported.

URL elements use a retained built-in NSURL implementation owner and a private
sealed witness table compatible with the existing two-word URL value. Its
Objective-C bridge returns an owned NSURL. File URL append/delete operations
use that same table and preserve directory slashes and percent-encoded strings.
The bounded path profile accepts absolute file paths up to 65536 bytes and
single nonempty components up to 4096 bytes; slash, backslash, NUL and dot
components are rejected. HTTP URLs support round-trip bridging; their path
mutation and other URL protocol slots remain unsupported. Parent paths are
copied using explicit lengths, including prefixes without a NUL terminator.

Concurrent readers exposed a race in NSURL's existing lazy `absoluteString`
cache. Its publication now holds the runtime lock so readers cannot replace
and release another reader's cached string. The failing sanitizer run and
generated C are retained with the new cohort's evidence.

The dedicated fixture compares 48 native/Vinix array cases across four Element
types, immutable/mutable sources and counts through 4096. It checks protected
nil metadata/Self/x8 arguments, independent source/result lifetimes, Array
copy/take/destruction, contiguous Sequence consumption, duplicate references,
HTTP round trips, file URL path operations, concurrent readers, invalid member
provenance/types and partial cleanup. It also writes Data through a bridged file
URL and requires two private runtime lifetimes to drain completely.

All 16 normal/deterministic sanitizer runs and eight ARM64 guest suites pass.
The 19 generated C streams and executables, native measurements, actual IPA
call site, four retired VM phases and pinned inputs are retained under
`build/ios/fortnite/array-unbridge-checks`. The generated C audit checks explicit
snapshot/buffer cleanup and initialized-prefix ownership. Published runners
remain unchanged; the full iOS regression remains unpassed.

The first guest image omitted the new fixture; its captured failure output is
retained. After the temporary RAM staging volume disappeared, guest binaries
were rebuilt from the verified C archives and the corrected image passed.
The lost RAM-only boot/serial files and raw supervisor logs are identified in
the evidence; joined child output and statuses remain available on Data.

The Array-bridge IPA probe links past that bridge, then exits with status 1 at
`_$sSy10FoundationE20replacingOccurrences2of4with7options5rangeSSqd___qd_0_So22NSStringCompareOptionsVSnySS5IndexVGSgtSyRd__SyRd_0_r0_lF`
(StringProtocol's String replacement operation).

V now supplies that String replacement entry for concrete String arguments.
Installed Foundation disassembly and guarded native calls establish the ABI:
pattern/replacement addresses in x0/x1, options in x2, optional Range payload
in x3/x4 and its tag in the low byte of x5, Self/Pattern metadata in x6/x7,
Replacement metadata followed by three StringProtocol tables on the stack,
and borrowed indirect Self in x20. The owned String result returns in x0/x1;
the caller's x20/x21 survive. The adapter uses stack storage in the existing
sealed Foundation arena. This concrete specialization invokes no generic
callbacks and does not read the witness tables or nil Range payload.

Actual IPA calls include `0x1000697b4` and `0x10006e730`: all three metadata
arguments are String, options are zero and the Range is nil. Their literal
patterns include space, `+`, `/` and `=`, including Base64 URL cleanup.
Default search supports ASCII source/pattern; literal search (option 2) also
accepts validated Unicode. Replacement text may contain Unicode or NUL.
Empty patterns leave the text unchanged. Matches are nonoverlapping and
left-to-right. Default Unicode canonical equivalence, other search options,
explicit ranges and other StringProtocol types remain unsupported.

Input/output text is bounded to 1 MiB and the pattern to 4096 bytes. The
two-pass KMP search runs in linear time, including repeated-prefix inputs.
Its explicitly allocated prefix table and output buffer are freed on success
and every error. Inline/native-tail strings, registered owned storage and
checked foreign NSString storage are borrowed under the runtime lock; result
bytes are copied into existing owned Swift String storage. Shared/custom
storage remains unsupported. Alias inputs and protected, non-NUL-terminated
literal spans work without mutating or consuming their owners.

The dedicated fixture compares 61 native/Vinix cases across inline/literal
and owned inputs, Unicode literal search, NULs, empty patterns, deletion,
overlaps, size boundaries and adversarial 4096-byte patterns. It also checks
native runtime-instantiated StringProtocol tables, independent result/pool
lifetimes, protected nil/x8 arguments, private foreign/alias inputs, rejected
metadata/representations/options/ranges/limits, eight concurrent workers and
two fully drained runtime lifetimes. The initial native fixture incorrectly
used a witness pattern instead of an instantiated table for the literal
path; its sanitizer failure and generated C are retained.

All 18 normal/deterministic sanitizer runs and nine ARM64 guest suites pass.
The 21 generated C streams and executables, native measurements, actual IPA
call sites, four retired VM phases and pinned inputs are retained under
`build/ios/fortnite/string-replace-checks`. Generated C inspection checks the
stack temporaries and explicit buffer cleanup. Published runners remain
unchanged; the full iOS regression remains unpassed.

The String-replacement IPA probe links past that operation and exits with
status 1 at `_NSHomeDirectory`.

V now supplies Foundation's `NSHomeDirectory` C entry. Installed-library
inspection shows a no-argument call returning a +0 NSString in x0, with the
ordinary preserved-register ABI. Native calls agree with the file manager's
home URL, return independently autoreleased strings, and survive pool teardown
when explicitly retained. Separate native processes verify that changing HOME
does not change the result, while Foundation's fixed-home setting selects a
normalized path. The IPA calls this entry at `0x100628924` and `0x1006289ec`,
including a filesystem capacity query inside an autorelease pool.

Vinix uses its existing application Documents convention: home is the parent
of VINIX_IOS_DOCUMENTS when configured, otherwise the parent of the loaded
bundle. Paths are absolute, valid UTF-8 and at most 1023 bytes; NUL and dot
components are rejected. Trailing/repeated separators are normalized. The
getter reads bounded borrowed configuration and path prefixes, copies into a
new NSString and autoreleases it on the calling thread. It does not create
directories, resolve symlinks, consult host account paths or add a permanent
cache. Calls require an active runtime and a configured bundle or Documents
path; configuration is established before app initializers and worker threads.

The fixture checks direct calls and protected ARM64 arguments/x8/x20, preserved
x20/x21, +0 ownership and retained strings after pool teardown. Eleven private
path cases cover both configured roots, Unicode/spaces, root and repeated or
trailing separators, the 1023-byte boundary and non-NUL-terminated protected
prefixes. It also checks Documents-directory integration without home-query
side effects, rejected inputs/lifetimes, eight concurrent readers and two
completely drained runtimes.

All 20 normal/deterministic sanitizer runs and ten ARM64 guest suites pass.
The 23 generated C streams and executables, native measurements, actual IPA
calls, four retired VM phases and pinned inputs are retained under
`build/ios/fortnite/home-directory-checks`. Generated C inspection verifies
borrowed spans, stack normalization and copied autorelease ownership without
hidden V temporaries. The initial successful prefix-only host trial is retained
separately from the final normalized-path results. Published runners remain
unchanged; the full iOS regression remains unpassed.

The home-directory IPA probe links past `NSHomeDirectory` and exits with status
1 at `_NSLogv`.

V now supplies Foundation's `NSLogv` entry with a borrowed NSString in x0 and
the Darwin ARM64 stack argument pointer in x1. The IPA calls this entry at
`0x1000906fc`, forwarding its original anonymous argument slots after building
an NSString format. Installed Foundation calls and disassembly verify that ABI,
preserved context registers, reusable input slots, stderr output and newline
behavior. Native measurements also cover Unicode object text, nil arguments,
embedded NULs and Foundation's negative dynamic string-width behavior.

The implementation copies the format under the runtime lock, validates its
complete grammar before accessing arguments, and renders each object description
once before locking stderr for a complete message write. It supports plain `%@`,
common integer and double conversions, `%s`, `%c`, `%p`, percent escaping and
scalar width/precision arguments. Formats are bounded to 64 KiB, argument lists
to 512 eight-byte slots and messages to 1 MiB. `%n`, positional arguments, wide
characters, long doubles and decorated `%@` conversions fail explicitly. Caller
argument/string spans must be readable. The existing variadic `NSLog` entry now
shares this formatter and writes to stderr. Vinix emits message text without
Foundation's host timestamp/process prefix.

Eight normal/deterministic sanitizer runs and four ARM64 guest suites pass:
the new fixture, Swift NSLog, OS logging and autorelease pools. Tests include
protected spare registers and argument/string boundaries, native formatting
comparisons, limit/error cases, reentrant descriptions, eight concurrent writers
and two fully drained runtimes. The eleven generated C streams and executables,
native measurements, IPA call sites, four retired VM phases and pinned inputs
are retained under `build/ios/fortnite/nslogv-checks`. Generated C inspection
checks stack scratch, explicit buffer frees and pool cleanup. The initial native
width mismatch and private build-list omission are retained with their corrected
results. Published runners remain unchanged; the full iOS regression remains
unpassed.

The NSLogv IPA probe links past logging and exits with status 1 at
`_NSProtocolFromString`.

V now supplies Foundation's `NSProtocolFromString` and an Objective-C protocol
registry. Native measurements verify the borrowed NSString argument and +0
Protocol result in x0, preserved contexts, case-sensitive UTF-8 names, nil and
unknown-name results, embedded-NUL rejection and stable identities across
autorelease pools. Fortnite's calls at `0x100054c38` and `0x100054cdc` request
`UNUserNotificationCenterDelegate`, then send `conformsToProtocol:`. That
protocol is present among the main executable's 79 declarations; EOSSDK has
seven more declarations. Their emitted descriptors are 96 bytes.

Image registration validates protocol roots, adoption graphs and writable
reference cells before publishing them. It copies names and graph edges,
coalesces identities by name and rewrites protocol references to canonical
runtime metadata. Class and category adoption lists feed the same registry.
Protocol objects support ARC as immortal metadata until quiescent shutdown.
The supplied NSObject adoption and six basic Foundation protocol identities
are installed at startup; further supplied-framework class adoptions still
require individual implementation. Image-declared adoptions are registered.

The libobjc entries cover name lookup, names, equality, protocol conformance,
class conformance and class adoption. Native comparison distinguishes the C
class query, which checks that class's declarations, from NSObject's method,
which also searches superclasses. Adding a protocol rejects one already
implied by a direct adoption and accepts one inherited only from a superclass.
The new method is also advertised by `respondsToSelector:`. Lookups and
conformance traversal allocate no heap scratch. Names are bounded to 1023 UTF-8
bytes, the registry to 4096 identities and 16384 image aliases, and metadata
traversal to 64 levels. Method/property reflection and Swift demangled protocol
aliases remain unsupported.

Eight normal/deterministic sanitizer runs and four ARM64 guest suites pass:
protocol lookup, supplied instance storage, associated objects and autorelease
pools. Coverage includes guarded C arguments, copied names, canonical image
references, class/category adoption, inherited conformance, nullable equality,
protected NSString spans, malformed/cyclic/truncated metadata, concurrent
readers and two completely drained registries. The eleven final generated C
streams and executables, native measurements, actual IPA protocol tables and
calls, four retired VM phases and pinned inputs are retained under
`build/ios/fortnite/protocol-lookup-checks`. Initial conformance/array failures,
cross-target guard checks, restored native fixture setup and the successful
trial before the method-availability fix are retained separately. Generated C
inspection checks the allocation-free query paths and explicit metadata/name/
array retirement. Published runners remain unchanged; the full iOS regression
remains unpassed.

The protocol-lookup IPA probe links past protocol discovery and exits with
status 1 at `_NSSetUncaughtExceptionHandler`.

V now supplies Foundation's `NSSetUncaughtExceptionHandler` and
`NSGetUncaughtExceptionHandler`. Native comparison verifies a nullable,
borrowed C function pointer shared by all threads: replacement and clearing on
one thread are immediately visible on another, and thread exit leaves the
registration intact. Both native exports tail-call the same helper with
different numeric arguments; direct cross-thread measurements establish the
storage scope. Fortnite registers an application function in x0 at
`0x1000a9284`.

The runtime serializes reads and writes with its recursive runtime lock, stores
the opaque address without dereferencing or retaining it, and clears it after
workers and teardown callbacks drain, before application images are unmapped.
These entries implement handler registration and retrieval. Objective-C
throwing and exception unwinding through Mach-O frames remain unsupported.

Eight normal/deterministic host sanitizer runs and four ARM64 guest suites pass:
handler registration, protocol lookup, NSThread and autorelease pools. The
handler fixture compares native and private behavior, including protected
pointer values, unused C argument registers, preserved callee contexts,
cross-thread replacement/clear, registration surviving worker exit, 1024
contended updates and two clean runtime lifetimes. The eleven generated C
streams and executables, actual IPA consumer, native measurements, pinned
inputs and four retired VM phases are retained under
`build/ios/fortnite/uncaught-handler-checks`. Generated C inspection checks
allocation-free registration/retrieval and explicit callback retirement.
Published runners remain unchanged; the full iOS regression remains unpassed.

The handler-registration IPA probe links past that import and exits with
status 1 at `_NSStringFromProtocol`.

V now supplies Foundation's `NSStringFromProtocol`. Native comparison verifies
the borrowed Protocol argument in x0, a +0 NSString result, exact UTF-8 names
and the literal `"nil"` for a nil protocol. The libobjc `protocol_getName(nil)`
result is also corrected to `"nil"`. Fortnite's calls at `0x100042b54`,
`0x100042ef8` and `0x100042fcc` retain the autoreleased result.

The implementation resolves canonical and image-alias protocol identities
under the runtime lock and copies the registry-owned name into an autoreleased
NSString. It rejects foreign pointers without dereferencing them and retains
the existing 1023-byte registry name limit. Native Foundation also accepts
longer names; the private registry's bound remains explicit.

Eight normal/deterministic host sanitizer runs and four ARM64 guest suites
pass: protocol-name conversion, protocol lookup, handler registration and
autorelease pools. Coverage includes nil, Unicode, spaces, 1023-byte names,
guarded C arguments and preserved contexts, round trips, strings retained
across pool drains, copied image names erased after registration, eight
concurrent readers and two completely drained registries. The eleven final
generated C streams and executables, native measurements, actual IPA calls,
pinned inputs and four retired VM phases are retained under
`build/ios/fortnite/protocol-name-checks`. Generated C inspection checks copied
string storage and allocation-free protocol lookup. Published runners remain
unchanged; the full iOS regression remains unpassed.

The protocol-name IPA probe links past that import and exits with status 1 at
`_NSTemporaryDirectory`.

V now supplies Foundation's `NSTemporaryDirectory`. Measurements against this
Mac's Foundation verify a no-argument C entry, a +0 NSString with a trailing
separator and a path matching NSFileManager's temporary-directory URL.
Thirteen isolated process environments also confirm that this installed
Foundation ignores `TMPDIR`, including changes after the first query.
Fortnite has four direct consumers at `0x100036330`, `0x1000a95c4`,
`0x104844e10` and `0x105eca510`; one retains the result, constructs a filename
and passes its bytes to `mkstemp`.

Vinix selects `tmp/` below the same container parent used by `NSHomeDirectory`
and Documents. It normalizes repeated separators, provisions missing
directories through the existing file-manager implementation and returns a
copied autoreleased NSString. It ignores the host's `TMPDIR`. The bounded
POSIX profile permits 1023 bytes including the trailing separator and rejects
relative paths, dot components, embedded NUL and invalid UTF-8. Directory
creation failures release the result before returning an explicit error.

Eight normal/deterministic host sanitizer runs and four ARM64 guest suites
pass: temporary directory, home directory, file manager and autorelease pools.
Coverage includes guarded C registers and borrowed path prefixes, Unicode,
spaces, roots, redundant/trailing separators, the complete 1023-byte path,
actual file writes, missing-parent creation, non-directory failure cleanup,
strings retained across pool drains, eight concurrent readers and two drained
runtime lifetimes. The eleven final generated C streams and executables,
native comparisons, actual IPA consumers, pinned inputs and retired VM phases
are retained under `build/ios/fortnite/temp-directory-checks`. The initial Mac
boundary failure caused by `/tmp` expanding to `/private/tmp`, the corrected
fixture and the initial guest trial are retained separately. Generated C
inspection checks bounded stack paths and explicit string/failure cleanup.
Published runners remain unchanged; the full iOS regression remains unpassed.

The temporary-directory IPA probe links past that import and exits with
status 1 at `_NSURLErrorBackgroundTaskCancelledReasonKey`.

V now supplies seven Foundation URL-error string globals: `NSURLErrorDomain`,
the failing URL, URL-string and peer-trust keys, the deprecated URL-string
alias, and the background-cancellation and network-unavailable reason keys.
Native measurements verify pointer-sized data cells, exact NSString values
and 32-byte ASCII constant-string records with flags `0x7c8`. In particular,
`NSURLErrorFailingURLErrorKey` contains `NSErrorFailingURLKey`; the two
URL-string names have distinct cells pointing to the same object containing
`NSErrorFailingURLStringKey`.

The runtime publishes cells, six immutable string records and copied bytes on
one sealed page under its recursive lock. Repeated queries allocate no storage.
These strings remain immortal through pool, constant-dictionary and Swift
context teardown; shutdown removes their registrations and unmaps the page
after those owners drain. The background-reason consumer at `0x100801df8` and
domain consumers including `0x100052cf4` load the exported cell and then its
NSString pointer, confirming the required indirection in the actual IPA.

Eight normal/deterministic host sanitizer runs and four ARM64 guest suites
pass: URL-error globals, JSON/NSError, immutable constant dictionaries and
autorelease pools. Coverage includes concurrent first publication by eight
readers, stable cells and alias identities, balanced ownership across pool
drains, NSError domain/userInfo lookup by equal strings, pool-destructor access
after task entry points retire, and two drained/unmapped lifetimes. Two extra
Swift heap sanitizer comparisons pass for the common shutdown ordering. The
eleven main generated C streams and executables, extra Swift heap artifacts,
native records, actual IPA consumers, pinned inputs and retired VM phases are
retained under `build/ios/fortnite/url-error-checks`. The initial sanitizer
failure from marking ordinary NSString storage as a constant record is retained
with its original source and binaries; the corrected page uses the measured
record layout. Generated C inspection checks allocation-free cached lookup and
retirement after pool, dictionary and Swift cleanup. Published runners remain
unchanged; the full iOS regression remains unpassed.

The URL-error IPA probe links past those globals and exits with status 1 at
`_NSURLSessionDownloadTaskResumeData`.

V now supplies Foundation's three `NSURLSessionTaskPriority` globals,
`NSURLSessionTransferSizeUnknown`, and the download/upload resume-data keys.
Native Foundation measurements verify 32-bit floats of 0.5, 0.25 and 0.75 for
default, low and high priority, a signed 64-bit -1 transfer-size sentinel, and
pointer-sized NSString cells containing the exact exported resume-data names.
These exports provide data addresses with the measured widths and indirection.
They do not implement NSURLSession tasks or networking.

The runtime publishes the scalars, pointer cells, two immutable ASCII string
records and copied bytes on one sealed page under its recursive lock. Cached
lookups allocate no storage. Shutdown removes the string registrations and
unmaps the page after pools, dictionaries and Swift contexts drain. Fortnite's
download-key consumer at `0x100801fa0`, priority consumers including
`0x1007ff15c` and `0x10836386c`, and transfer-size consumer at `0x100800b74`
confirm pointer, float32 and 64-bit loads from the exported data.

Eight normal/deterministic host sanitizer runs and four ARM64 guest suites
pass: session constants, URL-error globals, immutable constant dictionaries
and autorelease pools. Coverage includes exact scalar bits, concurrent first
publication by eight readers, stable cells, NSError resume-data bytes retained
across pool drains, lookup by equal NSString keys, pool-destructor access after
task entry points retire, and two drained/unmapped lifetimes. The eleven
generated C streams and executables, native measurements, all five required
IPA data consumers, pinned inputs and retired VM phases are retained under
`build/ios/fortnite/session-constants-checks`. Generated C inspection checks
allocation-free cached lookup and explicit storage retirement. Published
runners remain unchanged; the full iOS regression remains unpassed.

The session-constants IPA probe links past those five required globals and
exits with status 1 at `_NSUbiquityIdentityDidChangeNotification`.

V now supplies Foundation's `NSUbiquityIdentityDidChangeNotification`,
`NSUnderlyingErrorKey` and `NSUserActivityTypeBrowsingWeb` string globals.
Native measurements verify eight-byte pointer cells and immutable ASCII
NSString records. The underlying-error key's value is `NSUnderlyingError`;
the other two values match their exported names. The runtime publishes the
cells, records and copied bytes on one sealed page under its recursive lock.
Cached queries allocate no storage. Shutdown retires the strings after
notification registrations, pools, constant dictionaries and Swift contexts.
The exports supply identifiers; iCloud identity monitoring and NSUserActivity
behavior still require implementation.

Eight normal/deterministic host sanitizer runs and four ARM64 guest suites
pass: Foundation keys, URL-error globals, immutable constant dictionaries and
autorelease pools. Native comparisons cover nested NSError ownership,
notification delivery through equal NSString names, object filters and observer
removal, retained notification/userInfo lifetimes, dictionary lookup through
the browsing-web identifier, eight concurrent first readers and two drained
runtime lifetimes. Teardown also removes a zeroing-weak observer registration
while its name remains available to destructors.

Fortnite's consumers at `0x102156568`, `0x10001031c` and `0x100020760`
load the exported pointer cells and then their NSString objects. The eleven
final generated C streams and executables, native measurements, actual IPA
consumers, pinned inputs and retired VM phases are retained under
`build/ios/fortnite/foundation-keys-checks`. Generated C inspection checks
allocation-free cached lookup and explicit retirement after the owners drain.
Published runners remain unchanged; the full iOS regression remains unpassed.

The Foundation-key IPA probe links past those three globals and exits with
status 1 at AudioToolbox's `_AudioServicesPlaySystemSound`.

V now supplies the AudioToolbox system-sound entry for devices without
vibration hardware, plus `CAShow` and `CAShowFile` for live private AUGraphs.
Fortnite's only system-sound consumer loads the 32-bit vibration ID 4095 at
`0x10080ded0` and tail-calls the import at `0x10080dee8`. The installed SDK
specifies that this ID does nothing on devices without vibration capability;
the current Vinix runtime has no actuator backend. Other sound IDs fail
explicitly. System-sound registration and audible playback remain unsupported.

The diagnostic consumer at `0x105ea98bc` reads the graph handle from its audio
object's field at offset 1416. The `NewAUGraph` call at `0x105ea99ac` writes
that field. The implementation looks up registry-owned graphs under their
mutation/disposal lock and writes bounded stack buffers containing node IDs,
component FourCCs, unit handles, connections and initialization/running flags.
`CAShow` writes to stderr; native macOS uses os_log. `CAShowFile` translates
Darwin FILE handles to native streams. Foreign/stale graphs, invalid streams
and output failures are rejected. Other AudioToolbox object kinds still need
individual diagnostic implementations.

Eight normal/deterministic host sanitizer runs and four ARM64 guest suites
pass: AudioToolbox services, Foundation keys, URL-error globals and autorelease
pools. Native comparisons cover the uint32/void vibration ABI, protected unused
arguments and result-context register, preserved registers, eight concurrent
callers, graph diagnostics through open/initialize/start/stop/uninitialize and
concurrent FILE snapshots. Private cases also cover graph connections,
non-mutating dumps, protected foreign/stale handles, Darwin stream translation,
write failure, explicit unsupported-call rejection and two drained runtimes.

The eleven final generated C streams and executables, native measurements,
actual IPA consumers, pinned inputs and retired VM phases are retained under
`build/ios/fortnite/audio-services-checks`. Generated C inspection checks for
hidden V allocations in dispatch/serialization, plus registry locking and
stream translation. Published runners remain unchanged; the full iOS regression
remains unpassed.

The AudioToolbox IPA probe links past both required imports and exits
with status 1 at AVFoundation's `_AVCaptureDeviceTypeBuiltInTelephotoCamera`.

V now supplies the seventeen missing AVFoundation NSString globals used by the
IPA: five capture-device types, five capture-session notification names, the
high-quality capture preset, five media types and the player-item end notification.
The existing medium preset, aspect-fill gravity and video media type use the same
storage. All twenty values were measured through the installed AVFoundation
library and checked against its SDK declarations. Media types contain `soun`,
`clcp`, `sbtl`, `text`, `tmcd` and `vide`, rather than their export names.

These exports address aligned NSString pointer cells in one read-only page,
alongside immortal CFSTR records and their UTF-8 bytes. First publication uses
the runtime lock. Notification, collection, autorelease and Swift owners retire
before the page is unmapped; shutdown callbacks can still read published globals.
Exports are scoped to AVFoundation. This implements constant data; capture-device
discovery, camera capture and player classes still need their own implementations.

Eight normal/deterministic host sanitizer runs and four ARM64 guest suites pass:
AVFoundation constants, Foundation keys, URL-error globals and autorelease pools.
Native comparisons cover exact values, immutable copies, retained arrays and
dictionaries, equal-name delivery/filtering/removal for all six notifications,
eight concurrent readers and two drained runtime lifetimes. The actual IPA
consumer at `0x10a652048` loads the telephoto pointer cell, dereferences it at
`0x10a652050`, and adds it to the device-type collection before discovery.
The eleven final generated C streams/executables, native measurements, pinned
inputs, source inspection and retired VM evidence are retained under
`build/ios/fortnite/avfoundation-constants-checks`. Published runners remain
unchanged; the full iOS regression remains unpassed.

The AVFoundation IPA probe links past that group and exits with status 1 at
CoreVideo's `_CVMetalTextureCacheCreate`.

V now implements CPU CVPixelBuffer storage for caller-supplied packed BGRA and
two-plane 420v/420f YUV. Creation copies the plane descriptions. Final CF/ObjC
release invokes the supplied storage-release callback exactly once. Buffers
without a callback keep caller-owned bytes untouched.
Geometry, pixel format, base-address/row-stride/data-size and plane accessors use
that state. Lock/unlock make these permanently mapped CPU bytes accessible;
they are cache-access operations, not mutual-exclusion locks. GPU coherence and
other pixel formats remain unsupported. Borrowed-storage
constructors accept nil or empty attributes. Foreign or stale handles fail before
object memory is read.

Seventeen sealed CoreVideo CFString pointer globals cover pixel-buffer hints and
color primaries, transfer functions, gamma and YCbCr matrix metadata. Their values
and shared 709/240M string identities match the installed native library. The
existing pixel-format key now uses this storage and CoreVideo export scope.
The globals remain available through owner/pool/Swift teardown before unmapping.

Eight normal/deterministic host sanitizer runs and four ARM64 guest suites pass:
CoreVideo, Foundation keys, URL-error globals and autorelease pools. Native cases
cover packed, disjoint-planar and contiguous-planar storage; short caller strides;
packed plane-zero geometry; copied plane arrays; storage mutation; final-release
callbacks; CF ownership; concurrent readers; and metadata aliases/collections.
Private cases also exercise protected foreign/stale handles and two drained
runtime lifetimes. Five actual IPA width-query callers were inspected, including
`0x10a651498`, after `CMSampleBufferGetImageBuffer` and before Metal texture import.
The eleven final generated C streams/executables, native measurements, pinned
inputs and retired VM evidence are retained under `build/ios/fortnite/corevideo-checks`.
Generated C inspection checks state ownership, allocation-free queries and late
constant retirement. Published runners remain unchanged; the full iOS regression
remains unpassed.

`CVPixelBufferCreate` now allocates owned CPU storage for BGRA and two-plane
420v/420f. It accepts positive signed integers for row and plane alignment,
including non-power-of-two alignments, and rounds odd chroma dimensions upward.
Row strides meet both the requested alignment and the CPU profile's 64-byte minimum. The
contiguous YUV layout includes big-endian plane descriptors; clients use the
plane accessors rather than assuming Apple's device-specific padding. Checked
arithmetic bounds buffers to 2 GiB minus one byte. Final CF/ObjC release frees
the allocation. Invalid dimensions leave the output unchanged; format and later
failures clear it. Plane-alignment and IOSurface-properties keys join the sealed
metadata globals, bringing their count to nineteen.

The CPU allocation profile rejects unknown attributes and alignment values outside
that integer profile. OpenGLES compatibility requests remain unsupported. False
compatibility hints allow ordinary CPU allocation. Metal and IOSurface requests
now use the separate shared-storage profile described below.

Eight normal/deterministic host sanitizer runs and four ARM64 guest suites cover
owned allocation, borrowed CoreVideo buffers, URL-error globals and autorelease
pools. Native comparisons exercise odd dimensions, row/plane alignment, full-row
writes/readback, plane descriptors, CF ownership, eight concurrent readers and
error output semantics. Private cases cover overflow, unsupported attributes,
256 allocation/release cycles, ASan backing-storage retirement and two drained
runtimes. Eleven final generated C streams/executables and joined VM evidence are
retained under `build/ios/fortnite/pixel-allocation-checks`.

V/Mach-O/LLVM inspection found three actual texture-cache creation callers. At
`0x10a64d6c8`, the game passes a device returned through its renderer interface,
then imports BGRA storage as Metal pixel format 81 at `0x10a64d71c`. Owned CPU
allocation supplied the initial storage groundwork for this path.

The borrowed-buffer APIs and original metadata group resolved twenty-seven
required imports. CoreVideo's three required Metal texture-cache imports now also
resolve. `CVMetalTextureCacheCreate` retains a supplied device implementing
`newTextureWithDescriptor:iosurface:plane:`. Image import builds a 2D descriptor
inheriting `MTLTextureDescriptor`, calls that device, and owns its returned texture
together with the source pixel buffer. Failed device imports return an error and
release the temporary descriptor. Views remain valid after cache flush/release;
the cache retains no idle views. Shared storage mode, usage attributes,
nonnegative maximum-age
attributes, type IDs, orientation and clean texture coordinates are supported.
The three associated CFString keys bring the sealed CoreVideo globals to twenty-two.

Metal compatibility or an empty IOSurface-properties dictionary now requests
shared anonymous storage. A separate IOSurface object owns the mapping; pixel
buffers and imported textures can retain it independently. Local surface geometry,
plane, base-address, allocation-size and pixel-format accessors describe the
actual portable layout. Final surface release unmaps the storage. Mach-port
export, global surface IDs and device-specific allocations remain unsupported.
OpenGLES-compatible allocation and nonempty surface properties still fail
explicitly. BGRA maps to Metal formats 80/81, and 420v/420f planes map to formats
10/30. Native measurements additionally establish that packed plane indices
other than zero fail, despite the older header's wording; the output is preserved.
Missing image/cache/output arguments likewise fail before publishing a handle.
CPU-only image import clears the output and returns the native generic error.

Eight final host sanitizer runs and four ARM64 guest suites cover cache/device
delegation, owned pixel allocation, borrowed CoreVideo buffers and autorelease
pools. The Mac comparisons use its actual Metal device for surface allocation,
texture read/write aliasing, plane geometry, orientation, CF ownership and
concurrent readers. The V test device implements surface texture creation and
row transfers, exercising the same Objective-C and aggregate-argument ABI. Guest
checks cover independent device/cache/view/texture/surface lifetimes, failed
imports, format/size validation, shared writes across fork and two drained
runtimes. Host Mach VM queries verify final unmapping. Native driver mappings
are not inherited across fork; that test applies only to the portable profile.
Eleven final generated C streams/executables, native measurements, actual IPA
consumers and joined VM evidence are retained under
`build/ios/fortnite/metal-cache-checks`.

This implements the CoreVideo/device boundary. Its IPA probe linked past the
three Metal-cache imports, then stopped before application entry at CoreMedia's
`_CMAudioFormatDescriptionGetStreamBasicDescription`.

CoreMedia format descriptions now own independent format metadata. Generic,
audio and video constructors produce retainable CF objects with stable type IDs,
media type/subtype queries, borrowed extension queries, audio ASBD pointers and
video dimension queries. ASBD input bytes are copied, including reserved fields;
the pointer stays valid while its description is retained. Equality ignores the
reserved ASBD field, matching native behavior. Generic audio descriptions expose
a zeroed ASBD. Video descriptions
preserve signed dimensions, including zero and negative values; creation alone
does not validate a codec's decodability or usable image dimensions.

Extension dictionaries are deep, immutable property-list snapshots. Nested
dictionaries, arrays, strings, data and dates are copied; immutable numbers and
booleans are retained. Input mutation or release cannot change the snapshot.
Callers can retain the returned dictionary independently of its description.
Snapshots are bounded to 64 levels and 65,536 values; invalid types, raw CF
callbacks and excessive nesting fail with partial copies released. Audio
construction requires a nonzero sample rate and nil channel-layout/magic-cookie
arguments in this profile. Other layouts and cookies return a value-unavailable
error. A zero generic media type preserves the output; audio construction
clears it before validation. Format metadata does not create codecs.

Seven sealed CoreMedia CFString cells provide full-range video, sample-description
atoms and the required HLG, Linear, PQ, ST 428-1 and sRGB transfer-function values.
The sRGB value is the native `IEC_sRGB` string. These globals are scoped to
CoreMedia and retired after autorelease teardown.

Eight final host sanitizer runs and four ARM64 guest suites cover format
descriptions, CoreVideo texture imports, borrowed pixel buffers and autorelease
pools. Native comparisons verify copied ASBDs, signed dimensions, nested extension
mutation, CF equality and ownership, concurrent readers and exact metadata
strings. V checks additionally cover unsupported inputs, failed snapshot cleanup,
concurrent global initialization and two fully drained runtimes. Actual IPA call
sites obtain the audio description through `CMSampleBufferGetFormatDescription`
before reading the ASBD and block-buffer data. Eleven final generated C streams
and executables, native measurements and joined guest evidence are retained under
`build/ios/fortnite/media-format-checks`.

These changes resolved thirteen more required imports. That IPA probe exited
with status 1 before application entry at
`_CMBlockBufferCreateWithMemoryBlock`.

CoreMedia block buffers now provide contiguous owned or borrowed memory,
deferred allocation, retained buffer references, data pointers and lengths,
copy/replace/fill operations, contiguity/empty queries and CF type IDs. Default
allocation owns and frees the supplied or allocated block; `kCFAllocatorNull`
borrows supplied storage. Custom sources copy the packed 28-byte callback
record, reading its unaligned pointers byte by byte. Their release callback
runs once at final release, with the original base address and block size.
Unused deferred blocks allocate and free no memory.

Pointer and copy queries leave deferred storage unallocated and return the
native value-unavailable error. Assure, replace and fill allocate it on demand;
failed allocation can be retried. Out-of-range requests fail before allocation.
Pointer failures clear the pointer/available outputs while reporting the known
total length; a nil buffer leaves outputs untouched. Zero-length replacement
and copy fail, while zero-length fill or buffer reference uses the remaining
range. Nested references retain their root storage and share writes after the
source handles are released. Allocation callbacks run outside the runtime lock,
can join readers on another thread, and receive an explicit error if they try
to allocate the same block recursively.

This profile accepts nonempty contiguous blocks up to 2,147,483,647 bytes,
default structure allocation and default, null or version-zero custom block
allocation. Other CF allocators, empty/fragmented assembly and contiguous-copy
construction remain unavailable. Callers retain buffers while using their
borrowed pointers; allocation and mutation require caller synchronization.
The actual IPA's helper at `0x101fc6374` requests immediate default allocation,
with its ninth output-pointer argument on the stack.

Eight final host sanitizer runs and four ARM64 guest suites cover block buffers,
format descriptions, borrowed CoreVideo buffers and autorelease pools. Native
comparisons verify packed callbacks, eager/deferred allocation, allocation
failure/retry, range and output errors, shared slice writes, CF ownership and
concurrent readers. Private cases also check callback reentrancy and two fully
drained runtimes. Generated C audits verify explicit state allocation/free and
root ownership; eleven final C streams and executables are retained under
`build/ios/fortnite/block-buffer-checks` with the native measurements and IPA
consumer inspection.

Four more required imports resolved. That IPA probe exited with status 1 before
application entry at `_CMSampleBufferCreate`.

CoreMedia sample buffers now carry block data and format descriptions, copied
timing/size arrays, sample counts, duration/timestamp queries and CF ownership.
Creation retains the data and format independently of the caller. The arrays
use the SDK's four-byte alignment: records are copied as bytes before reading
64-bit values. One timing or size entry can describe every sample; per-sample
arrays preserve their individual entries. A buffer without timing has zero
duration and invalid timestamps. Data can be attached later through its
write-once setter. Borrowed data and format getters can be retained separately.
Image-buffer queries return nil for these block-backed samples; image sample
construction remains unavailable.

Readiness and validity are separate. A ready buffer skips its callback; an
unready buffer can invoke a supplied callback, preserve its exact error code and
retry later. Callbacks run without the registry lock and can join another
reader, mark data ready or invalidate the sample. Recursive readiness on the
same sample fails explicitly. Invalidation immediately hides all metadata and
disables readiness, while retaining the backing owners until final release,
matching native retain-count measurements. Repeated invalidation returns the
native invalidated error. Final release frees both metadata arrays and releases
the data and format owners, including after invalidation.

The bounded profile accepts 0..65,536 samples and at most 2,147,483,647 total
sample bytes, with zero, one or one-per-sample timing/size entries. Numeric
timescales must be positive; repeated timestamps and duration sums use compatible
timescales and checked signed 64-bit arithmetic. Canonical invalid, infinity and
indefinite durations are supported for a single timing entry. Mixed-scale
arithmetic and unsupported epoch combinations fail explicitly. Callers keep
sample buffers alive during queries/callbacks and synchronize mutations.
The inspected IPA helper at `0x101fc6348` creates one ready sample with one
timing record and no size array; the final four arguments use the stack.

Eight final host sanitizer runs and four ARM64 guest suites cover sample buffers,
block buffers, format descriptions and autorelease pools. Native comparisons
exercise copied/unaligned metadata, aggregate time returns, indexed timing,
retained-owner destruction orders, write-once data association, readiness
callbacks, invalidation and concurrent readers. Private cases reject arithmetic
overflow, unsupported time profiles, missing arrays and foreign/stale handles,
and drain two complete runtime lifetimes. The native missing-array probe raised
a memory fault; Vinix rejects that input before copying. Eleven final generated
C streams and executables, native measurements, IPA consumer inspection and
joined guest evidence are retained under
`build/ios/fortnite/sample-buffer-checks`.

Eight more required imports resolved. That IPA probe exited with status 1 before
application entry at `_CMTimeGetSeconds`.

CoreMedia time values now support `CMTimeMake`, `CMTimeMakeWithEpoch`,
`CMTimeMakeWithSeconds` and `CMTimeGetSeconds`. The 24-byte value uses the iOS
ARM64 indirect argument/result convention and composes with sample-buffer timing.
Integer constructors preserve signed 64-bit values and epochs, and clear every
field for nonpositive timescales. Seconds queries ignore the epoch, honor invalid
and indefinite flags before infinity flags, and divide numeric values in double
precision.

The seconds constructor follows measurements of this Mac's CoreMedia library:
fractional ticks truncate toward zero, including half ticks; conversion back to
seconds controls the rounded flag. Overflow repeatedly halves the preferred
timescale, then produces signed infinity if scale one still overflows. The exact
double-precision boundary at either sign of 2^63 clamps symmetrically to
plus/minus `INT64_MAX`. NaN produces a rounded zero at the requested positive
scale. These conversions allocate no objects or backing storage. General time
arithmetic, scale conversion and mixed-scale sample arithmetic remain unavailable.

The IPA consumer at `0x10a64b418` passes the sample query's stack result directly
to `CMTimeGetSeconds` before scaling its floating-point result. Native comparisons
cover constructors, epochs, flag precedence, invalid scales, rounding, subnormals,
overflow and sample-duration composition, plus 4,096 deterministic bit patterns.
Eight final host sanitizer runs and four ARM64 guest suites cover time values,
sample buffers, block buffers and autorelease pools. Eleven final generated C
streams and executables are retained with native measurements, generated-function
audits and joined guest evidence under `build/ios/fortnite/cm-time-checks`.

Three more required imports resolved. That IPA probe stopped before application
entry at `_CMVideoFormatDescriptionCreateFromH264ParameterSets`.

H.264 parameter-set descriptions now own an immutable `avcC` decoder configuration
record and metadata derived from the SPS. Creation accepts raw SPS/PPS NAL units,
removes emulation-prevention bytes while reading bits, and derives cropped
dimensions, progressive/interlaced fields, pixel aspect ratio, chroma location,
range and supported color tags. The configuration record preserves duplicate
sets, groups SPS records before PPS records and supports one-, two- and four-byte
sample length prefixes. Caller buffers can be discarded immediately after a
successful constructor. Constructor failures leave the output handle untouched.

Parameter queries borrow bytes from the description's owned `avcC` atom, including
an equivalent atom supplied through the generic format constructor. Count/header
queries ignore the index when no parameter bytes or size are requested. Out-of-range
parameter queries clear the requested pointer/size while still returning the
record count and length-header size. Sample buffers retain the format independently;
retaining the atom's CFData also preserves its bytes after the format is released.
Getters and RBSP readers allocate no storage.

This bounded profile accepts 2..64 SPS/PPS records, at most 65,535 bytes per NAL
and a one-MiB aggregate NAL budget. Supported SPS profiles are Baseline, Main,
Extended and eight-bit 4:2:0 High, with compatible metadata across multiple SPS
records. Color values support unspecified or BT.709 primaries/transfer/matrix;
other profiles, chroma/bit-depth/color combinations and SPS-extension NAL units
remain outside this profile. The installed libx264/libavcodec libraries generated
eleven native fixtures through V tooling. CoreMedia comparisons verify the full
metadata dictionaries and exact configuration bytes, including an explicit 1:1
pixel-aspect tag, extended aspect ratios, centered chroma and full-range video
without color tags. The inspected IPA consumer at `0x1078cab10` supplies the sixth
constructor argument, its output pointer, in `x5`.

Eight final host sanitizer runs and four ARM64 guest suites cover H.264 formats,
generic formats, sample-buffer ownership and autorelease pools. The earlier two
host runs and their seven-fixture sources are also retained. Eleven final C
streams and executables, native encoder/CoreMedia measurements, generated-code
audits and joined guest evidence are retained under
`build/ios/fortnite/h264-format-checks`.

One more required import resolved. That IPA probe stopped before application
entry at `_CMVideoFormatDescriptionCreateFromHEVCParameterSets`.

HEVC parameter-set descriptions now own an immutable `hvcC` record and derive
dimensions, bit depth, pixel aspect, chroma location, range and supported color
tags from the SPS. Identical input sets collapse into one record, with VPS/SPS/PPS
grouped in that order. Length prefixes support one, two or four bytes. Caller
extensions are deep property-list snapshots and override derived tags; caller
buffers and extension dictionaries can be discarded after construction. Sample
buffers and retained atom data preserve their owners independently. Parameter
queries borrow bytes from the owned record, also supporting generic `hvc1`/`hev1`
descriptions. Parsers and getters allocate no storage.

The bounded profile accepts 2..64 input records, one distinct VPS/SPS/PPS each
plus identical duplicates, at most 65,535 bytes per NAL and a one-MiB record
budget. VPS/SPS are required; PPS is optional, matching the measured native
constructor. Supported streams are progressive single-layer Main/Main10, 4:2:0,
eight or ten bits, with matching VPS/SPS profile information. Color tags support
unspecified or BT.709 values. SEI, distinct replacement sets, other profiles,
display windows, HRD, spatial segmentation, SPS extensions and caller-supplied
sample-description atoms remain outside this profile and fail explicitly.

V tooling used the installed libx265/libavcodec and CoreMedia libraries for
twelve fixture configurations and native metadata/error measurements. Checks
compare full dictionaries and exact `hvcC` bytes, including cropped dimensions,
Main10, square/extended aspect, centered chroma and range without color tags.
They cover truncated NALs, malformed atoms, unaligned pointers, raw dictionaries,
extension mutation, concurrent readers and sample/data destruction order. Eight
final host sanitizer runs, two retained earlier runs and four final ARM64 guest
suites cover HEVC, H.264, sample buffers and autorelease pools. Eleven final C
streams/executables and joined guest evidence are retained under
`build/ios/fortnite/hevc-format-checks`. The IPA consumer at `0x1078cab24` passes
nil extensions in `x5` and its seventh argument, the output pointer, in `x6`.

One more required import resolved. That IPA probe stopped before application
entry at `_CGFontCopyTableForTag`.

CoreGraphics fonts now own a validated copy of TrueType SFNT bytes, including
indexed faces in TrueType collections. Table queries return owned CFData copies;
table-tag arrays preserve directory order and contain raw FourCC integers,
matching the native API. Fonts retain their data provider until the final font
release. Returned arrays and table data survive independently, including after
the caller discards the input bytes. Glyph counts, units per em, PostScript names
and full names come from the font's tables. Font construction failures release
partial storage; byte readers and metadata getters allocate no storage.

This bounded profile accepts at most 16 MiB, 4,096 distinct tables and 64
collection faces, with TrueType `glyf`/`loca` outlines and validated table spans.
It supports format-zero name tables with Unicode records and the ASCII subset
of Mac Roman. CFF/OpenType `OTTO`, WOFF and CGFont glyph rasterization remain
outside this profile. With the optional `ios_text` backend,
`CGFontCreateWithFontName` searches existing process-registered font descriptors
by PostScript or full name and snapshots the matching file. Unregistered names
return nil; the static runner still lacks this name-lookup import.

V tooling used the installed HarfBuzz subsetter to produce a 1,996-byte fixture
from the existing OFL-licensed `VinixJapanese-Regular.ttf`. Native CoreGraphics
measurements cover directory order, exact table bytes, collections, nil and
empty tables, names, metrics and provider callback timing. Native table CFData
views alias the provider's input, so comparisons keep that input alive and
immutable until the views are released. Vinix's copies are separately checked
after input mutation and font destruction. Eight final host sanitizer runs and
four ARM64 guest suites also cover registered lookup, concurrent retained readers,
malformed directories and complete runtime teardown. Eleven final C streams and
executables, native measurements and joined guest evidence are retained under
`build/ios/fortnite/cg-font-checks`. The inspected IPA consumer calls
`CGFontCopyTableForTag` at `0x104844970` and `0x104844ac0`, passing the raw values
from `CFArrayGetValueAtIndex` as tags while serializing SFNT tables.

Three more required imports resolved in the text runner, and two in the static
runner. That IPA probe stopped before application entry at
`_SCNetworkReachabilityCreateWithAddress` from SystemConfiguration.

SystemConfiguration reachability targets now snapshot IPv4/IPv6 socket addresses
and names. Flags come from real routes and interface addresses: default targets
read the route table, and nonzero addresses use a UDP route lookup without sending
application data. Local and directly connected flags use the interface snapshot.
Queries distinguish an unreachable destination from an unavailable query, and
leave the caller's flags untouched on failure. The Mac implementation reads BSD
route dumps; Vinix uses bounded rtnetlink dumps with a one-second receive budget.
Every temporary socket, interface list and native route buffer is released.

Address monitoring polls at 100 ms between scans and delivers observed changes
on the requested dispatch queue, including main-queue delivery for the existing
main run loop's default or common mode. An unchanged target produces no synthetic
initial callback. Pending changes coalesce, and unscheduling invalidates queued
notifications. Scheduling owns the target and queue until cancellation. Callback
contexts have independent ownership, so replacement during a running callback
cannot destroy its info prematurely. Framework dispatch work now cleans up its
context both after execution and when shutdown cancels it. The watcher joins
before dispatch workers stop and object metadata is released.

The bounded profile supports 64 simultaneous monitors and names up to 1,024
bytes. Numeric names and `localhost` use address monitoring. Other unscheduled
names use the optimistic default-route result without DNS traffic; scheduling
generic DNS names, secondary run loops and additional run-loop registrations
remains unsupported and returns failure. Cellular, dial-on-demand, NAT64/DNS64
and policy-routing semantics remain outside this profile. Route changes shorter
than a scan can be missed; reachability does not establish server availability.

V tooling measured the installed SystemConfiguration library's address-length
validation, loopback/default flags, context replacement and scheduled ownership.
Ten final host sanitizer runs cover reachability, dispatch scheduling, fonts,
sample buffers and autorelease pools. Four ARM64 suites also cover cancellation,
reentrant context replacement, background queue delivery, run-loop modes and
drained runtimes. Twelve final C streams and executables, native measurements,
generated-code audits and joined guest evidence are retained under
`build/ios/fortnite/reachability-checks`. The IPA consumer at `0x10009bea8` creates
an IPv4 default-route target before assigning its dispatch queue and callback.

Those seven required imports resolved; that probe stopped before application
entry at `_DCErrorDomain` from DeviceCheck.

DeviceCheck now exports that NSString pointer cell with the Mac library's measured
value, `com.apple.devicecheck.error`. One page holds the cell, CFSTR record and
terminated bytes. Publication is serialized and seals the page read-only; later
lookups reuse it. The string stays registered as immortal until autorelease pools
and Swift contexts have drained, then its registration and page retire. New
publication is rejected once runtime retirement begins. The IPA consumer at
`0x1022e3938` loads the cell and dereferences its string at `0x1022e3940`, before
comparing an NSError domain and checking error code 3. This implements the error
domain global; DeviceCheck token services and App Attest remain unavailable.

Eight host sanitizer runs cover this global, Foundation keys, reachability and
autorelease pools, with normal and deterministic Swift hashing. Four ARM64 Vinix
suites also check concurrent first lookup, exact string equality, NSError lifetime
across pools, pool-destructor access during shutdown and two drained runtimes.
Eleven final C streams and executables, native measurements, generated-code audits
and joined guest evidence are retained under
`build/ios/fortnite/devicecheck-checks`.

That required import resolved; the following probe stopped before application
entry at `_nw_interface_get_name` from Network.framework.

Network.framework now provides the path-monitor and snapshot APIs imported by the
IPA. Initial delivery and later changes run on the requested dispatch queue,
including the existing main run loop. Snapshots retain immutable interface names,
indices and types; callers can retain a path or interface beyond monitor
cancellation. Enumeration is synchronous, borrows its block, and stops when the
block returns false. Monitor handlers are copied, replacements release their old
capture, and running callbacks keep their handler and path alive. Pending updates
coalesce; unchanged snapshots produce no callback or replacement allocation.
Cancellation invalidates queued deliveries and releases the monitor's owners.
Shutdown joins the polling worker before stopping dispatch, drains queued work,
and rejects new monitors through the remaining pool and capture destruction.

The Vinix backend reads bounded rtnetlink dumps of main-table unicast default
routes and live interface addresses. IPv6 requires a non-link-local address and
matching default route. DNS support means a configured numeric nameserver in
`/etc/resolv.conf`; the query sends no DNS or application traffic. Interface types
come from native link data and wireless ioctls. The Mac test backend uses BSD route
dumps and its SystemConfiguration BSD-name mapping to distinguish Wi-Fi from
Ethernet. Temporary route buffers, sockets, native interface lists and Mac
configuration arrays are released. Failed queries preserve the preceding
snapshot, with initial delivery waiting for a successful query.

This profile supports 64 active monitors and 64 unique default-route interfaces,
with 100 ms between scans and a one-second netlink receive budget. Changes shorter
than a scan can be missed. It does not model NECP or other policy routing,
multipath nexthops, cellular cost policy,
NAT64/DNS64 or Low Data Mode. Vinix has no constrained-data policy, so the
constrained query returns false; these flags do not establish server availability.

The installed Mac library was measured for initial delivery, block replacement,
retained snapshots and interfaces, enumeration early exit and cancellation.
Eight final host sanitizer runs and four ARM64 Vinix suites also exercise
coalescing, concurrent readers, cancellation before delivery, replacement during
a running callback, shutdown with queued work and two drained runtimes. Eleven
final C streams and executables, native measurements, generated-code audits and
joined guest evidence are retained under `build/ios/fortnite/network-path-checks`.
The actual IPA callback invokes `_nw_interface_get_name` at `0x1005ada54`.
The native test driver also bounds QEMU shutdown: if its owned child ignores
SIGTERM, it sends SIGKILL after two seconds and reaps it before removing payloads.

Those fifteen required imports resolved; the following probe stopped before
application entry at `_CHHapticDynamicParameterIDHapticIntensityControl`.

CoreHaptics now exports the five NSString pointer cells imported by the IPA:
`CHHapticDynamicParameterIDHapticIntensityControl`,
`CHHapticDynamicParameterIDHapticSharpnessControl`,
`CHHapticEventParameterIDHapticIntensity`,
`CHHapticEventParameterIDHapticSharpness` and `CHHapticEventTypeHapticContinuous`.
Their measured values are `HapticIntensityControl`, `HapticSharpnessControl`,
`HapticIntensity`, `HapticSharpness` and `HapticContinuous`. One sealed read-only
page holds stable cells, immortal CFSTR records and UTF-8 bytes. Publication is
serialized; retirement waits for collection, pool-destructor and Swift-context
owners to drain before unregistering the strings and unmapping the page. Exports
are scoped to CoreHaptics. Haptic parameter objects, engine playback and device
output remain unavailable.

The installed Mac library and V runtime pass the same concurrent-reader,
retain/release, autorelease, string-equality and retained-dictionary checks.
Eight host sanitizer runs and four ARM64 Vinix suites additionally cover two
runtime lifetimes, pool-destructor availability, DeviceCheck, Network path
monitoring and autorelease pools. Eleven generated C streams and executables,
native measurements and joined guest evidence are retained under
`build/ios/fortnite/corehaptics-constants-checks`. The actual IPA dereferences the
intensity-control cell at `0x100804008`.

Those five required imports resolved; the following probe stopped before
application entry at `_CACurrentMediaTime`.

QuartzCore now exports `CACurrentMediaTime` with its native double return ABI.
It converts the runner's nanosecond Mach clock to seconds, without creating
Objective-C state or allocating a cache. On the Mac host, the Mach shim now reads
absolute raw uptime instead of V's process-relative monotonic clock. Mach and
media time therefore share the same uptime origin, including across runtime
initialization and shutdown. The Vinix backend continues to use its existing
monotonic nanosecond clock and 1/1 Mach timebase.

Native measurements bracket media time with Mach ticks and the installed timebase.
The same eight-thread checks compare the V function's units, finite double
results, monotonic progression and elapsed sleep; the Mac also compares absolute
values directly against QuartzCore. Eight host sanitizer runs and four ARM64
Vinix suites cover dispatch deadlines, calls before/after two drained runtimes,
CoreHaptics constants, Network paths and autorelease pools. Eleven generated C
streams and executables, native measurements and joined guest evidence are
retained under `build/ios/fortnite/media-time-checks`. The actual IPA calls
`CACurrentMediaTime` at `0x10a64d53c`.

That probe stopped before application entry at
`_VTDecompressionSessionCanAcceptFormatDescription`. VideoToolbox now provides
all six VideoToolbox functions imported by this IPA, backed by the optional
FFmpeg software H.264/HEVC decoder. Sessions own their codec, immutable format
and output attributes. Successful decodes deliver independently allocated BGRA,
limited-range NV12 or full-range NV12 buffers, with the sample timestamp, duration
and caller reference delivered through the native callback ABI. Each callback
borrows its image; clients retain it to outlive that callback. Full-range
conversion is configured before scaler initialization to preserve the advertised
pixel levels.

The current profile processes one ready sample per call, with fixed dimensions
and configuration and no frame reordering. Async and temporal permission flags
allow synchronous completion; the actual IPA supplies flag value 9 at
`0x1078cb7a0`. The realtime hint is accepted and DoNotOutputFrame decodes with a
null callback image. Wait joins active decoding. Invalidation joins callbacks
from other threads; callback-local invalidation retires the runner codec after
the active operation returns. Retained pixel buffers survive codec destruction.
Format changes require a fresh session. Hardware decoding, reorder queues,
protected video, image-backed sample construction and the system Metal renderer
remain unavailable.

The installed Mac VideoToolbox library and V runner pass the same H.264/HEVC
red/blue frame checks for all three pixel formats, timestamp/duration ABI,
parameter-error output preservation, decode hints, suppressed images and joined
callbacks. Runner checks additionally exercise corrupt-packet rejection and
recovery, callback-local invalidation/release and two fully drained runtimes.
Eight host ASan/UBSan runs and four ARM64 Vinix suites cover decoding, H.264/HEVC
format metadata and pixel allocation. Eleven generated C/executable pairs,
pinned inputs, native measurements and actual IPA evidence are retained under
`build/ios/fortnite/video-decode-checks`. Earlier failed trials remain identified
there. The measured Mac deadlocks when invalidation is called inside its own
callback; that retirement case is tested only on the runner.

`tests/ios/build-video.v` builds the optional ARM64 SDK from the reviewed
FFmpeg archive in `tests/packages/ffmpeg-source.json`; it verifies its digest,
disables hardware/GPL/nonfree components and reserves x18. Use a fresh output
directory:

```sh
v -gc none -cc clang -o build/ios/build-video tests/ios/build-video.v
build/ios/build-video build/package-ffmpeg-work/ffmpeg-8.0.1.tar.xz build/ios/video
v -gc none -cc clang run tests/ios/native-checks.v build-video-decode
```

`VINIX_IOS_VIDEO_SDK` selects that SDK directory (default `build/ios/video`).
The native V driver adds `ios_video`, the matching target headers and the static
decoder libraries. The decode fixture requires the SDK. Runners built without
the optional backend report decoder-not-found from session creation.

After the six VideoToolbox imports resolved, the probe stopped at
`_$s8StoreKit10StorefrontV11countryCodeSSvg`. StoreKit now implements that
Swift getter. It borrows the resilient `Storefront` through x20, reads its
country field at offset zero and returns an owned String pair in x0/x1.
It retains the existing String owner, preserves Swift context/error registers
and uses a sealed adapter that is unmapped after callers drain. The getter
requires no per-call heap allocation.

The installed StoreKit library and SDK confirm the field layout and bridge
retention. Native comparisons cover small, immortal, native heap and Cocoa
Strings, read-only fields beside guard pages, result survival after source
release and concurrent ARC. Eight host ASan/UBSan runs and four ARM64 Vinix
suites cover the getter and existing String, NSString bridge and shared UTF-8
behavior, including concurrent publication and two drained runtime lifetimes.
Native measurements, actual IPA call sites, pinned inputs and eleven generated
C/executable pairs are retained under `build/ios/fortnite/storefront-checks`.
The fixture is available through `tests/ios/native-checks.v build-storefront`
and the native check inventories.

That probe next stopped at `_$s8StoreKit10StorefrontV7currentACSgvgZ`.
The asynchronous [Storefront.current](https://developer.apple.com/documentation/storekit/storefront/current)
query now supports the accountless profile. Vinix has no App Store account
service, so it completes with `Optional<Storefront>.none`. The native value
witnesses encode that result in the country String's bridge word at offset 8;
the other payload bytes remain uninitialized. Account integration and queries
that return a populated storefront remain unavailable.

The async entry receives its indirect result in x0 and child context in x22.
It tail-resumes the caller with that same child context, allowing the caller to
free the frame during completion. Its separate read-only async descriptor
advertises the measured 64-byte context and relative entry point. Code and
descriptor pages are retired after task callers drain.

Native measurements on this Mac returned no storefront. Native and runner
tests exercise real nested task calls, guarded optional results, child-frame
release and single continuation resumption. Eight host ASan/UBSan runs and four
ARM64 Vinix suites cover this path, the country getter, task creation and
100,000-switch continuation regressions. Eleven generated C/executable pairs,
pinned inputs and joined IPA evidence are retained under
`build/ios/fortnite/storefront-current-checks`; the new fixture is available
through `tests/ios/native-checks.v build-storefront-current`.

The subsequent Storefront metadata accessor and nominal descriptor imports,
`_$s8StoreKit10StorefrontVMa` and `_$s8StoreKit10StorefrontVMn`, now have a
canonical StoreKit implementation. Native metadata describes a 48-byte value:
country and identifier Strings at offsets 0 and 16, followed by Locale's
implementation object and table at 32 and 40. All eight value witnesses are
implemented, including field ownership during reentrant assignment, whole-value
take assignment, and single-payload enum encoding through UInt32 case limits.

Storefront exceeds Swift's three-word inline value buffer. Its buffer witness
shares a retained, registered 64-byte box and returns the payload at offset 16;
the box destructor releases all three owned fields before freeing storage.
The existing Any implementation recognizes those boxes. Code and metadata use
the existing sealed RX/R pages and retire after callers drain. The private
nominal descriptor supports symbolic type lookup; field reflection, broader
Storefront APIs and account services remain unavailable.

Eight host ASan/UBSan runs and four ARM64 Vinix suites validate metadata,
the async current query, Any and Locale. Native comparisons include actual
String/Locale values, reentrant field destruction, shared buffers, guarded and
unaligned enum storage, concurrent callers, and two sealed/unmapped runtimes.
Eleven generated C/executable pairs and pinned native/IPA evidence are retained
under `build/ios/fortnite/storefront-metadata-checks`. The fixture is available
through `tests/ios/native-checks.v build-storefront-metadata` and the native
check inventories.

The subsequent `Transaction.beginRefundRequest(for:in:)` entry and async
descriptor now support the unavailable-platform profile. Vinix has no refund
service, so each call throws an owned CFError with `SKErrorDomain`, SDK
`SKErrorUnsupportedPlatform` (19), and a localized explanation. The entry
does not submit a request or report a status. It leaves the indirect result
and borrowed transaction/scene arguments untouched, returns the Error in x21,
and tail-resumes the same child x22, which the caller may immediately free.

`RefundRequestStatus` has canonical metadata and all eleven enum value
witnesses: a one-byte POD value, two cases, and 254 extra inhabitants.
Single-payload witnesses preserve native tag-width transitions and UInt32
wrapping. Its private nested nominal descriptor supports symbolic lookup;
Transaction's broader metadata, reflection, conformances and refund UI remain
unavailable. These entries share the existing sealed StoreKit pages and drain
with their callers.

Eight host ASan/UBSan runs and four ARM64 Vinix suites cover this path,
Storefront.current, task creation, and NSError/Error bridging. The enum was
compared with native witnesses; generic async throwing/catching was compared
with native Swift tasks and synthetic CFErrors. Native refund service entries
were inspected without invocation. The installed Mac entry has a 112-byte
context, also used by this profile; its UIKit counterpart is unavailable on
this Mac. Pinned measurements, joined IPA evidence and eleven generated
C/executable pairs are retained under `build/ios/fortnite/refund-checks`.
The fixture is available through `tests/ios/native-checks.v build-refund` and
the native check inventories.

StoreKit's three `SKAdNetworkCoarseConversionValue` globals now expose stable
NSString pointer cells containing `high`, `medium` and `low`. The values and
CFSTR representation were measured directly from the installed iOSSupport
StoreKit shared-cache image. The IPA's actual consumer selects a pointer cell,
then loads its NSString value. These globals occupy a sealed read-only page
and remain available until pools, collections and Swift contexts drain.
They do not provide an attribution service or submit postbacks.

Eight host ASan/UBSan runs and four ARM64 Vinix suites cover the constants,
Storefront.current, NSString-to-Swift bridging and Objective-C associations.
Checks include native string/ownership comparisons, contended publication,
equal-key dictionary lookup, read-only/non-executable mappings, pool destructor
availability and two unmapped runtime lifetimes. Pinned native/IPA evidence
and eleven generated C/executable pairs are retained under
`build/ios/fortnite/storekit-constants-checks`. The fixture is available through
`tests/ios/native-checks.v build-storekit-constants` and the native inventories.

The subsequent `_adler32` import now has a V implementation independent of
the graphics backend. It preserves the Darwin unsigned-long seed/result and
32-bit length ABI, normalizes seed halves, supports incremental updates,
and uses bounded block sums without allocations or runtime-owned state.
The fixture compares native zlib and an independent per-byte reference across
guarded/read-only buffers, three byte patterns, arbitrary seeds, chunk
boundaries through 1 MiB, known vectors and eight concurrent callers.
Native zlib's null-buffer/one-byte fast path faults on this Mac; the V entry
safely returns the reset checksum for every null-buffer length. That unsafe
native call is excluded from subsequent comparisons, with its diagnostic
retained. The fixture is available through
`tests/ios/native-checks.v build-zlib-checksum` and the native inventories.

Eight further host ASan/UBSan runs and four ARM64 Vinix suites cover Adler-32,
the StoreKit constants, NSString bridging and Storefront.current. The actual
IPA consumer's reset and incremental calls were inspected with V/Mach-O/LLVM.
Pinned native/IPA evidence and eleven generated C/executable pairs are retained
under `build/ios/fortnite/zlib-checksum-checks`.

`compress2` and `compressBound` now have V implementations with the Darwin
64-bit buffer-length and 32-bit level/status ABI. The encoder uses LZ77 with a
32 KiB window and fixed Huffman blocks; levels control match-search effort.
Level zero uses stored blocks, also used as a fallback for incompressible data
to keep output within `compressBound`. The history uses at most 512 KiB per
active compression call and is freed on success and error. No graphics backend
or native zlib library is required. Encoded bytes and compression ratios can
differ from native zlib; the resulting RFC 1950 streams remain interoperable.

The fixture checks native errors, headers and unsigned-long bound arithmetic,
and decodes V output using both native zlib and an independent V inflater.
It covers all levels, four input patterns, exact 32 KiB match distances,
64 KiB block boundaries, guarded/read-only input, bounded output, length-cell
canaries, insufficient buffers, real compression and eight concurrent callers.
The fixture is available through `tests/ios/native-checks.v build-zlib-compress`
and the native inventories.

Eight host ASan/UBSan runs and four ARM64 Vinix suites cover compression,
Adler-32, NSString bridging and Storefront.current. The actual IPA's compression
call and its level selection were inspected with V/Mach-O/LLVM. Pinned inputs,
native measurements, joined probe/audit logs and eleven generated C/executable
pairs are retained under `build/ios/fortnite/zlib-compress-checks`.

`deflateBound` now has an allocation-free V implementation with Darwin's
64-bit unsigned-long arithmetic. It validates the stream, accounts for raw,
zlib and gzip wrappers, preset dictionaries and custom gzip headers, and
selects tight or conservative bounds from the stream settings. Initialized
streams use the private LP64 deflate-state prefix shared by the inspected Mac
zlib 1.2.12 and the supplied musl backend; changing that backend requires
rerunning the native interoperability fixture. The function neither creates
stream state nor adds streaming compression to the static runner.

The inspected Darwin library underestimates some raw and zlib streams with a
preset dictionary (64 KiB random input, level 1, fixed Huffman strategy). V uses a
larger conservative bound for that case so the compressor can finish without
exhausting the output buffer. Other measured Darwin results, including wrapping
arithmetic, are preserved.

`tests/ios/native-checks.v build-zlib-bound` builds the fixture. It compares
Darwin bounds, including unsigned overflow, checks guarded read-only ABI
objects and exercises real native streams, reset, dictionaries and custom gzip
headers. Compression must finish within the returned capacity, and the backend
inflater verifies the resulting raw/zlib/gzip data. The actual IPA consumer
initializes a gzip stream, obtains its bound and then ends the stream; its
instructions were inspected with V/Mach-O/LLVM.

Eight host ASan/UBSan runs and four ARM64 Vinix suites pass, covering stream
bounds, compression, NSString bridging and Storefront.current. Native streams
from the Mac's zlib 1.2.12 and Vinix's packaged zlib 1.3.2 both finish within
the V bounds. Pinned inputs, native/IPA inspection and eleven generated
C/executable pairs are retained under `build/ios/fortnite/zlib-bound-checks`.

`res_9_query` now constructs standard recursive DNS questions in V, including
SRV records, escaped label bytes, root names and the full 16-bit class/type
fields. It classifies returned DNS response codes and answer counts into BIND's
`h_errno` values, preserves reply bytes, and bounds every write by the supplied
answer capacity. Query construction and classification allocate no heap memory.
The existing libc `res_send` handles configured nameservers, retries, UDP and
TCP fallback. Queries use the default recursive profile without EDNS extensions.

`tests/ios/native-checks.v build-resolver-query` builds the fixture. A local DNS
server supplies real SRV replies, negative answers and a 65,535-byte TCP reply
after UDP truncation. The fixture compares Mac BIND behavior and checks protected
input/output boundaries, invalid and short arguments, error translation and
eight concurrent query builders. Test VM resolver configuration points to its
own loopback server. musl discards some DNS error responses that Mac BIND returns;
these follow musl's retry policy and become `TRY_AGAIN` with Darwin's timeout
error when the exchange expires.

Eight host ASan/UBSan runs and four ARM64 Vinix suites pass, covering DNS,
native zlib stream bounds, NSString bridging and Storefront.current. The IPA's
SRV query and 65,535-byte answer capacity were inspected with V/Mach-O/LLVM.
Pinned inputs, native measurements, probe/audit logs and eleven generated
C/executable pairs are retained under `build/ios/fortnite/resolver-query-checks`.

`CCKeyDerivationPBKDF` implements PBKDF2 in V using SHA1, SHA224, SHA256,
SHA384 and SHA512. It preserves CommonCrypto's separate PRF numbering,
parameter errors and nine-argument LP64 ABI. Binary passwords and salts,
empty inputs, long HMAC keys and partial output blocks are supported. Null
passwords, zero rounds/output lengths, overflowing pointer ranges and output
lengths exceeding the four-byte PBKDF2 block counter are rejected before writes.
Three owned hash states are reused across all rounds and freed on completion;
the round loop allocates no memory and stack key/output temporaries are wiped.

`tests/ios/native-checks.v build-pbkdf` builds the fixture. It compares all five
PRFs against the installed Mac CommonCrypto, checks RFC 6070 vectors, protected
buffer boundaries, error paths and concurrent callers. V/Mach-O/LLVM inspection
of the actual IPA found two SHA1 callers: one derives 16 bytes using eight salt
bytes and 1,000 rounds; the other uses 10,000 rounds and a runtime output length.
Both profiles are included in the fixture.

Eight retained host ASan/UBSan runs and four ARM64 Vinix suites pass, covering
PBKDF2, DNS, native zlib stream bounds and Storefront.current. Pinned sources,
Mac/IPA inspection, probe/audit logs and eleven generated C/executable pairs are
retained under `build/ios/fortnite/pbkdf-checks`.

`NDR_record` now exports the native eight-byte MIG representation descriptor
from V's existing system-data storage. It is a writable object with stable
identity during an execution; lookups preserve caller changes, and a new runtime
restores the little-endian, ASCII and IEEE defaults. The object shares its
owner's allocation and teardown without a separate allocation or mapping.

`tests/ios/native-checks.v build-ndr-record` compares the Mac SDK's field offsets,
native bytes and writable mapping, and checks scoped lookup, guarded message
copies, concurrent readers and two reset/teardown cycles. V/Mach-O/LLVM inspection
of the actual IPA shows an eight-byte load through the imported address followed
by an unaligned store at offset 24 in a 36-byte Mach message. This data export
does not add Mach IPC services.

Eight host ASan/UBSan runs and four ARM64 Vinix suites pass, covering the NDR
record, native zlib stream bounds, PBKDF2 and Storefront.current. Pinned inputs,
native/IPA inspection, probe/audit logs and eleven generated C/executable pairs
are retained under `build/ios/fortnite/ndr-record-checks`.

That probe exited with status 1 before application entry at `__Exit` from
`libSystem.B.dylib`.

C11 `_Exit` (Mach-O `__Exit`) now resolves through a V adapter with an explicit
signed 32-bit argument and a no-return contract. The native libc backend
terminates the whole process from either the main thread or a worker, without
running libc/image exit callbacks, C++/TLS destructors or flushing buffered
stdio. It also works before image runtime initialization and allocates no memory.

`tests/ios/native-checks.v build-immediate-exit` builds the subprocess fixture.
It compares Vinix's adapter against the installed Mac `_Exit`, including negative
and wrapping status values, and uses regular exit, image cleanup and thread
return as positive controls for the callbacks and buffered output. V/Mach-O/LLVM
inspection of the actual IPA follows both levels of branch islands and finds
three direct callers and a tail forwarder, each passing zero in `w0`.

Eight host ASan/UBSan runs and four ARM64 Vinix suites pass, covering immediate
exit, native zlib stream bounds, the writable NDR record and Storefront.current.
Pinned inputs, native/IPA inspection, joined probe/audit logs and eleven
generated C/executable pairs are retained under
`build/ios/fortnite/immediate-exit-checks`.

That probe exited with status 1 before application entry at `__NSGetEnviron`
from `libSystem.B.dylib`.

`_NSGetEnviron` (Mach-O `__NSGetEnviron`) now returns the writable libc process
environment cell through a V adapter. Its address stays stable when callers
replace the vector or libc grows it; the existing `getenv`, `setenv` and
`unsetenv` imports observe the same live vector. The getter is independent of
image initialization, preserves errno and allocates no memory.

`tests/ios/native-checks.v build-crt-environ` builds the isolated subprocess
fixture. It compares the installed Mac getter with the V adapter, checks empty,
UTF-8 and embedded-equals values, growth, overwrite/removal, null/empty vector
replacement and eight concurrent readers. Each child owns its mutations; the
driver's environment stays intact. V/Mach-O/LLVM inspection of the actual IPA
finds the call at `0x1006b5634`, followed by loading the returned cell and walking
eight-byte string pointers until the null terminator.

Eight host ASan/UBSan runs and four ARM64 Vinix suites pass, covering the CRT
environment getter, native zlib stream bounds, immediate process exit and
Storefront.current. Native/IPA inspection, joined logs, pinned inputs and eleven
generated C/executable pairs are retained under
`build/ios/fortnite/crt-environ-checks`.

That probe exited with status 1 before application entry at
`__NSGetExecutablePath` from `libSystem.B.dylib`.

`_NSGetExecutablePath` (Mach-O `__NSGetExecutablePath`) now copies the main
image's cached path through a V adapter. It uses the Darwin 32-bit result and
size pointer, includes the NUL byte in the required size, leaves successful
capacity and errno unchanged, and reports insufficient buffers before touching
their contents. The path is available before image initializers and remains
stable across working-directory changes. The getter allocates no memory.

`tests/ios/native-checks.v build-executable-path` builds the fixture. It compares
the installed Mac behavior, checks protected source/output/size boundaries,
read-only successful size pointers, paths longer than PATH_MAX, UTF-8, eight
concurrent readers and two retired runtimes. Missing or retired main-image
state and invalid output parameters reject explicitly. V/Mach-O/LLVM inspection
of the actual IPA finds the zero-size query at `0x1000a68a8`, allocation using
that 32-bit result and the buffer-fill call at `0x1000a68c0`.

Eight host ASan/UBSan runs and four ARM64 Vinix suites pass, covering executable
paths, native zlib stream bounds, the CRT environment cell and Storefront.current.
Native/IPA inspection, pinned inputs, joined logs and eleven generated
C/executable pairs are retained under
`build/ios/fortnite/executable-path-checks`.

That probe exited with status 1 before application entry at
`__dispatch_source_type_timer` from `libSystem.B.dylib`.

The dispatch timer source type now resolves to a direct, aligned, read-only
V constant. The public type is opaque: clients pass the object's address to
`dispatch_source_create`, without loading a pointer cell or depending on
Apple's private descriptor fields. Its identity is independent of queue and
image runtime initialization and teardown; resolving it allocates no memory.
This export does not implement source creation, timer delivery or cancellation.

`tests/ios/native-checks.v build-dispatch-timer-type` builds the fixture. It
checks library and symbol scope, read-only storage, unchanged errno, eight
concurrent readers and stable identity across two retired runtimes. The Mac
reference confirms the public macro and dynamic export name the same data
object and that its native timer factory accepts zero and strict masks.
V/Mach-O/LLVM inspection finds four actual IPA consumers at `0x100007b78`,
`0x10001553c`, `0x1000399d8` and `0x10009e4e0`, each loading the import slot
directly into the factory's first argument.

Eight host ASan/UBSan runs and four ARM64 Vinix suites pass, covering the timer
type, native zlib stream bounds, the CRT environment cell and Storefront.current.
Native/IPA inspection, pinned inputs, joined logs and eleven generated
C/executable pairs are retained under
`build/ios/fortnite/dispatch-timer-type-checks`.

That probe exited with status 1 before application entry at
`__dyld_get_image_header` from `libSystem.B.dylib`.

The V dyld adapter now implements `_dyld_image_count`, `_dyld_get_image_header`,
`_dyld_get_image_name` and `_dyld_get_image_vmaddr_slide` (Mach-O `__dyld_*`).
It enumerates the main executable followed by mapped bundled Mach-O libraries,
returns their live headers and borrowed UTF-8 paths, and computes signed
64-bit slides from each mapping's preferred address. A header can sit above
the mapping's lowest segment; `dladdr` and `getsectiondata` now agree with that
header address. Invalid 32-bit indices return null/zero without changing errno.
Queries allocate no memory, and their borrowed pointers remain valid until
application activity and destructors drain at module teardown. Static import
audits expose an empty image set because they create no Mach-O mappings.

`tests/ios/native-checks.v build-dyld-images` builds the fixture. It maps three
V-generated and parsed images between guard pages, checks real load commands,
positive and negative slides, UTF-8 names, section lookup, upper-bound indices,
eight readers and two teardown cycles. The Mac reference checks the public
API, native shared-cache headers and an empty compiler-produced dylib's
publication, repeated opens and unload. V/Mach-O/LLVM inspection finds four
actual header-query callers, including `0x10008bd74` and `0x10062e1b0`, which
identify the main image by file type and walk its load commands.

Eight host ASan/UBSan runs and four ARM64 Vinix suites pass, covering dyld image
queries, native zlib stream bounds, cached executable paths and the dispatch
timer type. Native/IPA inspection, pinned inputs, joined logs and eleven
generated C/executable pairs are retained under
`build/ios/fortnite/dyld-images-checks`.

That IPA probe exited with status 1 before application entry at
`__dyld_register_func_for_add_image` from `libSystem.B.dylib`.

The V dyld adapter now implements `_dyld_register_func_for_add_image` and
`_dyld_register_func_for_remove_image`. Add registration synchronously replays
published images before retaining the callback, preserving the measured native
ordering for duplicate and nested registrations. A fully bound and protected
batch is published before Objective-C `+load` or image initializers. Linked
bundle libraries stay mapped across `dlclose`; actual execution retirement
delivers removal notifications in reverse initialization order after
destructors, with headers, paths, Objective-C and TLS still available.

A process-lifetime recursive native mutex serializes callback registration,
delivery and module retirement independently of the Objective-C lock.
Per-execution callback arrays release their replaced buffers and are freed
before the module registry. An active callback pins the registry across a
concurrent teardown. Failed binding and static audits execute no notifications.

`tests/ios/native-checks.v build-dyld-callbacks` builds the fixture. It checks
real guarded Mach-O headers and signed slides, duplicate/nested replay, batch
publication, eight concurrent registrars, linked reopens and callback draining.
It also executes a V-generated ARM64 Mach-O twice through constructor, main,
destructor and removal callback; the callback uses live Objective-C and TLS,
and its constructor joins an Objective-C worker to check lock independence.
The Mac reference measures real dylib publication and unload, including
duplicate removal callbacks and image-query visibility during removal.
V/Mach-O/LLVM inspection finds the IPA's add call at `0x1000a8ae4`, remove tail
call at `0x1000a8af8` and an add callback that uses `dladdr`.

Eight host ASan/UBSan runs and four ARM64 Vinix suites pass, covering dyld
callbacks, image queries, native zlib bounds and cached executable paths.
Native/IPA inspection, pinned inputs, joined logs and eleven generated
C/executable pairs are retained under
`build/ios/fortnite/dyld-callbacks-checks`.

That IPA probe exited with status 1 before application entry at
`__tlv_atexit` from `libSystem.B.dylib`.

The V `__tlv_atexit` adapter implements Darwin's void callback/object-pointer
ABI, preserving errno. Each execution has one native pthread key; each thread
owns a stack of destructors and independent storage for every TLS image.
Callbacks run in reverse registration order, including callbacks registered
reentrantly, before any of that thread's image TLS is freed. Native key cleanup
handles both normal thread return and `pthread_exit`, without the pthread
destructor-iteration limit. `fork` keeps the surviving thread's TLS and drops
copies belonging to vanished threads without invoking their callbacks.

Process `exit` drains current-thread TLS before process/C++ exit handlers;
immediate exit skips both, matching native Mac measurements. When an embedded
execution returns, framework workers are joined and the main thread's TLS is
drained before global destructors. Additional drains handle registrations from
global destructors and dyld removal callbacks while Objective-C and image TLS
remain available. Live foreign TLS owners are rejected before framework
teardown; pending callbacks are rejected before deleting the native key or
unmapping code. TLS storage survives all these finalizers and is then freed.

`tests/ios/native-checks.v build-tlv-atexit` builds the fixture. It checks 32
joined workers across two executions, two TLS images per thread, normal and
explicit exit, nil callback arguments, 96 reentrant callbacks, fork ownership,
process/immediate exit and active/pending shutdown rejection. A V-generated
ARM64 Mach-O uses real TLV descriptors through constructor, main, TLS/global
destructors and removal callbacks, checking live Objective-C and TLS twice.
SDK declarations and typed native calls establish the ABI and ordering;
V/Mach-O/LLVM inspection finds 86 IPA consumers/forwarders for this import.

Eight host ASan/UBSan runs and four ARM64 Vinix suites pass, covering TLV exit,
dyld callbacks, zlib bounds and executable paths. Native measurements, IPA
inspection, pinned inputs, joined logs and eleven generated C/executable pairs
are retained under `build/ios/fortnite/tlv-atexit-checks`. Preliminary build
and source-review attempts are retained separately within that cohort.

That IPA probe stopped at `_acosh` from `libSystem.B.dylib`, before
application entry. Its scalar-double call at `0x101b9beac` and branch-island
forwarder are confirmed by LLVM disassembly. Native Mac boundary, NaN,
infinity, errno and floating-exception measurements are retained for the next
adapter. Fortnite remains unplayable and the full iOS regression is unpassed.

V now implements `_acosh`, `_asinh` and `_atanh` for `libSystem.B.dylib`.
The adapters preserve errno, signed zeros, NaN signs and payloads, and existing
floating-exception flags. Domain errors and poles raise the measured Darwin
exceptions. Tiny `asinh`/`atanh` values reproduce Darwin's rounding-dependent
underflow thresholds and one-step magnitude adjustments. Ordinary finite
arguments use the native scalar math backend with the shared double ABI.

The V fixture contains 1,694 vectors measured from this Mac's libSystem,
with finite accuracy independently checked using the installed MPFR library
at 256-bit precision. It checks four rounding modes, existing exception flags,
thread-local errno and eight concurrent callers. Normal results are checked
within two representable steps of the reference in nearest rounding and three
in directed modes; special values and exception effects are checked exactly.
MPFR is used only to generate reference data and is not linked into the runner.
LLVM inspection confirms all three IPA scalar-double calls and their branch
islands at `0x101b9beac`, `0x101b9bd2c` and `0x101b9c02c`.

`tests/ios/native-checks.v build-inverse-hyperbolic` builds the new fixture.
Eight host ASan/UBSan runs and four ARM64 Vinix suites pass, covering these
functions, TLV destruction, dyld callbacks and native zlib bounds. Native/MPFR
measurements, the preliminary rounding failure, pinned inputs, joined logs
and eleven generated C/executable pairs are retained under
`build/ios/fortnite/inverse-hyperbolic-checks`.

That IPA probe gets past the inverse hyperbolic imports and stops at
`_arc4random` from `libSystem.B.dylib`, still before application entry.
Fortnite remains unplayable and the full iOS regression is unpassed.

V now implements `_arc4random` and `_arc4random_buf`, and the existing
`_arc4random_uniform` uses the same OS entropy reader. The typed APIs return
an unsigned 32-bit word, fill exactly the requested `size_t` byte count, and
use rejection sampling for bounded values. Zero and one bounds return zero.
The adapters preserve errno and floating-point state, allocate no temporary
buffers, and keep no userspace generator state or locks across fork. Buffers
are filled in at most 256-byte `getentropy` calls through CommonCrypto's
existing backend. Entropy failure terminates the call instead of returning
uninitialized output; the void Darwin ABI cannot report an error.

SDK declarations and typed calls into this Mac's libSystem confirm the ABI,
zero-length null/protected buffers, errno and exception behavior. V/Mach-O/LLVM
inspection confirms the IPA's unsigned word calls at `0x100077828` and
`0x10007782c`, and its 8-byte buffer calls at `0x100546450` and `0x100546854`.

`tests/ios/native-checks.v build-arc4random` builds the fixture. Eight host
ASan/UBSan runs and four ARM64 Vinix suites pass, covering random APIs,
inverse hyperbolic functions, TLV destruction and native zlib bounds. The
random fixture checks both guarded buffer ends, zero/chunk/page boundaries,
buffers above 16 MiB, all four rounding modes, sticky exception flags,
thread-local errno, eight concurrent callers and fresh parent/child output
after fork. Native measurements, IPA inspection, pinned inputs, joined logs
and eleven generated C/executable pairs are retained under
`build/ios/fortnite/arc4random-checks`.

That IPA probe passes the random imports and stops at `_asl_add_log_file`
from `libSystem.B.dylib`, before application entry. Its caller at `0x100083950`
passes a stored client pointer and descriptor 2. Preliminary typed native ASL
measurements are retained for the next adapter; no log messages were sent.
Fortnite remains unplayable and the full iOS regression is unpassed.

V now implements the ASL client profile imported by this IPA: `_asl_open`,
`_asl_set_filter`, `_asl_add_log_file` and variadic `_asl_log`. `_asl_close`,
`_asl_remove_log_file` and `_asl_vlog` share the same client implementation.
Each client owns a copy of its sender/facility strings in one allocation;
close and runtime shutdown free that allocation. Logging snapshots the filter,
options and a bounded sender prefix under the registry lock, then formats and
writes outside that lock. A concurrent close cannot invalidate the snapshot.

Native libSystem calls establish the default filter of 63, 16-bit mask storage,
out-of-range levels clamped to debug, preserved errno and explicit stderr's
filter bypass. Vinix directs the filtered server stream to local stderr with
an `ident: message` prefix. Legacy file attachments follow the measured modern
libSystem behavior: valid client/nil handles accept descriptors without using
or owning them; the SDK marks this functionality unsupported.

A naked V ARM64 entry passes the incoming stack pointer to a fixed-signature
V formatter. It supports printf scalar, string and pointer conversions with
width/precision, including mixed integer/double arguments and output beyond
the small stack buffer. Unsupported message objects, positional formats,
long doubles, wide strings, `%n` and `%m` return failure explicitly. The profile
limits formats to 65,535 bytes and output to 1 MiB. No Apple ASL library supplies
guest logging.

V/Mach-O/LLVM inspection confirms the IPA's open at `0x1000838c8`, filter at
`0x1000838e4` and log at `0x100083ca4`. The log passes a nil message, a 32-bit
level, `%s` at `0x10c7344bc` and one string pointer on the stack.
`tests/ios/native-checks.v build-asl` builds the fixture.

Eight host ASan/UBSan runs and four ARM64 Vinix suites pass, covering ASL,
random APIs, TLV destruction and native zlib bounds. The ASL fixture checks
real variadic calls, mixed scalar/string arguments, large output, filtered
protected pointers, errno, 1,024 threaded client lifetimes and two runtime
shutdown cycles. Native measurements, IPA inspection, the preliminary compiler
failures, pinned inputs, joined logs and eleven generated C/executable pairs
are retained under `build/ios/fortnite/asl-checks`.

The fresh IPA probe resolves all four ASL imports and stops at `_backtrace`
from `libSystem.B.dylib`, before application entry. The IPA's forwarding
wrapper and preliminary guarded native backtrace measurements are retained
for the next adapter. Fortnite remains unplayable and the full iOS regression
is unpassed.

V now implements `_backtrace` for ARM64 frame chains. A naked V entry captures
the incoming frame pointer, return address and stack pointer before any
compiler-generated frame. The V walker writes the immediate caller PC, then
follows ascending, aligned, complete 16-byte frame records within the current
thread's live stack bounds. It strips return-address authentication bits and
frame-link top-byte tags, preserves interior null PCs and trims trailing null
PCs. The walk allocates no storage and preserves errno and floating-point
state. Zero or negative capacities return zero without touching the buffer;
negative counts are a defensive policy, not the native unsigned-count behavior.

The existing pthread stack-bounds bridge supplies the current stack range.
If those bounds cannot be obtained, or the captured SP is outside them, the
adapter returns only the caller PC. Alternate signal stacks, asynchronous
Swift stack reconstruction, symbolication and DWARF/C++ exception unwinding
remain unsupported. This adapter does not depend on ELF metadata for the
application's mapped Mach-O frames.

Typed native libSystem measurements and LLVM inspection confirm the pointer
array/int32 ABI, frame decoding and trailing-null trimming. V/Mach-O/LLVM
inspection follows the IPA's guarded forwarding wrapper at `0x104844e98` to
actual callers, including fixed capacities of 100, 66 and 10 frames and a
variable-capacity buffer. `tests/ios/native-checks.v build-backtrace` builds
the new fixture.

Eight host ASan/UBSan runs and four ARM64 Vinix suites pass, covering backtrace,
ASL, TLV destruction and native zlib bounds. The backtrace fixture emits three
real ARM64 call frames into executable memory and checks their exact return
PCs against both native libSystem and the V adapter. It also checks guarded
buffer ends, malformed/cyclic/tagged links, incomplete records at a guard
page, all four rounding modes, sticky exception flags, preserved errno,
512 concurrent captures and a forked child. Native measurements, IPA consumers,
preliminary helper compiler failures, pinned inputs, joined logs and eleven
generated C/executable pairs are retained under
`build/ios/fortnite/backtrace-checks`.

The fresh IPA probe passes `_backtrace` and stops at `_dispatch_data_create`
from `libSystem.B.dylib`, before application entry. The IPA also imports
`_dispatch_data_create_concat`; its callers create data with stack-block
destructors, concatenate it and release the input objects. Preliminary typed
native measurements establish default-buffer copying, the empty singleton,
retained concatenation inputs and mapped subrange bytes for the next adapter.
Fortnite remains unplayable and the full iOS regression is unpassed.

V now implements `_dispatch_data_create` and `_dispatch_data_create_concat`,
with `_dispatch_data_get_size`, `_dispatch_data_create_map` and the empty-data
global sharing the same owned representation. Default creation copies the
input bytes. Custom block destructors borrow them, promote the block captures
and retain the supplied queue (or use the default global queue). Concatenation
retains both immutable inputs without copying their bytes. Mapping a leaf
retains that leaf; mapping a composite creates a contiguous owned copy.

Normal final release schedules a custom destructor on its queue exactly once.
Zero-length creation returns the immortal empty singleton and still schedules
its custom destructor. Block calls and dispose helpers run outside the
scheduler mutex and can release other data or query the runtime. Shutdown
joins workers, invokes pending cancellation destructors, then disposes any
remaining application captures while their data buffers are still valid.
Remaining shutdown callbacks run synchronously before Objective-C storage and
application mappings retire. Graph traversal and destruction use iterative
walks rather than recursive calls through concatenation nodes.

Data uses the measured eight-byte Objective-C facade:
`OS_dispatch_data_empty` → `OS_dispatch_data` → `_NSDispatchData` → `NSData`.
Dispatch, Objective-C and Swift unknown-object ownership share the data
registry; generic allocation and isa replacement are rejected. The supported
Objective-C messages cover identity, class queries and ownership. NSData byte
methods, weak references, subranges, region iteration and named FREE/MUNMAP
destructor globals remain unsupported; no native dispatch library supplies
the guest data implementation.

Native libSystem calls establish copy/borrow behavior, capture promotion,
queued destruction, empty-data identity and the class hierarchy. V/Mach-O/LLVM
inspection confirms creation with a stack-block destructor at `0x1078a9f8c`
and concatenation followed by releases of both inputs at `0x101fbeaac`.
`tests/ios/native-checks.v build-dispatch-data` builds the new fixture.

Eight host ASan/UBSan runs and four ARM64 Vinix suites pass, covering dispatch
data, dispatch queue Objective-C ownership, TLV destruction and native zlib
bounds. The data fixture compares the native APIs, checks promoted captures,
queued/empty/shutdown destructor paths, guarded zero buffers, all four rounding
modes, sticky exception flags, errno, 1,024 concurrent lifetimes, 4,096-node
ropes, mapped byte order and three drained runtime lifetimes. Native references,
IPA inspection, the initial invalid native-queue test and corrected runs,
pinned inputs, joined logs and eleven generated C/executable pairs are retained
under `build/ios/fortnite/dispatch-data-checks`.

The fresh IPA probe passes both dispatch-data imports and stops before entry
at `_dispatch_get_specific` from `libSystem.B.dylib`. Preliminary native
measurements confirm pointer keys, local direct lookup, target-chain
inheritance during current-queue lookup, child overrides and nil removal for
the next adapter. Fortnite remains unplayable and the full iOS regression is
unpassed.

V now implements `_dispatch_get_specific`, `_dispatch_queue_set_specific` and
`_dispatch_queue_get_specific`. Keys are compared as pointer identities without
reading their memory. Direct lookup reads one queue; current-queue lookup
follows its target chain, including child overrides and inheritance restored
by nil removal. The main thread denotes the main queue outside callbacks.
Native measurements also distinguish implicitly targeted serial queues from
queues explicitly targeting the public default global queue; Vinix now keeps
those roots separate so their associations stay independent.

Each nonnull association owns one entry. Replacement, removal and the queue's
last release retire its old destructor on the default global concurrent queue.
Replacing an unchanged pointer still retires the previous association. Nil
keys are ignored; nil contexts ignore the supplied new destructor. Queued work
keeps its queue and associations alive through callback completion. Callbacks
run outside the scheduler lock and can query or modify other associations.
Lookup allocates no temporary storage, and the V entry points preserve errno
and floating-point state.

Shutdown joins workers and invokes cancelled owned destructors, then drains
remaining main/global/application queue associations while Objective-C and
application storage remain live. Remaining shutdown destructors run
synchronously; new nonnull associations are rejected during that phase.
Nested synchronous dispatch restores the caller's current-queue TLS value.

V/Mach-O/LLVM inspection confirms the IPA's lookup at `0x100007544` and setter
at `0x1000070dc`, with additional consumers using the same pointer-key ABI.
`tests/ios/native-checks.v build-dispatch-specific` builds the fixture.
Eight host ASan/UBSan runs and four ARM64 Vinix suites pass, covering specific
contexts, dispatch data, queue Objective-C ownership and native zlib bounds.
The new fixture compares native lookup/lifetime behavior, exercises protected
keys, main/global/foreign threads, nested dispatch, all four rounding modes,
sticky exceptions, 1,024 concurrent association lifetimes, queued-work retention,
reentrant destructor queries, deterministic cancellation and two drained
shutdowns. Native measurements, preliminary measurement/compiler failures,
pinned inputs, joined logs and eleven generated C/executable pairs are retained
under `build/ios/fortnite/dispatch-specific-checks`.

The fresh IPA probe passes both required queue-specific imports and stops
before entry at `_dispatch_group_async` from `libSystem.B.dylib`. Preliminary
native group measurements cover membership, empty/immediate waits, asynchronous
work and completion notification for the next adapter. Fortnite remains
unplayable and the full iOS regression is unpassed.

V now implements `_dispatch_group_create`, `_dispatch_group_enter`,
`_dispatch_group_leave`, `_dispatch_group_wait`, `_dispatch_group_async` and
`_dispatch_group_notify`, plus the two function-pointer submission variants.
Native Mac measurements and the supplied IPA's six required imports establish
the function and Apple Blocks ABIs. The async import cell is `0x10dc9a660`,
with a stack-block caller at `0x10000bfb4`; other callers submit global blocks.
Creation is also visible at `0x103ccaae4`.

A nonempty group owns an internal membership reference. Submissions enter
before publishing queue work, promote stack blocks, and leave after both the
callback and copied-block disposal return. Explicit enter/leave pairs preserve
the group after its external owner releases it. Waits support immediate,
monotonic, wall-clock and infinite deadlines, with generation tracking so a
completed wait cannot become attached to a later reuse. Pending notifications
retain their destination queue and copied block, then submit ordinary queue
work when the group becomes empty. Empty-group notifications still enqueue
asynchronously. Capture helpers and notification callbacks run outside the
scheduler mutex.

The native `OS_dispatch_group` → `OS_dispatch_object` → `OS_object` →
`NSObject` hierarchy has an eight-byte public instance size. Vinix publishes
that facade while keeping ownership, membership and callbacks in its private
registry. ObjC and Swift unknown-object ARC use the registry, and generic
construction or isa replacement remains rejected. Context and finalizer APIs
also recognize groups. Shutdown joins workers, cancels queued members, and
disposes pending notification captures before block/class metadata is retired;
unbalanced explicit membership is discarded with remaining image storage.
The separately bounded Swift `DispatchQueue.async` overlay still requires a
nil group.

`tests/ios/native-checks.v build-dispatch-group` builds the fixture. Eight final
host ASan/UBSan runs and four ARM64 Vinix suites pass for groups, queue-specific
contexts, dispatch data and queue ObjC ownership. The new native/V comparisons
cover 1,024 concurrent submissions, nested work, stack/global blocks, copied
capture disposal before completion, early external release, queued notification
ownership, reused generations, deadline clocks and floating-point state.
Vinix checks additionally cover main-queue delivery, ObjC/Swift ownership and
two complete cancellation/shutdown lifetimes. Native measurements, IPA consumer
inspection, preliminary runs, pinned inputs, joined logs and eleven generated
C/executable pairs are retained under
`build/ios/fortnite/dispatch-group-checks`.

The fresh IPA probe passes all six group imports and stops before application
entry at `_dispatch_resume`. Its inspected callers configure timer sources
and event-handler blocks before resuming them. A native scout verifies that
timer sources begin suspended, resume activates their deadline, event data
counts expirations, and cancellation runs its handler after the event callback.
Fortnite remains unplayable and the full iOS regression is unpassed.

V now implements timer-source creation, timer configuration, event/cancel
handlers in Blocks and function-pointer forms, cancellation queries and source
data/handle/mask access. `_dispatch_resume` activates a newly created source;
`_dispatch_suspend` and later resumes maintain a balanced suspension count.
The same calls suspend queues, including their serial target descendants.
`_dispatch_set_target_queue` supports inactive sources and idle application
queues, retaining their new targets and rejecting cycles or changes that would
invalidate running work.

Timers use the existing dispatch workers, scheduler condition and queue jobs.
One-shot and repeating timers preserve monotonic or wall-clock deadlines,
coalesce missed expirations, and prevent concurrent invocation of one source
even on a concurrent target. Reconfiguration clears accumulated pending data.
Forever deadlines disarm delivery; zero intervals become one nanosecond. The
timer flag profile accepts ordinary and strict timers and fires at the requested
deadline without adding a deliberate leeway delay. Other source kinds remain
unsupported.

Handler updates are queued within the source. Event functions receive the
context captured when registration takes effect, while cancel functions receive
the source context current at delivery. Updates submitted during an event may
take effect after the source yields its target queue. Copied blocks and the
source's target queue remain owned until replacement, cancellation or shutdown.
Explicit cancellation suppresses future events and delivers its handler after
any running event returns. Cancellation before activation or during suspension
waits for a resume. Native measurements also show that the last external release
implicitly cancels an active source without invoking its cancel handler.

The eight-byte `OS_dispatch_source` facade inherits from `OS_dispatch_object`.
ObjC and Swift unknown-object ARC use separate external and internal source
references. Queue work pins the source through callback return and capture
disposal. Shutdown joins workers, cancels queued jobs and disposes all remaining
handler updates/captures before retiring class metadata or application storage;
sources remain registered while cross-source capture cycles are dismantled.

`tests/ios/native-checks.v build-dispatch-source` builds the new fixture. Ten
host ASan/UBSan runs and five ARM64 Vinix suites pass for timer sources, groups,
queue-specific contexts, dispatch data and queue ObjC ownership. Native/V tests
exercise deferred contexts, handler replacement during execution, copied block
ownership, 128 concurrent source lifetimes, one-shot rearming, clock domains,
suspension, nonreentrant callbacks, explicit/implicit cancellation and floating
state. Vinix additionally tests source/queue targets, main delivery, ObjC/Swift
ownership and two shutdowns with queued and cyclic captures. The sanitizer run
identified a mutable-map pointer lowering issue in the V compiler; scheduler
loops now bind each stored pointer to a local before passing it to a helper.
Generated-C checks verify that those calls receive source storage rather than
the address of a map slot.

V/Mach-O/LLVM inspection locates timer creation at `0x100007b8c` and balanced
suspension at `0x1000156d0`. Native measurements, initial invalid test
assumptions and the sanitizer failure, corrected runs, pinned inputs, joined
logs and thirteen generated C/executable pairs are retained under
`build/ios/fortnite/dispatch-source-checks`.

The fresh IPA probe passes eight more required imports and stops before
application entry at `_dispatch_semaphore_create`. A native scout verifies token
consumption, immediate timeout value 49, signaling with and without a blocked
waiter, and balanced release. The initial scouts released unbalanced
semaphores and trapped; the invalid-count case was not isolated in those runs.
They are preserved separately. Fortnite remains unplayable and the full iOS
regression is unpassed.

V now implements `_dispatch_semaphore_create`, `_dispatch_semaphore_wait` and
`_dispatch_semaphore_signal`. Negative creation returns null; a positive initial
count permits that many immediate acquisitions. Empty waits support immediate,
monotonic, wall-clock and forever deadlines, returning Darwin timeout value 49.
A signal grants exactly one registered waiter or adds one available token, and
returns whether it woke a waiter. The scheduler mutex serializes grants and
timeout removal, so a timed-out wait cannot consume a later signal. Each wait
record stays on its thread's stack, with no allocation on the wait/signal path.

The eight-byte `OS_dispatch_semaphore` facade inherits from
`OS_dispatch_object`; dispatch, ObjC, Swift unknown-object ARC and copied Block
captures share its ownership. Contexts and finalizers use the existing dispatch
object APIs. Final release requires all waits to have returned and the original
token balance to have been restored, then schedules its finalizer outside the
mutex. Shutdown disposes queued captures before freeing remaining semaphore
storage. Generic ObjC allocation remains rejected. A new isolated native test
corrects the earlier invalid-count note: negative creation returns null, while
releasing a consumed positive-count semaphore traps.

`tests/ios/native-checks.v build-dispatch-semaphore` builds the fixture. Ten host
ASan/UBSan runs and five ARM64 Vinix suites pass for semaphores, timer sources,
groups, dispatch data and queue ObjC ownership. The semaphore suite compares
native and V behavior for eight blocked waiters, 2,048 handoffs through a
three-token resource pool, 64 timeout/signal races, timer callback signaling,
stack Block captures, contexts/finalizers and floating-point state. Vinix also
checks ObjC/Swift ownership, unbalanced-release diagnosis and two drained
shutdowns. Generated-C review found and corrected V heap promotion of the wait
record; the first passing cohort is retained alongside the corrected runs.

V/Mach-O/LLVM inspection finds creation at `0x10214f270` followed by
`MKW_GetCurrent` and a forever wait at `0x10214f2a4`. Native reference results,
pinned inputs, joined logs and thirteen generated C/executable pairs are under
`build/ios/fortnite/dispatch-semaphore-checks`. The fresh IPA probe passes all
three semaphore imports and stops before application entry at `_div`. A native
scout verifies its signed 32-bit arguments and eight-byte quotient/remainder
result. Fortnite remains unplayable and the full iOS regression is unpassed.

V now implements `_div` with Darwin ARM64's eight-byte `div_t`: signed
32-bit quotient and remainder fields return together in `x0`. Results truncate
toward zero, and a nonzero remainder has the numerator's sign. The adapter
uses integer arithmetic without allocations or changes to errno, rounding mode
or sticky floating-point flags. Explicit branches reproduce the measured ARM64
results for zero divisors and `INT_MIN / -1`, without evaluating undefined C
division in the generated code. Those inputs remain outside the C language
contract; their behavior here follows the native ARM64 library.

LLVM inspection of this Mac's `div` confirms 32-bit `SDIV`/`MSUB` arithmetic
and packing into `x0`. V/Mach-O/LLVM inspection finds Fortnite's call at
`0x10027279c`, followed by a shift extracting the remainder from the upper
32 bits. `tests/ios/native-checks.v build-division` builds the new fixture. Two
host ASan/UBSan runs and the ARM64 Vinix suite pass for signed boundaries,
exhaustive small operands, 32,768 full-width pairs, native oracle comparisons,
four rounding modes and eight concurrent callers. A machine-code call probe
checks dirty upper input bits, packed return fields, a protected indirect-result
address, a callee-saved register and output canaries.

Native measurements, disassembly, the corrected test pointer-cast build failure,
pinned inputs, joined logs and five generated C/executable pairs are retained
under `build/ios/fortnite/division-checks`. The fresh IPA probe passes `_div`
and stops before application entry at `_exception_raise`. Native exception
client scouts verify the three client signatures and invalid-destination errors
without invoking a live exception server. Mach exception delivery remains
unimplemented. Fortnite remains unplayable and the full iOS regression is
unpassed.

V now resolves `_exception_raise`, `_exception_raise_state` and
`_exception_raise_state_identity` for the current Mach task/thread/semaphore
namespace. The clients check the native limits of two signed 32-bit exception
codes and 1,296 unsigned 32-bit state words before port lookup, returning
`MIG_ARRAY_TOO_LARGE` for oversized inputs. Missing or dead destinations return
`MACH_SEND_INVALID_DEST`; missing descriptor rights return
`MACH_SEND_INVALID_RIGHT`. Live kernel ports reject the RPC with the measured
`KERN_FAILURE` or `KERN_INVALID_ARGUMENT`, preserving inputs, outputs, flavor,
count, send references, semaphore credits, errno and floating-point state.
Destroying a semaphore preserves any retained send rights until their last
reference is dropped. Native Mac ports use the native transport in host tests.

This is a client validation and kernel-port error subset: Vinix still has no
public Mach receive ports, user exception-message delivery or kernel fault
interception. V/Mach-O/LLVM inspection finds Fortnite's three forwarding calls
at `0x1000b459c`, `0x1000b4650` and `0x1000b4618`, including the state clients'
ninth through eleventh arguments on the stack.
`tests/ios/native-checks.v build-mach-exception` builds the fixture. Two host
ASan/UBSan runs and the
ARM64 Vinix suite pass for bounds and error precedence, live/retired rights,
ownership, eight concurrent callers, fork and two image teardowns. Generated-C
review verifies stack temporaries, lock release and no new adapter allocations.

Native measurements, failed test assumptions and their corrections, joined
logs, pinned inputs and five final generated C/executable pairs are retained
under `build/ios/fortnite/mach-exception-checks`. The IPA probe passes all three
client imports and stops before entry at `_flock`. Native RE verifies its
locking flags and Fortnite's nonblocking unlock at `0x1005a752c`. Fortnite
remains unplayable and the full iOS regression is unpassed.

V now resolves `_flock` for regular files and directories using native kernel
locks. The adapter reproduces Darwin's unlock-before-exclusive-before-shared
flag precedence, ignores unknown bits, preserves the nonblocking bit and maps
contention to Darwin `EWOULDBLOCK` (35). Invalid operations on valid files report
`EBADF`; pipes and sockets report `ENOTSUP` before operation validation. Kernel
open descriptions retain ownership through dup and fork, wake blocking waiters,
and release locks on last close. The adapter adds no allocation or lifetime state.

This remains a Linux lock backend: a failed shared-to-exclusive conversion can
drop the shared lock, and flock/POSIX record locks have separate conflict domains.
Native Darwin retains the shared lock and makes those lock domains interact.
Device locks remain unsupported on Vinix and return `ENOTSUP`.

`tests/ios/native-checks.v build-flock` builds the fixture. Two host ASan/UBSan
runs and the ARM64 Vinix suite pass for 80 flag combinations, real contention
and blocking wakeup, directories, read/write access, descriptor errors, dup/fork
ownership, dirty upper ARM64 arguments, ordinary status flags, contents, offsets,
errno, floating-point state and eight concurrent callers. The tests account for
the Mac's additional `F_GETFL` bit after flock. Worker fixtures are opened before
the concurrent calls; the initial guest fixture-open failure is retained.

Native reference measurements, the failed attempts, joined logs, pinned inputs
and five final generated C/executable pairs are under
`build/ios/fortnite/flock-checks`. V/Mach-O/LLVM inspection confirms Fortnite's
nonblocking unlock at `0x1005a752c`. The fresh IPA probe passes `_flock` and stops
before entry at `_getprogname`. Native RE verifies its stable borrowed basename
pointer. Fortnite remains unplayable and the full iOS regression is unpassed.

V now resolves `_getprogname` from the main image's original `argv[0]`.
Startup installs a borrowed basename pointer before dependency binding and
initializers; it remains available through entry, joined workers and teardown.
Later edits to the original bytes remain visible, while replacing the argv cell
or introducing another slash does not recompute the pointer. The bounded scan
stops at the first NUL, handles empty and trailing-slash names, and adds no
allocation. Calls without a configured image fail explicitly. Native Darwin
measurements and LLVM disassembly verify its stored-pointer behavior.

`tests/ios/native-checks.v build-progname` builds the regression fixture.
Two host ASan/UBSan runs and the ARM64 Vinix suite pass for guarded read-only
inputs, long and UTF-8 names, embedded NULs, mutable aliases, errno and
floating-point state, eight concurrent readers, import scoping and invalid
lifecycle states. A generated ARM64 Mach-O binds the real import and verifies
initializer, entry and destructor callbacks over two complete executions,
including replacement of its argv cell. Generated C review confirms the bounded
scan, borrowed lifetime and initialization order.

Native references, joined logs, pinned inputs and five generated C/executable
pairs are retained under `build/ios/fortnite/progname-checks`. Failed fixture
attempts are retained: the legacy import table initially lacked its nlist entry,
and an incorrect ADRP displacement reached the wrong page. LLVM verifies all
three corrected callback stubs in both executed host fixtures. The fresh IPA
probe passes `_getprogname` and stops before entry at `_host_page_size`.
V/Mach-O/LLVM inspection identifies its call at `0x1005a715c` for the next
adapter. Fortnite remains unplayable and the full iOS regression is unpassed.

V now resolves `_host_page_size` from the same writable cache exported as
`_vm_page_size`. Native ARM64 disassembly shows that Darwin's public function
ignores the host port, stores the cached eight-byte `vm_size_t` and returns
success. The V adapter follows that behavior using Vinix's page size, preserves
errno and floating-point state, and adds no allocation or port lifetime.

`tests/ios/native-checks.v build-host-page-size` builds its fixture. Two host
ASan/UBSan runs and the ARM64 Vinix suite pass for native comparison, null/dead/
unknown port names, dirty upper argument bits, guarded aligned and unaligned
outputs, adjacent canaries, cache changes and aliasing, eight concurrent callers,
import scoping and two system-data lifecycles. Explicit byte-copy casts avoid
typed alignment checks; the initial sanitizer failure and its correction are
retained. Generated C review verifies the stack snapshot and exact eight-byte
copy. Unconfigured calls fail explicitly.

Measurements, joined logs, pinned inputs and five generated C/executable pairs
are retained under `build/ios/fortnite/host-page-size-checks`. The fresh IPA probe
passes `_host_page_size` and stops before entry at `_host_statistics`. Native
statistics count negotiation, port/flavor errors and output extents are retained
for the next adapter. Fortnite remains unplayable and the full iOS regression
is unpassed.

V now resolves `_mach_host_self`, `_host_statistics` and `_host_statistics64`.
The Vinix host send right has reference counts, shared namespace locking,
atomic name publication and names that survive neither last-reference removal
nor image retirement. Port type/ref queries, reference modification, deallocation,
exception arguments and wrong-type semaphore operations recognize it. Forked
children acquire a fresh host right. The Mac backend uses native host rights
and statistics calls.

The Vinix statistics subset supports `HOST_VM_INFO` through both functions and
`HOST_VM_INFO64` through the 64-bit function. Native count negotiation selects
12/14/15-word legacy revisions and 24/38/40/62-word 64-bit revisions. Short
buffers and invalid destinations/flavors return the measured errors without
changing output. A bounded `/proc/meminfo` parser rejects malformed, duplicate
and overflowing mapped fields. Output copies use the negotiated word count;
64-bit counters retain their upper words and legacy counters saturate.

Vinix lacks Darwin's active/inactive page queues. This adapter reports resident
file cache as inactive, kernel slab as wired, and remaining resident pages as
active, with bounded totals and separate compressed-storage counts. Available
Vinix page-in/page-out counters are mapped; unsupported lifetime and tagging
counters remain zero. These are approximate classifications of Vinix memory.
Other host-statistics flavors remain unsupported on Vinix.

`tests/ios/native-checks.v build-host-statistics` builds the fixture. Two host
ASan/UBSan runs and the ARM64 Vinix suite pass for guarded revision layouts,
parser failures, counter saturation, dirty upper arguments, errno/floating-point
state, eight concurrent callers, host references, fork isolation and two
lifecycles. Existing Mach thread, semaphore and exception host suites also pass
twice under ASan/UBSan. The initial host exception fixture mixed native and
synthetic task names; its failed attempt and the corrected fixture are retained.
Generated C review verifies stack buffers and no added allocation lifetime.

Native measurements, joined logs, pinned inputs and eight generated C/executable
pairs are under `build/ios/fortnite/host-statistics-checks`. The fresh IPA probe
passes all three imports and stops before entry at `_logbf`. Fortnite remains
unplayable and the full iOS regression is unpassed.

V now resolves `_logbf` with scalar float ABI and exact finite exponents.
Normal and subnormal inputs use integer bit inspection, so flush-to-zero does
not turn a nonzero input into a pole. Both signed zeros return negative infinity
and raise divide-by-zero. Infinities and NaNs use the native ARM64 floating
multiply: signaling NaNs raise invalid, payloads/signs survive normally, and
default-NaN mode produces the canonical positive NaN. Errno, rounding controls
and previously raised flags are preserved. The adapter allocates nothing and
does not call a logarithm backend.

`tests/ios/native-checks.v build-logb` builds the regression fixture. Two host
ASan/UBSan runs and the ARM64 Vinix suite pass for every finite exponent class,
both signs, subnormal boundaries, zero poles, NaN cases, four rounding modes,
all combinations of flush-to-zero/default-NaN controls, sticky flags and eight
concurrent callers. The host suite also runs these cases against native `logbf`.
Generated C and both optimized runner binaries are reviewed; LLVM confirms
single-precision special-value multiplication and the explicit zero exception.

Native references, joined logs, pinned inputs and five generated C/executable
pairs are under `build/ios/fortnite/logb-checks`. The IPA's color-packing call at
`0x10063b454` consumes the float result before `ldexpf`. The fresh probe passes
`_logbf` and stops before entry at `_mach_make_memory_entry_64`. Its call sites
and native permission/size negotiation and shared aliases are measured for the
next adapter. Fortnite remains unplayable and the full iOS regression is unpassed.

V now resolves `_mach_make_memory_entry_64`, `_vm_map` and `_vm_page_mask`.
Named entries retain independent backing descriptors, with send-right type/ref
queries, reference changes, deallocation and retired names. Exception arguments,
host statistics and wrong-type semaphore operations recognize these rights.
One namespace lock protects mappings, entries and fork cleanup. Dropping the last
right closes its descriptor and frees the entry; mapped aliases remain valid.

The current-task subset exports regions allocated or mapped by the compatibility
VM, rounds unaligned source ranges, returns the available part of a source region,
and supports restricted child entries. Shared mappings alias the same bytes.
Copy mappings take an eager backing snapshot, so later writes to either mapping
stay separate. Protection limits are checked and retained by remaps. Fixed
replacement requires a fully owned destination range; splitting and deallocation
retain the surviving backing offsets. Foreign malloc/mmap regions, cross-task
export, memory-entry flags, alignment masks, other inheritance modes and executable
anonymous mappings remain unsupported. The existing four-GiB mapping limit remains.
BSD fixed mmap, munmap and mprotect reject overlapping compatibility VM regions
with `ENOTSUP`, preventing stale ownership records; ordinary BSD regions retain
their existing behavior.

`tests/ios/native-checks.v build-memory-entry` builds the fixture. Native Mach
measurements, eight host ASan/UBSan runs and the ARM64 Vinix fixture cover region
negotiation, parent slices, reference ownership, alias/snapshot independence,
read-only replacements, split deallocation, remap protection limits, errno,
eight concurrent callers, fork and image retirement. The host runs include the
existing thread, semaphore and exception suites. Generated C review checks entry
allocation/free, descriptor cleanup, lock coverage and temporary snapshot views.
The Mac's POSIX shared-memory descriptors reject `pread`/`pwrite`; the initial
failed attempt and its mapped-view correction are retained.

Evidence and compressed generated C/executables are under
`build/ios/fortnite/memory-entry-checks`. LLVM inspection confirms the IPA's
entry calls at `0x1000b1cb8` and `0x1000b1d44`, followed by read-only copy mapping
over an allocated destination and immediate send-right removal. The fresh probe
passes these three imports and stops before entry at `_mach_msg`. Fortnite remains
unplayable and the full iOS regression is unpassed.

V now provides `_mach_msg`, receive-port allocation, same-name `MAKE_SEND` right
insertion and port destruction. The process-local transport accepts inline
`COPY_SEND`, `MOVE_SEND` and `MAKE_SEND` messages without transferred reply or
voucher rights. It has a five-message FIFO queue, a 64-KiB message limit, blocking
send/receive and millisecond timeouts. The caller's buffer is copied before a
send waits for space. Receives return the Darwin header and minimum eight-byte
trailer, including exact partial output for undersized buffers.

`MACH_RCV_LARGE` retains the message for retry and reports only fields that fit.
Ordinary oversized receives discard the message and return a header-only result.
Timed-out sends return their in-transit right: copy/make sends gain a reference,
move sends restore theirs, and the returned header permits a move-send retry.
Native measurements also show that removing a receive right wakes receivers
with `MACH_RCV_PORT_CHANGED`, while an already blocked send succeeds and discards
its message when the destination is destroyed. The adapter follows these rules.

Port type/ref queries, send/dead references, receive-right removal and last-right
cleanup share the existing namespace. Call pins keep objects alive across waits;
destruction wakes callers and frees queued packets. Pending sender copies are
tracked from allocation through enqueue or failure. Fork freezes the queues and
retires the child's inherited namespace. Image teardown checks for active calls
before freeing packets and native synchronization objects. Host-statistics and
exception RPCs to these user ports reject unsupported delivery explicitly.
Cross-process transport, complex descriptors, transferred reply/voucher
rights, alternate trailers and kernel exception delivery remain
unsupported. Only the measured message options are accepted.

`tests/ios/native-checks.v build-mach-message` builds the fixture. Ten host
ASan/UBSan runs include native Mach comparison and the existing memory-entry,
thread, semaphore and exception suites. The ARM64 Vinix fixture covers guarded
output extents, queue pressure, retry ownership, FIFO payloads, blocking sends,
eight receivers, retirement, errno, fork with blocked send/receive and queued data,
import scope and two image lifecycles. Generated C review checks packet and port
ownership, reference credits, lock order, stack copies and teardown order.

Native probes, retained failed assumptions, joined logs, pinned inputs and
compressed generated C/executables are under `build/ios/fortnite/mach-message-checks`.
LLVM inspection confirms Fortnite's receive loop at `0x1000b416c`, stop send at
`0x1000b46fc` and reply forwarding call at `0x1000b4894`. The fresh import probe
passes `_mach_msg` and stops before entry at `_mach_port_move_member`. Fortnite
remains unplayable and the full iOS regression is unpassed.

The V adapter now also allocates port sets and implements
`mach_port_move_member`. Fortnite's constructor attaches two receive ports to
one set before starting the receive loop above. Membership moves preserve the
member queues; removing a member from no set returns `KERN_NOT_IN_SET`.
Set receives rotate between ready member queues while retaining FIFO order
within each port. Successful receives and `MACH_RCV_LARGE_IDENTITY` identify
the member port. An oversized `MACH_RCV_LARGE` receive retains the packet but
still rotates that member behind the other ready queues, as measured on macOS.
Direct receives remain available while a port belongs to a set.

Port-set type/ref queries, removal through destroy/mod-refs/deallocate and
blocked receiver wakeups follow native measurements. Set destruction preserves
the member ports and queued messages. Namespace locking, call pins and queue
guards protect selection against concurrent direct receives, membership changes
and destruction. A sender releases its queue guard before notifying the set;
the receiver holds the set guard across the empty scan and condition wait.
Membership adds no allocation. Fork and image retirement use the existing
queue ownership and synchronization cleanup. Multiple simultaneous memberships
through `mach_port_insert_member`, transferred rights and cross-process message
transport remain unsupported.

`tests/ios/native-checks.v build-mach-port-set` builds the port-set fixture.
Native comparisons cover rights, error precedence, ready queue selection,
oversized retry and guarded output extents. Sanitizer and ARM64 checks exercise
blocked receivers, sender pressure, membership changes, destruction, errno,
fork and image retirement. Evidence is retained under
`build/ios/fortnite/mach-port-set-checks`. The fresh Fortnite probe passes
`_mach_port_move_member` and stops before entry at
`_mach_port_request_notification`. Fortnite remains unplayable; the full iOS
regression is unpassed.

The V adapter now implements `mach_port_request_notification` for
`MACH_NOTIFY_NO_SENDERS` (70), the request made by Fortnite at `0x1000b3f88`.
Native measurements establish the `sync` gate, make-send count, one-shot delivery,
replacement/cancellation and the 36-byte notification ABI. Ordinary messages
retain their destination send rights while queued, so the notification fires
after the last such message is received or discarded. A retained oversized
receive keeps that right. Timed-out sends restore their user reference and
retain the measured make-send count.

Each request reserves its send-once right and notification packet. Delivery
allocates nothing and bypasses the ordinary queue limit, as Darwin does.
Replacement and cancellation return owned send-once names; deallocation or
source destruction sends `MACH_NOTIFY_SEND_ONCE` (71). Returned rights support
type/ref queries, removal, reuse with `MOVE_SEND_ONCE`, dead-name conversion
and inline send-once messages. Dead targets are retained only while a right
still needs their state. Namespace locking, target references and atomic
in-transit counts preserve ownership through concurrent receives and ref drops.
Fork and image teardown retire internal/exported rights before their targets.
Other notification families and send-right notification descriptors explicitly
return `KERN_NOT_SUPPORTED`; transferred reply rights and complex descriptors
remain unsupported.

`tests/ios/native-checks.v build-mach-notification` builds the fixture.
The public driver now routes registered individual build commands through the
fixture table and rejects unknown fixture names.
Fourteen host ASan/UBSan runs and the ARM64 Vinix fixture cover native ABI
comparisons, guarded output, queue ownership, retry/discard, saturation, full
queues, dead targets, eight set receivers, concurrent ref drops, errno, fork
and two image lifecycles. Generated C review checks the reserved packet and
target ownership, atomic counts, lock order and cleanup. Evidence is under
`build/ios/fortnite/mach-notification-checks`. The fresh Fortnite probe passes
`_mach_port_request_notification` and stops before entry at `_madvise`.
Fortnite remains unplayable and the full iOS regression is unpassed.

The V `madvise` adapter now translates Darwin's advice values and outward page
rounding to Vinix's Linux ABI. It supports normal/random/sequential/will-need
hints, non-destructive `MADV_DONTNEED`, private anonymous `MADV_FREE` and
`MADV_FREE_REUSABLE`, and `MADV_FREE_REUSE`. Free/reusable eagerly discard the
permitted contents, so reuse cannot leave a lazy-free page eligible for later
reclamation. Whole-range mapping, protection and backing validation precedes
discard; holes, overflow and failures preserve the measured errno behavior for
the supported profile. Shared Mach aliases and file mappings explicitly reject
free/reusable with `ENOTSUP` rather than losing their shared backing. Wired-page
zeroing, reusable-state queries, pageout and zero-page advice remain unsupported
on Vinix. macOS validation uses the native implementation.

`tests/ios/native-checks.v build-madvise` builds the fixture. Native measurements,
four host ASan/UBSan runs and the ARM64 Vinix fixture cover unaligned/empty
ranges, overflow, holes, protection, contents after reuse, actual eager discard,
shared aliases, file guards, long mapping names, errno and two image lifetimes.
The existing Mach memory-entry regression also passes under the host sanitizers.
Generated C review checks the scalar ABI, bounded stack parsing, complete-range
validation, namespace locking and absence of retained allocations. Evidence is
under `build/ios/fortnite/madvise-checks`. The fresh Fortnite probe passes
`_madvise` and stops before entry at `_malloc_create_zone`, called with a 4 MiB
initial size at `0x10489c068`. Fortnite remains unplayable; the full iOS regression
is unpassed.

The V allocator now implements Fortnite's seven malloc-zone imports: creation,
destruction, allocation, realloc, free, exact pointer lookup and consistency
checks. Zones expose the version-5 ARM64 callback table, including size, calloc,
page-aligned allocation and memalign. Their introspection table supplies size
rounding, consistency checks, locking and statistics; remote enumeration and
debug printing/logging remain unsupported. Creation accepts the measured zero
flags; the initial size is an allocation hint.

A hash table and per-zone lists track payload ownership without reading guest
memory or adding private headers to returned blocks. Imported malloc, calloc,
realloc, strdup and posix_memalign use an embedded default zone. Global free and
realloc recognize custom-zone blocks, and malloc_size reports their tracked
capacity. Failed resize preserves the original bytes and ownership. Zero-sized
allocations and realloc return usable storage. NSData and CMBlockBuffer disposal
remove tracked ownership before freeing transferred guest buffers. Zone lookup
covers allocations through these adapters; allocations made inside native
bridge/C++ libraries are outside that registry, while existing native-pointer
free/realloc/size operations retain their native fallback.

The namespace gate serializes heap metadata and already spans fork, so child
allocations remain independently usable. Zone destruction reclaims outstanding
blocks; image retirement also releases the default heap and zone headers.
`tests/ios/native-checks.v build-malloc-zone` builds the fixture. Ten host
ASan/UBSan runs cover the allocator, libSystem, Mach memory entries, block
buffers and Objective-C storage. Native allocator measurements run separately
from ASan's allocator interposition; the existing native class-lifetime fixture
is rebuilt for this cohort. The ARM64 fixture covers callback layout, ownership,
alignment, failure, transferred buffers, eight callers, fork and two image
lifetimes. Generated C review checks allocation/free paths and pointer stability.
Evidence is under `build/ios/fortnite/malloc-zone-checks`. Fortnite now passes
the zone imports and stops before entry at `_mkstemp`, called at `0x1000a960c`.
Fortnite remains unplayable; the full iOS regression is unpassed.

`_mkstemp` is now implemented in V. Native macOS measurements and LLVM
disassembly establish the BSD template rules: replace all trailing `X`s,
accept shorter runs and literal names, reject an empty template, and check
the 1,024-byte path limit before mutation. OS entropy chooses the initial
alphanumeric suffix; collision retries enumerate the name space and terminate
with `EEXIST`. Creation uses `O_RDWR | O_CREAT | O_EXCL`, mode `0600` filtered
by umask, and a descriptor without close-on-exec. Existing files and final
symlinks remain untouched. Successful retries can retain `EEXIST` in errno,
matching the measured native behavior.

Suffix and retry state stay on the stack. The Vinix adapter bounds filename
components to 255 bytes. A parent-symlink fallback preserves exclusive creation
and closes its temporary directory descriptor. The existing fork gate
serializes adapter calls: concurrent creates otherwise lose directory entries
in the frozen validation kernel. The fixture retains all 400 files until its
eight callers join, checking both uniqueness and contents.

`tests/ios/native-checks.v build-mkstemp` builds the fixture. Six host ASan/UBSan
runs cover temporary files, file timestamps and file locking; the ARM64 fixture
also passes. Checks include guarded template mutation, empty/literal/short
templates, path and component boundaries, modes, flags, exhausted collisions,
symlinks, unlink lifetime, eight callers, a heap-owned Fortnite-style template
and two image lifetimes. Generated C review checks the scalar ABI, stack state,
locking, error paths and descriptor cleanup. Evidence is under
`build/ios/fortnite/mkstemp-checks`. The fresh Fortnite probe clears `_mkstemp`
and stops before entry at `_nextafterf`. Fortnite remains unplayable; the full
iOS regression is unpassed.

`_nextafterf` now uses a V adapter measured against this Mac's ARM64 libSystem.
Finite values step by one float representation; equal comparisons return the
target, preserving its signed-zero representation. Native float comparisons
retain flush-to-zero and input-denormal behavior. A float addition supplies
NaN payload/signaling priority and default-NaN behavior. Explicit volatile
floating operations raise the measured underflow/overflow exceptions without
being optimized away, including the flush-to-zero underflow policy. The
adapter preserves errno, rounding/control bits and existing exception flags;
its ordinary path allocates nothing.

`tests/ios/native-checks.v build-nextafter` builds the fixture. Native reference
digests cover 3,312 input pairs across all normal exponents, subnormal/zero
boundaries, infinities, NaN combinations and deterministic random samples.
The 64 profiles combine four rounding modes, flush-to-zero/default-NaN controls
and four sticky-flag presets. Six host ASan/UBSan runs cover this adapter,
logbf and libSystem; the new host fixture runs with optimization. The ARM64
fixture also passes, including eight callers and two image lifetimes.
Generated C and optimized ARM64 disassembly review confirm the scalar float
ABI, exception instructions and absence of direct control/status-register
writes. Evidence is under `build/ios/fortnite/nextafter-checks`. The fresh
Fortnite probe clears `_nextafterf` and stops before entry at
`_os_unfair_lock_lock`. Fortnite remains unplayable; the full iOS regression
is unpassed.

The unfair-lock family now uses the caller's aligned, zero-initialized
four-byte word, with native thread ownership and sequentially consistent V
atomics. Lock, try-lock, unlock, owner assertions and the flagged lock entry
are exported. Contention parks on a private futex on Vinix or the measured
native address-wait API on macOS. Unlock publishes zero and wakes one waiter;
interrupted waits and changed values retry acquisition. No per-lock native
mutex, address registry or heap allocation is needed. The macOS
`pthread_self` declaration now matches the native pointer return type and
the current V library; Linux retains its integer handle declaration.

Native checks confirm ownership, nonrecursive misuse, bool try-lock ABI,
errno preservation and flags zero/`0x40000` (adaptive spinning). The adaptive
flag uses the blocking path; priority inheritance and owner-death recovery
are unsupported. Locks remain process-private and address-stable. Unknown
flags, unaligned/null words, recursive acquisition and non-owner unlocks fail
explicitly. Fork preserves inherited lock words and obtains fresh native
thread identities in the child.

`tests/ios/native-checks.v build-unfair-lock` builds the fixture. Six host
ASan/UBSan runs cover unfair locks, atomic queues and libSystem, with the lock
fixture optimized. The ARM64 fixture also passes: guarded word boundaries,
errno, blocked/spurious wakeups, protected-data publication, eight callers,
fork behavior, isolated misuse rejection and two runtime lifetimes. Generated
C and optimized ARM64 review check the four-byte atomics, stack CAS expected
value, native identities, blocking paths and absence of lock-path allocation.
Seven generated-C/executable pairs and joined validation evidence are retained
under `build/ios/fortnite/unfair-lock-checks`. The interrupted RAM-backed
attempt had no persisted results; the complete validation was rebuilt in
persistent storage. The fresh Fortnite probe clears the unfair-lock imports
and stops before entry at `_pause`, called at `0x104862d48`. Fortnite remains
unplayable; the full iOS regression is unpassed.

`_pause` now calls native libc through a V adapter with an int32 return value
and Darwin errno translation. The calling thread keeps its signal mask and
sleeps until a caught signal makes the call return `-1`/`EINTR`, including
handlers installed with `SA_RESTART`. Ignored and blocked signals leave the
wait asleep. The adapter holds no runtime lock, changes no dispositions and
allocates no storage, so the existing signal bridge can deliver callbacks.

`tests/ios/native-checks.v build-pause` builds the fixture. Six host
ASan/UBSan runs cover pause, signal delivery and libSystem; the optimized pause
fixture also runs eight native Mac reference profiles. The ARM64 fixture
passes ignored/blocked/caught delivery, pending signals, mask preservation,
eight callers, fork and two runtime lifetimes. Generated C and optimized
ARM64 review verify the native call, return ABI and errno path. Seven
generated-C/executable pairs and joined probe/audit evidence are retained
under `build/ios/fortnite/pause-checks`. The fresh Fortnite probe clears
`_pause` and stops before entry at `_proc_pid_rusage`. Its actual consumer at
`0x1005a77a8` requests flavor 5 for the current process and reads the
physical-footprint field. Fortnite remains unplayable; the full iOS regression
is unpassed.

`_proc_pid_rusage` now implements flavors 0 through 6 with measured record
sizes 96, 144, 160, 232, 296, 304 and 464 bytes. The footprint field is at byte
72. macOS supplies native process records; their Mach tick fields are scaled
to the runner's nanosecond clock/timebase while byte, energy and instruction
fields keep their native units. Native probes verify error ordering, unchanged
failure buffers, errno preservation, child queries, mapped-memory changes and
the CPU time conversion against `getrusage`.

The Linux subset queries the calling process. CPU and child times come from
`getrusage`; process start and RSS come from `/proc/self/stat`, with a statm
fallback for older kernels. Wired/swap and I/O values use available status/io
counters. The footprint is an explicit Linux approximation: RSS plus swapped
bytes. Its lifetime maximum uses native peak RSS, bounded below by the current
footprint. UUID, Darwin QoS, wakeup, hardware energy/cycle and unavailable
interval counters remain zero. Other live PIDs return `ENOTSUP`; invalid PID,
flavor and null-buffer validation follow the measured native ordering.

Each proc record uses one bounded read: Vinix regenerates text per read, so an
EOF probe could append a changed snapshot's suffix. The atomic RSS field also
avoids statm's temporary zero result when its mapping walk cannot acquire the
page-map lock. These cases were found with concurrent ARM64 queries. Parsers
and snapshots stay on the stack; descriptors close on every path, and output
is copied only after a successful complete query. Unavailable required
counters fail instead of reporting a successful zero footprint.

`tests/ios/native-checks.v build-proc-rusage` builds the fixture. Six host
ASan/UBSan runs cover resource usage, system queries and libSystem, with the
new fixture optimized. The ARM64 fixture passes guarded/unaligned layouts,
native error order, real CPU/memory changes, malformed records, eight callers,
descriptor reuse, fork and two runtime lifetimes. Native measurements, failed
concurrency diagnostics and final evidence are retained separately under
`build/ios/fortnite/proc-rusage-checks`.

Seven final generated-C/executable pairs, optimized ARM64 call-path review and
fresh probe/audit results are retained there. The probe clears
`_proc_pid_rusage` and stops before entry at `_raise`. Fortnite remains
unplayable; the full iOS regression is unpassed.

`_raise` now uses native thread-directed signal delivery with the existing
Darwin signal-number mapping. Native macOS measurements confirm signal zero,
`-1/EINVAL` for invalid signals, synchronous delivery on the calling thread,
and preservation of errno changes made by a caught handler. The adapter
retains the calling thread's mask, leaves blocked signals pending and allows
nested raises from callbacks without a runtime lock or allocation. Linux
continues to reject Darwin-only SIGEMT/SIGINFO with `ENOTSUP`.

`tests/ios/native-checks.v build-raise` builds the fixture. Six host ASan/UBSan
runs cover raise, pause and signal-registry regressions; the raise fixture is
optimized and compares eight native macOS profiles. ARM64 checks cover
zero/invalid/ignored signals, handler errno, masks/pending delivery, nested
callbacks, eight callers, fatal ABRT/BUS/SYS/KILL fork children and two runtime
lifetimes. The fixture restores sanitizer-owned fault handlers using complete
native disposition records. Evidence, seven generated-C/executable pairs and
optimized ARM64 call-path review are retained under
`build/ios/fortnite/raise-checks`.

The fresh probe clears `_raise` and stops before entry at `_setrlimit`.
Fortnite remains unplayable; the full iOS regression is unpassed.

`_setrlimit` now accepts Darwin's 16-byte limit record. macOS forwards to the
native API. Linux maps the nine Darwin resources to native CPU, file-size,
data, stack, core, address-space, locked-memory, process-count and descriptor
limits, strips the strict POSIX resource flag, and translates Darwin infinity
(`INT64_MAX`) to Linux infinity (`UINT64_MAX`). It copies unaligned inputs to
the stack without changing caller bytes. Native ceilings, permissions and
enforcement remain authoritative; the adapter adds no per-image limit cache.
Linux rejects values above Darwin's canonical infinity with `ENOTSUP`; that
range includes a collision with Linux's infinity sentinel. Native measurements
verify the null-pointer error priority, invalid resources, soft/hard ordering
and success errno preservation.

The actual Fortnite call at `0x10062777c` requests
`NOFILE={10240, infinity}`, using the literal at `0x10d3220b0`. The fixture
compares this request with the native backend, including real permission
failures. It also checks guarded/unaligned inputs, all nine resource mappings,
descriptor exhaustion at a lowered soft limit, hard-limit permissions, fork
inheritance, unchanged parent limits, eight callers and two runtime lifetimes.

`tests/ios/native-checks.v build-setrlimit` builds the fixture. Six host
ASan/UBSan runs cover resource limits, process resource usage and raise; the
new fixture is optimized and compares four native macOS profiles. The ARM64
fixture passes. Native probes, actual IPA evidence, seven final generated-C/
executable pairs and optimized ARM64 call-path review are retained under
`build/ios/fortnite/setrlimit-checks`.

The fresh probe clears `_setrlimit` and stops before entry at `_sigaltstack`.
Fortnite remains unplayable; the full iOS regression is unpassed.

`_sigaltstack` now translates Darwin's 24-byte `{sp, size, flags}` record to
the native layout and maps Darwin `SS_DISABLE=4`. Native macOS probes establish
the 32 KiB minimum even for disable requests, size-error priority, old-record
writes before flag/on-stack errors, and old-before-new behavior for aliased
records. The Linux adapter reproduces these cases, including the distinct
on-stack enable/disable errors. macOS forwards to its native API.

Darwin keeps the last pointer/size while disabled; Linux clears them. Two
native TSD slots, reserved once before bridge callbacks are enabled, retain
only those scalar values per thread. They allocate no stack storage and use
no registry lock on the callback path. Fork-child handling clears the history
to match the measured native fork path; the child can install its own stack.
The signal bridge now accepts `SA_ONSTACK` with the existing one-argument,
restart and nodefer handlers. Stack mappings remain caller-owned: restore or
disable native delivery before freeing them.

`tests/ios/native-checks.v build-sigaltstack` builds the fixture. Six host
ASan/UBSan runs cover alternate stacks, signal-registry and raise regressions;
the optimized new fixture compares eight native macOS profiles. ARM64 checks
pass guarded/unaligned records, output/error/alias ordering, disabled history,
actual callback frame addresses inside guarded stack mappings, eight threads,
fork reset/reinstallation, restoration before unmap and two runtime lifetimes.

Evidence under `build/ios/fortnite/sigaltstack-checks` includes native probes,
the retired initial fork diagnostic, seven final generated-C/executable pairs,
native TSD and optimized ARM64 call-path review, and fresh probe/audit results.
The probe clears `_sigaltstack` and stops before entry at `_swscanf`.
Fortnite remains unplayable; the full iOS regression is unpassed.

`_swscanf` and `_vswscanf` now bridge Darwin ARM64's anonymous pointer slots
to native wide scanning. macOS forwards the native `va_list`; Linux builds
the native AAPCS64 record with empty register ranges. Both use four-byte
wide characters. The V adapter validates the complete input in the current
locale before writing outputs, preserves Darwin's match-failure `errno`, and
maps encoding errors to Darwin `EILSEQ` (92). It rewrites eight-byte Darwin
long-double conversions and narrow `h` character modifiers in one temporary
format copy, freed before return. The game's common formats borrow their
original storage without allocating.

All fifteen fixed formats recovered from the actual IPA are checked,
including suppressed fields, short version/build components, 64-bit
addresses, bounded wide strings and five output pointers. Additional native
comparisons cover scalar widths, floats, positional arguments, character
sets, counts, C/UTF-8 locale behavior and unchanged input/format/argument
storage. Full Darwin scanf conformance outside these fixtures remains
unfinished, including libc edge behavior for range character sets and
incomplete floating exponents.

`tests/ios/native-checks.v build-swscanf` builds the fixture. Six host
ASan/UBSan runs cover wide scanning, libSystem and NSLogv; the new fixture
also passes in the ARM64 guest with protected input, format, argument and
output boundaries, a real Darwin variadic caller, eight concurrent workers
and two runtime lifetimes. Generated C and optimized ARM64 paths were
reviewed for the ABI, format ownership and unintended allocations.

Evidence under `build/ios/fortnite/swscanf-checks` retains native measurements,
the initial errno/character-modifier diagnostics, seven generated-C/executable
pairs and fresh probe/audit results. The probe clears `_swscanf` and stops
before entry at `_task_get_exception_ports`. Fortnite remains unplayable;
the full iOS regression is unpassed.

`_task_get_exception_ports` now queries the current task's exception actions.
macOS maps the compatibility self-task name to the native task and forwards
the query, including inherited handler ports and their caller-owned send
rights. Linux reports its initial unset actions: a nonzero mask returns one
group containing the requested bits, a null handler, zero behavior and zero
flavor; a zero mask returns no groups. Mach handler installation and kernel
fault delivery remain unsupported on Vinix.

Native measurements confirm that the count is output-only, even when its
incoming value is zero or uninitialized. The V adapter accepts exception
bits 1 through 13, validates destination kinds before touching output,
preserves `errno`, and copies masks, count, handlers, behaviors and flavors
in native order with exact four-byte writes. Invalid destinations and masks
leave all outputs unchanged. Compatibility receive queues reject typed MIG
queries with `KERN_NOT_SUPPORTED`.

`tests/ios/native-checks.v build-task-exception-ports` builds the fixture.
Six host ASan/UBSan runs pass current-task queries and Mach exception/message
regressions; eight native profiles compare live kernel inventories while
retaining and releasing every returned send right. The optimized ARM64
fixture passes unset-action grouping, arbitrary incoming counts, all output
extents, guard pages, unaligned and overlapping outputs, namespace errors,
eight concurrent workers, fork and two runtime lifetimes.

Native characterization, seven generated-C/executable pairs, optimized ARM64
and allocation review, and fresh probe/audit evidence are retained under
`build/ios/fortnite/task-exception-ports-checks`. The probe clears
`_task_get_exception_ports` and stops before entry at `_task_info`. Fortnite
remains unplayable; the full iOS regression is unpassed.

`_task_info` now supports the current task's `MACH_TASK_BASIC_INFO` (20)
and `TASK_VM_INFO` (22) memory records on Vinix. macOS maps the compatibility
self-task name and forwards queries to the native API. Linux samples live
RSS and the native resident high-water mark, streams the process's mapping
snapshot for virtual size and region count, and reports RSS plus swap as
physical footprint, matching the existing process-usage adapter. Descriptors
close on every path; the V snapshot and record packing use stack storage.

Native measurements establish a twelve-word basic record and VM revisions
of 36, 38, 42, 84, 86, 87, 89 and 93 four-byte words. Short counts and
unsupported Linux flavors return `KERN_INVALID_ARGUMENT`; failed snapshots
return `KERN_FAILURE`, with caller outputs unchanged. The adapter reads the
input count before resolving the destination, releases the namespace lock
before collecting data or writing outputs, preserves `errno`, and copies
the record before its count, including unaligned and overlapping spans.

Darwin-only tagged/compressor ledgers, map bounds, remaining task limit and
terminated-thread CPU times remain unavailable on Linux and stay zero.
The basic record describes the runner's timesharing policy and zero Mach
task suspension count. Other task-info flavors and foreign Linux tasks are
unsupported; this adapter does not install exception handlers or deliver
kernel faults.

`tests/ios/native-checks.v build-task-info` builds the fixture. Six host
ASan/UBSan runs pass task-info, task-exception-port and process-usage checks;
eight native profiles compare counts, memory fields, page size and output
extents. The optimized ARM64 fixture passes every count through 105, VM
revision boundaries, guarded/unaligned/aliased writes, port kinds, live
32 MiB allocation and persistent peak RSS, eight workers, fork and two
runtime lifetimes. Native caller-memory fault measurements, seven
generated-C/executable pairs and fresh probe/audit evidence are retained in
`build/ios/fortnite/task-info-checks`.

The probe clears `_task_info` and stops before entry at
`_task_swap_exception_ports`. Fortnite remains unplayable; the full iOS
regression is unpassed.

`_task_swap_exception_ports` now forwards native Mach swaps on macOS,
including caller-owned send references returned for previous handlers.
Vinix supports valid empty-mask requests and clearing already-unset actions
to a null handler, zero behavior and zero flavor. Otherwise valid nonempty
requests that install a handler or change policy return `KERN_NOT_SUPPORTED`,
with all outputs unchanged. No handler state or successful fault delivery
is fabricated.

The ten-argument V adapter resolves the destination and `COPY_SEND` right
before checking the receiving object and scalar arguments. Kernel-object
ports cannot become handlers, even for an empty mask: native measurements
establish `KERN_INVALID_RIGHT` after mask/behavior validation and before
thread-flavor validation. Compatibility receive queues continue to reject
typed MIG transport. The adapter preserves `errno`, never reads the incoming
output count, releases the namespace lock before native calls or caller
writes, and copies masks, count, handlers, behaviors and flavors in native
order with exact four-byte extents.

`tests/ios/native-checks.v build-task-swap-exception-ports` builds the fixture.
Six host ASan/UBSan runs cover swap, query and exception-RPC regressions;
eight native profiles compare old-action grouping and release every returned
send reference. The optimized ARM64 fixture checks both stack-passed output
pointers, unaligned and overlapping arrays/counts, guard pages, output-only
counts, port kinds and error precedence, unchanged references after refused
installation, eight workers, fork and two runtime lifetimes.

Native measurements, seven generated-C/executable pairs, optimized ARM64
review and fresh probe/audit results are retained under
`build/ios/fortnite/task-swap-exception-ports-checks`. The probe clears
`_task_swap_exception_ports` and stops before entry at `_task_threads`.
Fortnite remains unplayable; the full iOS regression is unpassed.

`_task_threads` now returns an independently owned VM array of 32-bit thread
port names and one send reference per listed thread. On macOS it enumerates
native Mach threads and moves the array into the runner's VM registry while
retaining the returned rights. On Vinix it snapshots the current-task thread
namespace under its lock, including entry/callback threads, Darwin pthreads,
NSThreads and dispatch/network workers. Foreign native pthreads that never
enter the adapter and foreign Linux tasks remain outside this support.

The count is output-only. The V adapter preserves `errno` and copies the
eight-byte pointer before the four-byte count after unlocking, including
unaligned and overlapping outputs. Invalid destinations and wrong port kinds
leave outputs unchanged. Array storage can be released with `vm_deallocate`
independently of its send rights; held rights become dead-name references
after exit. Enumeration excludes retired threads, can recreate a live send
right with zero references, and preserves saturated reference counts. Existing
robust-mutex lifetimes keep a thread visible through native TLS destructors.

`tests/ios/native-checks.v build-task-threads` builds the fixture. Six host
ASan/UBSan runs cover enumeration, thread namespace and VM-entry regressions.
The optimized ARM64 fixture passes exact guarded/unaligned/aliased outputs,
independent VM/right ownership, eight concurrent workers, retired names,
TLS-destructor lifetime, zero/saturated references, dispatch workers, fork and
two runtime lifetimes. Native stress measurements also observed 331 null
entries among 8,041 entries during thread-exit races; native copyout is
preserved, including these null entries.

Native measurements, seven generated-C/executable pairs, optimized ARM64
review and fresh probe/audit results are retained under
`build/ios/fortnite/task-threads-checks`, with earlier fixture diagnostics kept
separately. The probe clears `_task_threads` and stops before entry at
`_thread_get_exception_ports`. Thread state, suspension and exception-handler
delivery remain unsupported. Fortnite remains unplayable; the full iOS
regression is unpassed.

`_thread_get_exception_ports` now forwards live native queries on macOS,
including caller-owned send references for installed handlers. Vinix queries
the initial state of live threads in its Mach namespace: no exception-action
table, zero returned groups and untouched output arrays for every valid mask.
Native measurements distinguish this absent table from an explicitly cleared
table, which returns null-action groups. Thread handlers are not inherited
from the creating thread; the query does not substitute task actions.

The V adapter checks the destination before the mask, preserves `errno`,
releases the namespace lock before native calls or caller writes, and writes
exactly the four-byte output-only count on Vinix. Invalid masks, missing send
rights and retired names leave all outputs unchanged. Wrong kernel-object
kinds return `KERN_INVALID_ARGUMENT`; compatibility receive queues with send
rights return `KERN_NOT_SUPPORTED`. Thread handler installation and kernel
exception delivery remain unsupported.

`tests/ios/native-checks.v build-thread-exception-ports` builds the fixture.
Six host ASan/UBSan runs pass query, task-query and exception-RPC regressions;
eight native profiles compare absent/allocated tables, two distinct handler
groups, overlapping output order and balanced returned send references. The
optimized ARM64 fixture passes guarded, unaligned and aliased counts, unused
inaccessible arrays, dirty upper argument bits, mask/destination precedence,
eight live and retired threads, unchanged send references, fork and two
runtime lifetimes. Generated C and optimized ARM64 review confirm no adapter
allocation and only the count write after unlocking on Vinix.

Native measurements, seven generated-C/executable pairs and fresh
probe/audit evidence are retained in
`build/ios/fortnite/thread-exception-ports-checks`. The probe clears
`_thread_get_exception_ports` and stops before entry at `_thread_get_state`.
Fortnite remains unplayable; the full iOS regression is unpassed.

`_thread_get_state` now forwards live native Mach queries on macOS. On ARM64
Vinix it captures the executing thread's NEON registers `q0` through `q31`,
FPSR and FPCR with V inline assembly for `ARM_NEON_STATE64` (flavor 17).
The 528-byte record includes eight zeroed alignment bytes and returns a count
of 132 four-byte words. General registers, debug and exception state, page-in
counters, SME state and remote-thread snapshots return
`KERN_NOT_SUPPORTED`; no register record is manufactured for those requests.

Native measurements establish the accepted flavors and minimum counts, and
show that the four-byte input count is read before destination validation.
The adapter preserves `errno`, checks flavor/count after the destination,
releases the namespace lock before native queries or caller writes, and
copies a successful record before its four-byte count. Invalid flavors,
short counts, missing rights, wrong object kinds and retired names preserve
the caller's outputs. The capture uses stack storage and changes neither
signal dispositions nor signal masks.

`tests/ios/native-checks.v build-thread-state` builds the fixture. Six host
ASan/UBSan runs pass state-query, thread-exception-query and exception-RPC
regressions. Twelve native profiles compare flavor/count/error behavior and
exact records from a suspended native thread. The optimized ARM64 guest
fixture passes seeded hardware-register capture, guarded/unaligned/aliased
outputs, dirty upper argument bits, eight concurrent and retired workers,
fork and two runtime lifetimes. Generated C and ARM64 disassembly confirm
stack-only copyout and the complete register-store sequence.

Native measurements, seven generated-C/executable pairs and fresh probe/audit
evidence are retained in `build/ios/fortnite/thread-state-checks`. The probe
clears `_thread_get_state` and stops before entry at `_thread_resume`.
Fortnite's inspected call sites request general registers, including unified
flavor 1; those requests still return unsupported on Vinix. Suspension,
register mutation and kernel exception delivery remain unsupported. Fortnite
remains unplayable; the full iOS regression is unpassed.

`_thread_resume` now forwards native Mach resumes on macOS, including real
nested suspension counts. Native measurements show a count of two becoming
one and then zero; another resume returns `KERN_FAILURE`. Vinix has no
individual-thread suspension backend, so its live Mach threads have zero
user suspension counts and return that same underflow error. The adapter
does not report a successful resume, alter a count or send process-wide
`SIGCONT` on Vinix.

The V adapter validates the destination under the shared namespace lock,
unlocks before native calls, and preserves `errno` and Mach references.
Wrong kernel-object kinds return `KERN_INVALID_ARGUMENT`, missing send rights
and retired names return `MACH_SEND_INVALID_DEST`, and compatibility receive
queues with send rights return `KERN_NOT_SUPPORTED`.

`tests/ios/native-checks.v build-thread-resume` builds the fixture. It covers
native nested suspension, repeated self/remote underflow, dirty upper argument
bits, eight concurrent and retired workers, unchanged send/dead references,
right removal and reacquisition, fork and two runtime lifetimes.

Six host ASan/UBSan runs pass resume, thread-state and thread-exception-port
regressions; twelve native profiles include real suspension-count checks.
The optimized ARM64 fixture passes with separate start/finish worker gates.
The initial shared-gate fixture could let a fast worker consume another
worker's release token; its stalled guest run and original artifacts are
retained separately under `diagnostics/first-concurrency-gate`.

Native measurements, seven final generated-C/executable pairs and fresh
probe/audit evidence are retained in
`build/ios/fortnite/thread-resume-checks`. Generated C and ARM64 review confirm
no adapter allocation, right mutation, remote pthread dereference or signal
delivery. The probe clears `_thread_resume` and stops before entry at
`_thread_suspend`. Per-thread suspension, general/remote register capture,
register mutation and kernel exception delivery remain unsupported on Vinix.
Fortnite remains unplayable; the full iOS regression is unpassed.

`_thread_suspend` now forwards real Mach suspension on macOS. Native
measurements verify nested counts from zero to one to two, balanced resumes,
and self-suspension observed and resumed by another thread. The V adapter
releases the shared namespace lock before suspending, so an adapter thread
can acquire it to resume a suspended caller.

Vinix returns `KERN_NOT_SUPPORTED` for live thread destinations because it
has no individual-thread suspension backend. It does not stop the process,
install a signal handler, change a suspension count or claim success.
Subsequent resume calls retain the zero-count `KERN_FAILURE` behavior.
Destination errors distinguish wrong kernel-object kinds, missing send
rights, retired names and compatibility receive queues. `errno` and Mach
references are preserved.

`tests/ios/native-checks.v build-thread-suspend` builds the fixture. It covers
native nested/self suspension, balanced resumes, eight concurrent and retired
workers, unchanged send/dead references, right removal and reacquisition,
dirty upper argument bits, fork and two runtime lifetimes.

Six host ASan/UBSan runs pass suspension, resume and state-query regressions;
twelve native profiles include nested counts and a different adapter thread
resuming the suspended caller. The optimized ARM64 fixture passes explicit
unsupported results without changing subsequent resume behavior. Generated C
and ARM64 review confirm no adapter allocation, right mutation, remote pthread
dereference or signal delivery.

Native measurements, seven generated-C/executable pairs and fresh probe/audit
evidence are retained in `build/ios/fortnite/thread-suspend-checks`. The probe
clears `_thread_suspend` and stops before entry at
`_thread_swap_exception_ports`. Individual-thread suspension, general/remote
register capture, register mutation and kernel exception delivery remain
unsupported on Vinix. Fortnite remains unplayable; the full iOS regression is
unpassed.

`_thread_swap_exception_ports` now forwards native swaps and their returned
COPY_SEND references on macOS. Vinix supports zero-mask swaps and exact
null/zero clears of unset actions. Native measurements show that a successful
swap allocates an empty action table even with a zero mask. A flag on the
existing Mach thread record tracks that state without another allocation.
Subsequent thread queries return one null-action group for a nonzero valid
mask; a fresh thread or fork child still returns zero groups. Removing and
reacquiring send rights preserves the live thread's table state.

The V adapter refreshes retired names and validates the destination and
COPY_SEND descriptor before checking masks, behavior and ARM flavors.
It changes table state under the namespace lock, then unlocks before caller
writes or native calls. Both swaps and allocated-table queries write exactly
four bytes per output field in native masks/count/handlers/behaviors/flavors
order, including unaligned and overlapping outputs. Counts are output-only.
Handler/policy installation and kernel exception delivery remain unsupported;
rejected requests leave outputs and table state unchanged.

`tests/ios/native-checks.v build-thread-swap-exception-ports` builds the fixture.
Six host ASan/UBSan runs pass thread-swap, task-swap and thread-query
regressions; twelve native profiles compare complete records, two distinct
old handler groups and balanced returned references. The optimized ARM64
fixture passes guarded/unaligned/aliased output checks, empty-table queries,
descriptor precedence, eight concurrent and retired threads, right
reacquisition, fork and two runtime lifetimes. Generated C and ARM64 review
cover both the swap and the changed query path.

Native measurements, seven generated-C/executable pairs and fresh probe/audit
evidence are retained in
`build/ios/fortnite/thread-swap-exception-ports-checks`. The native probe's
initial fork cleanup reused the parent's task port; its diagnostic is retained
under `diagnostics/native-fork-task-port`, and the corrected probe passes.
The loader clears `_thread_swap_exception_ports` and stops before entry at
`_uname`. Fortnite remains unplayable; the full iOS regression is unpassed.

`_uname` now returns the host's system identity through Darwin's five
256-byte fields. macOS forwards the native call. Vinix translates its native
six-field, 65-byte Linux layout, omitting the domain name. It returns the
kernel's actual system, node, release, version and machine strings; it does
not substitute an iPhone model. Fortnite's caller passes a 1296-byte stack
frame at offset eight and reads the machine field at offset 1024.

Native measurements show that each field writes only its string and NUL,
leaving the remaining bytes untouched. Success preserves `errno`; invalid
destinations return `EFAULT` and may retain a written prefix. The V adapter
uses stack storage and `process_vm_writev` to preserve these boundaries and
report copyout errors without dereferencing an invalid application buffer.
It allocates no user-space heap storage.

`tests/ios/native-checks.v build-uname` builds the fixture. Six host ASan/UBSan
runs pass uname, system-query and sysctl regressions. The optimized ARM64
fixture passes full-record comparisons against native uname, untouched tails,
unaligned buffers, Fortnite's frame layout, ten guarded capacities, read-only
and invalid pointers, partial writes, thread-local errno, eight concurrent
workers, fork and two runtime lifetimes. Generated C and ARM64 review cover
both runners and the host/guest fixture.

Native measurements, seven generated-C/executable pairs and fresh probe/audit
evidence are retained in `build/ios/fortnite/uname-checks`. The loader clears
`_uname` and stops before entry at `_vm_read_overwrite`. Fortnite remains
unplayable; the full iOS regression is unpassed.

`_vm_read_overwrite` now forwards native task reads on macOS and reads the
current task's memory on Vinix. Its task argument is 32 bits; addresses,
size and the output-only count are 64 bits. Fortnite passes a stack count
pointer at `0x1000a8114`. The adapter validates the Mach destination before
memory arguments and preserves errno. Compatibility receive queues still
reject this typed RPC; Vinix has no cross-task Mach memory interface.

The Vinix path streams address/permission prefixes from `/proc/self/maps`
and uses kernel-assisted reads and writes. It accepts readable stack, heap,
ordinary mmap and compatibility-owned regions. Source bytes are captured
before destination writes, including overlap. Small snapshots stay on the
stack; larger snapshots use a temporary mapping that is released on success
and both copy failures. The descriptor closes on every exit. No mapping is
added to the compatibility VM registry and no user-space heap allocation is
retained.

Native measurements distinguish Darwin's 32 KiB kernel-buffer boundary.
Zero-length calls write a zero count without inspecting either address.
Requests through 32 KiB reject static holes/protection failures with
`KERN_INVALID_ADDRESS` and no copied prefix. Larger requests distinguish
protection failures, can write a valid destination prefix, and still leave
the count untouched on failure. Successful calls copy the eight-byte count
last, including unaligned counts and counts that alias source or destination.

`tests/ios/native-checks.v build-vm-read-overwrite` builds the fixture. Six
host ASan/UBSan runs pass VM-read, uname and memory-entry regressions. Native
matrix profiles and the optimized ARM64 fixture cover the 32 KiB boundary,
small/large snapshots, static holes, permission splits, overlap, guarded and
aliased counts, namespace errors, eight concurrent workers, fork and two
runtime lifetimes. Generated C and ARM64 review check stack storage,
descriptor closure and every temporary-mapping release path.

Seven generated-C/executable pairs, native boundary probes and fresh
probe/audit evidence are retained in
`build/ios/fortnite/vm-read-overwrite-checks`. Diagnostics preserve the initial
native function-pointer prototype error, the first guard matrix and the
fixture's corrected unaligned count read. The loader clears
`_vm_read_overwrite` and stops before entry at `_vm_region_64`. Fortnite
remains unplayable; the full iOS regression is unpassed.

`_vm_region_64` now has a seven-argument ABI bridge. macOS forwards queries
to the native task, including basic, legacy basic, top and extended records,
returned object rights and native output order. Vinix validates the Mach
destination, then streams `/proc/self/maps` bounds to distinguish end-of-map
from unavailable metadata. Native measurements show that end-of-map takes
precedence over invalid flavors and short counts. Basic/legacy/extended
records require nine words; top records require five.

Vinix returns `KERN_NOT_SUPPORTED` for valid region-metadata requests and
leaves every caller-owned buffer unchanged. Its exported map view lacks the
complete Mach wire/inheritance attributes, object statistics and Darwin
allocation tags needed for those records. Fortnite requests extended flavor
13 with nine words and examines an allocation tag; that request remains
unsupported on Vinix. No tags, object names or residency values are invented.
Lookup uses fixed stack buffers and closes its descriptor on every exit;
the bridge preserves errno and adds no heap lifetime or Mach references.

`tests/ios/native-checks.v build-vm-region-64` builds the fixture. Six host
ASan/UBSan runs pass region, read-overwrite and memory-entry regressions.
Four native profiles compare complete guarded records, count thresholds,
split protections, holes and unaligned/overlapping outputs. The optimized
ARM64 fixture checks unchanged unsupported outputs, namespace/error
precedence, bounded hex parsing, dirty upper arguments, eight concurrent
workers, fork and two runtimes. Generated C and ARM64 review cover the ABI,
descriptor cleanup and absence of Vinix output writes.

Native measurements, seven generated-C/executable pairs and fresh
probe/audit evidence are retained in
`build/ios/fortnite/vm-region-64-checks`. The link probe clears
`_vm_region_64` and stops before entry at `_CFLocaleCopyCurrent`. Fortnite
remains unplayable; the full iOS regression is unpassed.

`_CFLocaleCopyCurrent` now returns an owned, toll-free bridged `NSLocale`
reference through its no-argument C entry. It shares the runtime's cached
`NSLocale.currentLocale` snapshot, with one separate retain per caller and
one cache retain released at shutdown. Publication is protected by the
recursive runtime lock; results survive autorelease-pool drains and other
callers' releases.

On macOS the snapshot copies the native current locale's identifier and
balances both its CF owner and temporary native autorelease pool. On Vinix
it preserves the existing `LC_ALL`, `LC_MESSAGES`, then `LANG` policy,
stripping encoding/modifier suffixes; unset, `C` and `POSIX` use the existing
`en_US` compatibility default. It copies at most 1,023 identifier bytes into
its owned NSString and keeps that snapshot through the runtime lifetime.
This does not implement preference-change notifications, the ICU locale
database, `CFLocaleGetValue` or preferred-language queries.

`tests/ios/native-checks.v build-cf-locale-current` builds the fixture. Six
host ASan/UBSan runs pass current-locale, Swift fixed-locale and CF dictionary
checks. Native measurements verify cached owned references and identifier
stability after pool drains and environment changes. The optimized ARM64
fixture checks environment precedence/defaults/suffixes, long identifiers,
protected argument/x8 registers, preserved x20/x21, cold concurrent cache
publication, CF retain/release and Objective-C integration, autorelease
independence and two drained runtimes with zeroed weak references.

Native measurements, seven generated-C/executable pairs, corrected native
pool/fixture-teardown/review-checker diagnostics and fresh probe/audit
evidence are retained in `build/ios/fortnite/cf-locale-current-checks`. The
link probe clears `_CFLocaleCopyCurrent` and stops before entry at
`_CFLocaleCopyPreferredLanguages`. Fortnite remains unplayable; the full iOS
regression is unpassed.

`_CFLocaleCopyPreferredLanguages` now returns an owned immutable NSArray
snapshot whose NSString elements remain borrowed until retained separately.
On macOS it copies the complete native preference order, including an empty
list, and balances the native array and temporary native autorelease pool.
Each compatibility result has an independent lifetime and survives pool
drains and the release of other snapshots. Native snapshots support up to
32 entries and 1,023 UTF-8 bytes per string.

Vinix uses a colon-separated `LANGUAGE` priority list, skips empty entries
and removes duplicate normalized tags without changing preference order.
An absent or empty list uses the existing locale environment policy and
`en_US` compatibility default. The bounded profile supports two/three-letter
languages, optional scripts/regions and a POSIX variant, plus measured
Hebrew/Indonesian/Yiddish aliases and Chinese/English canonical forms. It
accepts at most 32 distinct tags, 128 bytes per source tag and 4,095 bytes in
`LANGUAGE`; unsupported forms fail explicitly. This is a Vinix configuration
policy, without a CFPreferences database or full ICU canonicalization.

`tests/ios/native-checks.v build-cf-preferred-languages` builds the fixture.
Six host ASan/UBSan runs pass preferred-language, current-locale and CF
dictionary checks. Native measurements compare the full preference list,
array/element ownership and supported canonical tags. The optimized ARM64
fixture checks order/deduplication, fallback precedence, 32-entry bounds,
partial-error cleanup, non-NUL-terminated guarded parser input, protected
argument/x8 registers, preserved x20/x21, independent snapshots, retained
elements, eight concurrent callers and two drained runtimes. Generated C
review verifies stack parsing, array/child cleanup and native ownership.

Native measurements, seven generated-C/executable pairs and fresh probe/audit
evidence are retained in `build/ios/fortnite/cf-preferred-languages-checks`.
The link probe clears `_CFLocaleCopyPreferredLanguages` and stops before
entry at `_CFLocaleGetValue`. Fortnite remains unplayable; the full iOS
regression is unpassed.

`_CFLocaleGetValue` now returns borrowed identifier, language and country
NSStrings from built-in NSLocale snapshots. `NSLocale.objectForKey:` shares
the same lookup. Identifier queries return the stored snapshot; language
and country strings are cached together under the runtime lock and owned by
the locale. A missing country stays nil and is cached without guessing a
region. Callers may retain a value to keep it after the locale is released.

On macOS the components are copied from a native fixed locale, with balanced
CF owners and a temporary native autorelease pool. Component strings support
up to 1,023 UTF-8 bytes. Vinix parses a bounded 128-byte profile: two-letter
languages, optional scripts, alphabetic/numeric regions and a POSIX variant,
plus root, C/POSIX and measured Hebrew/Indonesian/Yiddish aliases. Keywords,
three-letter languages and the full ICU alias database remain unsupported
on Vinix. Known locale metadata keys outside the three string keys fail
explicitly; unrecognized keys return nil, matching native lookup behavior.

`tests/ios/native-checks.v build-cf-locale-value` builds the fixture. Six
host ASan/UBSan runs pass locale-value, current-locale and Swift fixed-locale
checks. Four native profiles compare complete language/country results,
including empty language, missing country, scripts, numeric regions and
POSIX. The optimized ARM64 fixture checks borrowed/cache identity, retained
child lifetimes and zeroed weak references, key-content equality, explicit
unsupported queries, non-NUL-terminated guarded parser input, protected
x2–x8 registers, preserved x20/x21, concurrent first queries, Objective-C
integration and two drained runtimes. Generated C review checks atomic cache
publication, failed-query cleanup and transfer to the locale's owned fields.

Native measurements, seven generated-C/executable pairs and fresh probe/audit
evidence are retained in `build/ios/fortnite/cf-locale-value-checks`. The link
probe clears `_CFLocaleGetValue` and stops before entry at
`_CFPreferencesAppSynchronize`. Fortnite remains unplayable; the full iOS
regression is unpassed.

`_CFPreferencesAppSynchronize` now flushes the current application's persisted
defaults through the same store as `NSUserDefaults`. It accepts the current-app
constant by string content and the bundle identifier read from `Info.plist`
(or the existing bundle-filename fallback). Its return uses CF's unsigned-byte
Boolean ABI. Allocated NSStrings and registered Mach-O constant strings are
accepted. Unsupported domains and invalid arguments return false. Directory
creation, write and exact-path rename failures also return false, with the
in-memory values available for retry. Synchronization and standard-defaults
mutations share the runtime lock; registration defaults stay out of the plist.

Preference writes now rename to exactly the plist path. V's directory-target
rename behavior previously allowed a write into a directory at that path to
report success. The fixture caught this behavior; the failed generated C,
executable, debug symbols and log are retained. The store still uses one
per-bundle application source with eager setters. External-process merging,
live reload, custom suites, global/managed/host sources and power-loss durability
remain unsupported; malformed bundle metadata or an invalid existing plist
retain the existing explicit startup failure.

`tests/ios/native-checks.v build-cf-preferences-sync` builds the fixture. Six
host ASan/UBSan runs pass synchronization, CF dictionary and locale-value checks.
Four native profiles measure empty/staged/removal synchronization and a blocked
destination, using only an isolated temporary preference domain. The optimized
ARM64 fixture checks the single argument with protected x1–x8 registers,
preserved x20/x21, Boolean success/failure, bundle identity, registration
exclusion, cold/write/rename failure recovery, concurrent writes, removal and
persistence across two drained runtimes. Generated C and assembly review checks
the shared locking, exact rename, owned path/identity and serializer cleanup.

Evidence and seven generated-C/executable pairs are retained in
`build/ios/fortnite/cf-preferences-sync-checks`. The fresh link probe clears
`_CFPreferencesAppSynchronize` and stops before entry at
`_CFPreferencesCopyAppValue`. Fortnite remains unplayable; the full iOS
regression is unpassed.

`_CFPreferencesCopyAppValue` now reads the current application's shared defaults
store. It accepts the current-app constant or bundle identifier, compares keys
by string content, searches persisted values before registered fallbacks, and
returns nil for an absent key. Allocated NSStrings and registered Mach-O string
constants are accepted for both arguments. Unsupported application domains,
invalid arguments and unsupported preference objects fail explicitly.

Each successful lookup returns an owned immutable property-list snapshot.
Its strings, data, arrays, dictionaries and children survive replacement of the
stored value and autorelease-pool cleanup. Construction transfers child owners
directly to collections, and balances V's implicit map-iteration key copies.
The existing autoreleased plist conversion now wraps the owned constructor.
Boolean values keep their CFBoolean type through parsing, standard-defaults
setters, serialization and restart. The supported profile consists of strings,
signed integers, reals, Booleans, data, arrays and string-keyed dictionaries.
Dates, other application domains, global/managed/host sources and external
preference merging or live reload remain unsupported.

`tests/ios/native-checks.v build-cf-preferences-value` builds the fixture. Six
host ASan/UBSan runs pass value lookup, synchronization and CF dictionary checks.
Isolated native measurements establish absent nil, content-equal keys, staged
values, all seven supported plist types, registered-default visibility and
retained-result lifetime. The optimized ARM64 fixture checks the two arguments
with protected x2–x8 registers and preserved x20/x21, immutable nested ownership,
persistent precedence, Boolean-preserving save/reload, image constants, rejected
queries, repeated/concurrent dictionary copies, replaced-source child lifetime
and two drained runtimes. Generated C and assembly review checks source locking,
serializer cleanup, static rejection errors and pool-independent tree ownership.

Evidence, diagnostics and seven generated-C/executable pairs are retained in
`build/ios/fortnite/cf-preferences-value-checks`. The fresh link probe clears
`_CFPreferencesCopyAppValue` and stops before entry at
`_CFPreferencesSetAppValue`. Fortnite remains unplayable; the full iOS regression
is unpassed.

`_CFPreferencesSetAppValue` now stages changes in the current application's
shared defaults store. Its three-pointer ABI returns void. A nil value removes
the application's key, exposing a registered fallback if one exists; removing
an absent key is harmless. Non-nil values are copied immediately to immutable
property-list trees, and the store owns a copy of the key. Caller-owned values
can be released or mutable containers changed after the call. Existing copied
results remain valid after replacement or removal.

The setter accepts the current-app constant or bundle identifier and allocated
or registered image strings. It validates the complete supported tree under
the same runtime lock as reads and synchronization before changing the store.
Invalid arguments, unsupported domains or object types, raw CF collections,
cycles/excessive depth, data over 16 MiB and non-finite real numbers fail
explicitly. Rejected updates preserve existing values. The supported profile
uses strings, signed integers, finite reals, Booleans, data, arrays and
string-keyed dictionaries; dates and broader preference domains remain unsupported.

CF setters perform no file writes. `CFPreferencesAppSynchronize` flushes the
shared application source and reports persistence failures, leaving staged
values available for retry. Existing eager `NSUserDefaults` setters also flush
that shared source. Registered defaults remain separate from persisted values.

`tests/ios/native-checks.v build-cf-preferences-set` builds the fixture. Six host
ASan/UBSan runs pass setter, lookup and synchronization checks. Native probes
measure value copying, equal-key lookup, nil removal, all seven supported plist
types and persistence through an isolated temporary domain. The optimized ARM64
fixture checks protected x3–x8 registers and preserved x20/x21, the void return
contract, caller ownership, mutable-input isolation, image constants, rejected
updates without mutation, repeated/concurrent replacements and removals,
registration fallback, failure/retry synchronization and restart persistence.
Generated C and assembly review checks validation before mutation, owned
key/value transfer, serializer cleanup and absence of setter file writes.

Evidence, diagnostics and seven generated-C/executable pairs are retained in
`build/ios/fortnite/cf-preferences-set-checks`. The fresh link probe clears
`_CFPreferencesSetAppValue` and stops before entry at `_CFRunLoopGetMain`.
Fortnite remains unplayable; the full iOS regression is unpassed.

`_CFRunLoopGetMain` now returns a borrowed handle to the existing main desktop
run loop. Foundation's `mainRunLoop` and main-thread `currentRunLoop` use the
same locked lazy cache, and its `getCFRunLoop` returns that handle. Worker-first
access still identifies the main loop. The runtime owns one reference until
shutdown; repeated calls neither retain nor autorelease it. Callers may balance
their own `CFRetain`/`CFRelease` pairs without consuming the cached reference.

Native probes verify main/current identity, distinct worker current loops,
Foundation's `getCFRunLoop` mapping and survival across autorelease drains.
Vinix keeps its existing restriction on background `NSRunLoop currentRunLoop`.
The getter does not add CF source, observer, timer or run/wake/stop APIs; existing
desktop display-link scheduling continues through the shared handle.

`tests/ios/native-checks.v build-cf-run-loop-main` builds the fixture. Six host
ASan/UBSan runs pass main-loop, connection and current-locale checks. The optimized
ARM64 guest fixture verifies protected x0–x8 registers, preserved x20/x21,
concurrent first publication, borrowed ownership, balanced caller references,
display-link schedule/fire/remove/invalidate on the main thread, absence of
per-call objects or autoreleases and two fully released runtime caches.
Generated C and assembly review checks the no-argument pointer ABI, locked
publication, shared Foundation getters and shutdown release in the fixture and
both production runners.

Evidence and seven generated-C/executable pairs are retained in
`build/ios/fortnite/cf-run-loop-main-checks`. The fresh link probe clears
`_CFRunLoopGetMain` and stops before entry at `_CFStringCompare`.
Fortnite remains unplayable; the full iOS regression is unpassed.

`_CFStringCompare` now implements the zero-option profile used by Fortnite's
application-preference cleanup. Two string pointers and a 64-bit option mask
arrive in x0–x2; the signed 64-bit result is exactly -1, 0 or 1. Comparison uses
literal UTF-16 code-unit order, including embedded NULs, prefixes and surrogate
pairs. Case differences and composed/decomposed spellings remain distinct.
Supplementary characters sort by their surrogate units rather than UTF-8 bytes.

The bridge validates allocated NSStrings or registered UTF-8/decoded UTF-16 image
constants before borrowing their bytes under the runtime lock. Valid UTF-8 up
to 16 MiB is supported. Invalid provenance, malformed UTF-8 and nonzero options
fail explicitly, including case-insensitive, nonliteral, localized and numeric
comparison options. Two stack cursors stream UTF-16 units without allocating a
conversion buffer, retaining inputs or adding autoreleases. Caller references
and input contents remain unchanged.

`tests/ios/native-checks.v build-cf-string-compare` builds the fixture. Six host
ASan/UBSan runs pass comparison, preference lookup and preference setter checks.
Native differential cases verify signed results, empty strings, embedded NULs,
prefixes, normalization/case distinctions and BMP/surrogate ordering through
U+10FFFF. The optimized ARM64 guest fixture also checks protected x3–x8,
preserved x20/x21, both image constant encodings, rejected inputs and full-width
option masks, eight concurrent readers, unchanged ownership and two drained
runtimes. Generated C and assembly review verifies the ABI, locked validation,
stack cursors, borrowed text and static unboxed rejection errors in the fixture
and both production runners.

Evidence and seven generated-C/executable pairs are retained in
`build/ios/fortnite/cf-string-compare-checks`. The fresh link probe clears
`_CFStringCompare` and stops before entry at `_CFUUIDCreate`.
Fortnite remains unplayable; the full iOS regression is unpassed.

`_CFUUIDCreate` now accepts an allocator pointer in x0 and returns an owned
CFUUID reference in x0. `nil`, `kCFAllocatorDefault` and `kCFAllocatorSystemDefault`
use the existing secure entropy helper. Custom allocators, `kCFAllocatorNull`
and calls outside the runtime lifetime fail explicitly.
The helper obtains sixteen bytes from `getentropy`, sets the version-4 and
variant bits and fails explicitly if entropy is unavailable. A complete value
is obtained before allocating and returning the object.

Native probes identify CFUUID as `__NSCFType`, with `isKindOfClass:NSUUID`
returning false. Vinix therefore uses a distinct private CFUUID class and
stores its sixteen bytes in existing object metadata. No UUID sidecar or
autorelease is added. `CFRetain`/`CFRelease`, collection ownership and weak
reference cleanup use the existing object lifetime machinery. Other CFUUID
constructors and byte/string conversion APIs remain unimplemented.

`tests/ios/native-checks.v build-cf-uuid-create` builds the fixture. Six host
ASan/UBSan runs pass CFUUID creation, NSUUID and low-level UUID generation checks.
Native checks verify owned references, null/default allocation, autorelease
independence, version/variant bits, uniqueness and variation of unreserved bits.
The optimized ARM64 guest fixture also checks protected x1–x8, preserved x20/x21,
allocator rejection, the distinct type, 512 unique stored values across eight
workers per runtime, unchanged errno, balanced references, collection/weak
lifetimes and two zero-live-object teardowns. Generated C and assembly review
verifies the one-pointer ABI, locked allocator validation, secure entropy before
object allocation, inline payload, owned return and static unboxed errors in
the fixture and both production runners.

Evidence and seven generated-C/executable pairs are retained in
`build/ios/fortnite/cf-uuid-create-checks`. The fresh link probe clears
`_CFUUIDCreate` and stops before entry at `_CFUUIDCreateFromString`.
Fortnite remains unplayable; the full iOS regression is unpassed.

`_CFUUIDCreateFromString` now accepts allocator/string pointers in x0/x1 and
returns an owned CFUUID reference in x0. It accepts null/default allocation and
allocated strings or registered UTF-8/decoded UTF-16 image constants. Invalid
string provenance, malformed UTF-8, custom allocators, `kCFAllocatorNull` and
calls outside the runtime lifetime fail explicitly.

Native differential probes show that this parser differs from NSUUID's strict
canonical parser: it examines at most 100 UTF-16 units, skips leading non-hex
units, ignores the contents of four fixed separator slots and zero-fills
invalid or incomplete byte pairs. Trailing text is ignored. Only an empty
string returns nil; nonempty strings without hex pairs produce an all-zero
UUID. All parsed bits are preserved, without imposing version/variant bits.
Two fixed stack buffers hold the UTF-16 units and sixteen output bytes before
one object is allocated. Results are independent of the source string and use
the existing reference/weak-reference lifetime machinery. Equal UUID payloads
have value equality and equal hashes, including collection key lookup; CFUUID
and NSUUID remain distinct types. Native implementations may reuse an existing
UUID, while this bridge returns independent owned objects.

`tests/ios/native-checks.v build-cf-uuid-string` builds the fixture. Six host
ASan/UBSan runs pass string parsing, CFUUID creation and NSUUID checks. The 42
native differential cases cover prefixes, case, embedded NULs, separator slots,
bad/incomplete pairs and the 100-unit boundary with BMP/supplementary text.
The optimized ARM64 guest fixture also verifies protected x2–x8, preserved
x20/x21, both image constant encodings, allocator/input rejection, value equality
and hashing, source independence, dictionary/weak lifetimes, eight concurrent
readers, balanced references, no autoreleases and two zero-live-object teardowns.
Generated C and assembly review verifies the two-pointer ABI, locked validation,
stack parsing, inline payload, owned return and static unboxed errors in the
fixture and both production runners.

Evidence and seven generated-C/executable pairs are retained in
`build/ios/fortnite/cf-uuid-string-checks`. The fresh link probe clears
`_CFUUIDCreateFromString` and stops before entry at `_CFUUIDCreateFromUUIDBytes`.
Fortnite remains unplayable; the full iOS regression is unpassed.

`_CFUUIDCreateFromUUIDBytes` now accepts an allocator in x0 and a by-value
sixteen-byte CFUUIDBytes aggregate in x1/x2, returning an owned CFUUID reference
in x0. Fortnite's call site loads the two words with `ldp x1, x2, [x8]`, passes
a null allocator and stores the result. The bridge copies both words into the
existing inline CFUUID metadata, preserving byte order and every bit, including
zero or nonstandard version/variant fields. The words are values, so even
pointer-shaped payloads are accepted without dereferencing them.

Null/default allocators are supported; custom allocators, `kCFAllocatorNull`
and calls outside the runtime lifetime fail explicitly. Allocator validation
precedes the single object allocation. The implementation reuses the existing
CFUUID type, reference/weak-reference cleanup and value equality/hash behavior.
It adds no UUID sidecar or autorelease, and equal byte/string-created values
work interchangeably in collection lookup.

`tests/ios/native-checks.v build-cf-uuid-bytes` builds the fixture. Six host
ASan/UBSan runs pass byte construction, random UUID creation and string parsing.
A typed native probe verifies 260 payloads, including every bit independently
set and cleared, zero/all-ones and ascending/descending bytes. The host fixture
also calls the actual native aggregate ABI through a raw register probe. Its
261 cases include protected-address-shaped payloads, protected x3–x8 and preserved
x20/x21. The optimized ARM64 guest fixture verifies the same payloads, rejected
allocators, owned pool-independent results, equality/hash across constructors,
set/weak lifetimes, eight concurrent callers and two zero-live-object teardowns.
Generated C and assembly review verifies the allocator/two-word ABI, locked
validation, exact scalar-to-inline copies, owned return and static unboxed
errors in the fixture and both production runners.

Evidence and seven generated-C/executable pairs are retained in
`build/ios/fortnite/cf-uuid-bytes-checks`. The fresh link probe clears
`_CFUUIDCreateFromUUIDBytes` and stops before entry at `_CFUUIDCreateString`.
Fortnite remains unplayable; the full iOS regression is unpassed.

`_CFUUIDCreateString` now accepts allocator/CFUUID pointers in x0/x1 and returns
an owned CFString reference in x0. Native probes verify uppercase canonical
36-character text with hyphens at positions 8, 13, 18 and 23. Every UUID bit is
preserved through string parsing, including zero or nonstandard version/variant
fields. Formatting uses a fixed stack buffer, then the existing NSString
constructor copies its bytes into owned, NUL-terminated storage.

The bridge accepts null/default allocation and a live CFUUID from the runtime's
object map. It checks provenance before reading UUID storage, rejecting nil,
stale handles, class objects, NSUUID/other objects, custom allocators,
`kCFAllocatorNull` and calls outside the runtime lifetime. An isolated native
nil diagnostic faults on this Mac; the bridge reports its checked failure.
UUID contents and references remain unchanged. Returned strings outlive both
the source UUID and the creating autorelease pool, and use the existing
collection and weak-reference cleanup machinery.

`tests/ios/native-checks.v build-cf-uuid-text` builds the fixture. Six host
ASan/UBSan runs pass formatting, byte construction and string parsing checks.
Native/runtime cases cover every byte value at every position, four known
strings, uppercase/hyphen layout, exact parse round trips and balanced ownership.
The optimized ARM64 guest fixture also verifies protected x2–x8, preserved
x20/x21, invalid input/allocator rejection, source/pool independence, collection
and weak lifetimes, eight concurrent readers, no autoreleases and two
zero-live-object teardowns. Generated C and assembly review verifies the
two-pointer ABI, locked provenance validation, stack formatting, copied string
backing, owned return and static unboxed errors in the fixture and both
production runners.

Evidence and seven generated-C/executable pairs are retained in
`build/ios/fortnite/cf-uuid-text-checks`. The fresh link probe clears
`_CFUUIDCreateString` and stops before entry at `_CFUUIDGetUUIDBytes`.
Fortnite remains unplayable; the full iOS regression is unpassed.

`_CFUUIDGetUUIDBytes` now accepts one CFUUID pointer in x0 and returns its
sixteen-byte value in x0/x1. Fortnite stores those words with unaligned stores
at offsets 5 and 13, then releases the UUID. A two-word integer aggregate matches
this native ARM64 return convention, including its lack of an indirect x8
output pointer. The bridge copies all sixteen bytes without changing any bits,
references or runtime object counts. Returned values remain valid after the
source UUID and autorelease pool are released.

The adapter checks runtime lifetime, object-map provenance, the distinct CFUUID
class and live references while holding the runtime lock. Nil, stale or foreign
handles, class objects, NSUUID and destroyed storage fail explicitly before
reading payload bytes. An isolated native nil diagnostic faults on this Mac.
Extraction uses a stack value without allocating, retaining or autoreleasing.

`tests/ios/native-checks.v build-cf-uuid-read` builds the fixture. Six host
ASan/UBSan runs pass extraction, byte construction and string formatting checks.
The native/runtime raw-register fixture covers 261 payloads, every byte value
at every position, zero/all-ones/ascending/descending values and protected-address
bit patterns. It reproduces the unaligned stores at offsets 5 and 13 with intact
surrounding canaries, protects x1–x8 and verifies preserved x20/x21. The optimized
ARM64 guest fixture also checks invalid handles, values from all three supported
UUID constructors, independent copies, unchanged references, eight concurrent
readers, no allocations/autoreleases and two zero-live-object teardowns.
Generated C and assembly review verifies the aggregate layout and return ABI,
locked provenance checks, exact stack copy and static unboxed errors in the
fixture and both production runners.

Evidence and seven generated-C/executable pairs are retained in
`build/ios/fortnite/cf-uuid-read-checks`. The fresh link probe clears
`_CFUUIDGetUUIDBytes` and stops before entry at `_NSCalendarIdentifierISO8601`.
Fortnite remains unplayable; the full iOS regression is unpassed.

`_NSCalendarIdentifierISO8601` now exports an aligned NSString pointer cell
through Foundation and CoreFoundation. Native measurements confirm that both
frameworks expose the same cell and exact `iso8601` CFString value. Fortnite's
GOT consumer at `0x105eb70bc` loads the cell address, then dereferences it into
x2; this is a data import without a function stub.

The bridge extends the existing sealed Foundation constant page to four cells
and four CFSTR records. Publication is serialized, registers all strings before
sealing the page read-only, and preserves stable identities without allocating
runtime objects on lookup. Retain, release, autorelease, immutable copying and
equal-string dictionary lookup use the existing NSString machinery. Shutdown
rejects cold publication while keeping published cells readable to callbacks;
all four registrations and the page retire after pools and Swift contexts drain.
The original three Foundation key values and record locations are preserved.

`tests/ios/native-checks.v build-ns-calendar-iso8601` builds the new fixture.
Six host ASan/UBSan runs pass the identifier, Foundation-key and URL-session
constant checks. The optimized ARM64 fixture passes eight concurrent cold
publishers, both framework routes, exact pointer/CFSTR/string layout, string and
dictionary behavior, retirement guards, callback access and two zero-live-object
teardowns. A separate native probe confirms acceptance by CoreFoundation's
ISO8601 calendar with Monday/four-day week rules; this does not implement
Objective-C NSCalendar construction or calendar arithmetic on Vinix.
Generated C and assembly inspection covers the expanded layout, publication,
allocation behavior and deferred unregister/unmap in both production runners.

Evidence and seven generated-C/executable pairs are retained under
`build/ios/fortnite/ns-calendar-iso8601-checks`. The fresh production link probe
clears this import and stops before entry at `_NSInternalInconsistencyException`.
Fortnite remains unplayable; the full iOS regression is unpassed.

`_NSInternalInconsistencyException` now exports an aligned NSString pointer
cell through Foundation and CoreFoundation. Native measurements confirm a
shared cell containing the exact 32-byte `NSInternalInconsistencyException`
CFString value. Fortnite loads that cell through its GOT at `0x100092cb4` and
`0x100094274`, dereferences it into x2 and constructs NSError with code -1 and
nil userInfo. These are data consumers without a function stub.

The bridge uses a dedicated sealed page with one pointer cell, a CFSTR record
and NUL-terminated static bytes. Lazy publication holds the runtime lock,
registers the string before sealing the page read-only, and then publishes the
shared address. Lookup creates no Objective-C objects or temporary strings.
Retain/release, autorelease, copying, equality, hashing and dictionary-key use
follow the existing immutable NSString behavior. Published cells remain
available to teardown callbacks after cold publication is disabled. The string
registration and page retire after pools, NSError owners and Swift contexts
drain. This adds a name constant; Objective-C exception throwing and unwinding
remain unsupported.

`tests/ios/native-checks.v build-ns-internal-exception` builds the fixture.
Six host ASan/UBSan runs pass this fixture, Foundation keys and the ISO8601
identifier. The optimized ARM64 guest fixture also passes.
Native and runtime checks cover both framework routes, exact data layout and
text, eight concurrent cold publishers, immutable copying, equal-string
dictionary lookup and NSError domains with nil or retained userInfo across
autorelease pools. Two runtime lifetimes check retirement guards, callback
availability, zero live objects and removal of the constant registration.
Foundation-key and ISO8601-identifier fixtures cover the existing constant
storage. Generated C and assembly inspection covers the cell/record/byte layout,
publication order, allocation behavior and deferred unregister/unmap in the
fixture and both production runners.

Evidence and seven generated-C/executable pairs are retained under
`build/ios/fortnite/ns-internal-exception-checks`. The fresh production link
probe clears this import and stops before entry at `_NSInvalidArgumentException`.
Fortnite remains unplayable; the full iOS regression is unpassed.

`_NSInvalidArgumentException` now exports an aligned NSString pointer cell
through Foundation and CoreFoundation. Native measurements confirm the same
cell under both install names and the exact 26-byte `NSInvalidArgumentException`
CFString value, distinct from `NSInternalInconsistencyException`. Fortnite's
consumers at `0x100041044` and `0x10007d1cc` load the cell through the GOT,
dereference it into x2 and pass the name to NSException calls. This adds the
name constant; NSException construction, throwing and unwinding remain
unsupported on Vinix.

The existing exception-name page now publishes both cells and CFSTR records
under the runtime lock before sealing the page read-only. The original
internal-inconsistency cell, record and bytes stay at offsets 0, 32 and 64;
the new name uses offsets 8, 128 and 160 without another page allocation.
Each exact-name wrapper selects its own cell. Cached lookup allocates no
objects or temporary strings, and retirement rejects new publication while
keeping existing cells available to callbacks. Shutdown unregisters both
strings before unmapping their shared page after pools and Swift contexts drain.

`tests/ios/native-checks.v build-ns-invalid-argument` builds the fixture.
Six host ASan/UBSan runs pass this fixture, internal inconsistency and
Foundation keys. The optimized ARM64 guest fixture also passes.
Native and runtime checks cover distinct names, both framework routes, eight
mixed-name concurrent cold publishers, stable identities, exact cell/record/text
layout, immutable copying, string equality/hash, dictionary-key use and
autorelease pools. Two runtime lifetimes check both names during teardown,
retirement guards, zero live objects and removal of both registrations.
The internal-inconsistency and Foundation-key fixtures cover existing behavior.
Generated C and assembly review checks the shared layout, publication and
two-name retirement in the fixture and both production runners.

Evidence and seven generated-C/executable pairs are retained under
`build/ios/fortnite/ns-invalid-argument-checks`. The fresh production link
probe clears this import and stops before entry at `_NSLocaleCountryCode`.
Fortnite remains unplayable; the full iOS regression is unpassed.

`_NSLocaleCountryCode` now resolves through Foundation and CoreFoundation.
Native measurements show that it and `_kCFLocaleCountryCode` share the same
aligned pointer cell and the exact 23-byte NSString value
`kCFLocaleCountryCodeKey` under both install names. Fortnite's consumer at
`0x10008cb44` loads the cell through GOT slot `0x10dc9b1c8`, dereferences it
into x26 and passes the key as the x2 argument to subsequent calls.

Both spellings now use one sealed page containing their shared cell, CFSTR
record and NUL-terminated bytes at offsets 0, 32 and 64. This replaces the
CF spelling's separate owned-string storage. Publication registers the constant
under the runtime lock before sealing the page read-only; cached lookup
allocates nothing. Retirement rejects cold publication while preserving the
cached key for destructors. Shutdown unregisters and unmaps it after pools
and Swift contexts drain.

`tests/ios/native-checks.v build-ns-locale-country` builds the fixture.
Six host ASan/UBSan runs pass the new fixture and both existing locale fixtures;
the optimized ARM64 guest fixture also passes. Native and runtime checks cover
eight mixed-alias concurrent readers, both framework routes, exact storage,
immutable copying, dictionary-key use and autorelease pools. Locale queries
through `objectForKey:` and `CFLocaleGetValue` agree for alpha/numeric/script
regions, absent countries and an equal independently allocated key. Repeated
queries preserve cached result identity without object growth; retained results
survive locale release. The fixture also checks currentLocale, retirement
callbacks and two drained runtime lifetimes. Generated C and assembly review
covers the fixture and both production runners.

Evidence and seven generated-C/executable pairs are retained under
`build/ios/fortnite/ns-locale-country-checks`. The fresh production link probe
clears this import and stops before entry at `_NSLocaleCurrencyCode`.
Fortnite remains unplayable; the full iOS regression is unpassed.

`_NSLocaleCurrencyCode` now resolves through Foundation and CoreFoundation.
Native measurements confirm that both install names and the CF spelling
`_kCFLocaleCurrencyCode` share one aligned NSString pointer cell containing
the exact eight-byte value `currency`, distinct from the country key.
Fortnite's consumers at `0x104844bcc` and `0x107faf664` load GOT slot
`0x10dc9b1d0`, dereference its pointer into x2 and pass the key to subsequent
calls. This exports the key; currency-value queries still fail explicitly.
Native USD/EUR/JPY, regionless and currency-override queries were measured
as reference behavior, without adding a currency database to Vinix.

The existing locale-key page now publishes both cells under the runtime lock
before sealing the page read-only. Country storage stays at offsets 0, 32 and
64; currency uses offsets 8, 128 and 160 without another page allocation.
Each NS/CF alias pair selects its own cell. Cached lookup allocates nothing,
retirement preserves existing cells for callbacks, and shutdown unregisters
both strings before unmapping the page after pools and Swift contexts drain.

`tests/ios/native-checks.v build-ns-locale-currency` builds the fixture.
Six host ASan/UBSan runs pass the new fixture, country-key fixture and locale
value fixture. The optimized ARM64 guest fixture also passes. Native and runtime
checks cover eight mixed-key/alias cold publishers, both framework routes,
distinct identities, exact storage, immutable copying, CFHash, equal-string
dictionary lookup and autorelease pools. Currency queries retain their explicit
diagnostic without object growth or changes to country queries. Two runtime
lifetimes check both keys during teardown and remove both registrations.
An initial fixture used the existing unsupported Objective-C `hash` path;
its host/guest diagnostics, generated C and executables are preserved in
`objc-hash-diagnostic` within this cohort. The corrected fixture uses CFHash,
matching the established constant fixtures. Generated C and assembly review
covers shared publication and retirement in the fixture and production runners.

Evidence and seven generated-C/executable pairs are retained under
`build/ios/fortnite/ns-locale-currency-checks`. The fresh production link probe
clears this import and stops before entry at `_NSLocaleCurrencySymbol`.
Fortnite remains unplayable; the full iOS regression is unpassed.

`_NSLocaleCurrencySymbol` now resolves through Foundation and CoreFoundation.
Native measurements confirm that the NS and CF spellings share the same
aligned NSString pointer cell under both install names, containing the exact
26-byte key `kCFLocaleCurrencySymbolKey`. Fortnite's consumer at `0x104844c08`
loads GOT slot `0x10dc9b1d8`, dereferences it into x2 and passes the key to
the following call. Currency-code and currency-symbol value queries remain
explicitly unsupported in the bridge.

The existing locale-key page now contains all three cells and CFSTR records.
Country and currency-code storage retain their layouts; the symbol key uses
offsets 16, 192 and 224 for its cell, record and NUL-terminated text.
Publication registers all three constants under the runtime lock before
sealing the page read-only. Cached lookup allocates nothing. Retirement keeps
published cells available to callbacks, and shutdown unregisters all three
before unmapping the page after pools and Swift contexts drain.

`tests/ios/native-checks.v build-ns-locale-currency-symbol` builds the fixture.
Six host ASan/UBSan runs pass the new symbol-key fixture and the existing
currency-code and country-key fixtures. The optimized ARM64 guest fixture
also passes. Checks cover eight mixed-key/alias concurrent readers, all three
distinct keys, both framework routes, exact layouts, immutable copying,
CFHash, equal-string dictionary lookup and autorelease pools. Both currency
queries retain their explicit diagnostic without object growth or changes
to country queries. Two runtime lifetimes check three-key callback access
and removal of all registrations. Generated C and assembly review covers
the fixture and both production runners.

Native symbol values, including `$`, `€`, `¥`, the generic currency sign and
a currency override, were measured separately. Repeated native queries can
return equal strings with different identities; the reference compares their
contents. The initial pointer-identity diagnostic is preserved under
`native-query-identity-diagnostic` within this cohort.

Evidence and seven generated-C/executable pairs are retained under
`build/ios/fortnite/ns-locale-currency-symbol-checks`. The fresh production link
probe clears this import and stops before entry at `_NSURLCreationDateKey`.
Fortnite remains unplayable; the full iOS regression is unpassed.

`_NSURLCreationDateKey` now resolves through Foundation and CoreFoundation.
Native measurements confirm that it and `_kCFURLCreationDateKey` share one
aligned NSString pointer cell under both install names, containing the exact
20-byte value `NSURLCreationDateKey`. Fortnite's consumer at `0x100087798`
loads GOT slot `0x10dc9b1e0`, dereferences it into x25 and builds a one-key
NSArray for a subsequent NSFileManager call. This exports the resource key;
resource-date lookup remains unsupported.

URL resource keys use a separate sealed page so existing Foundation key
layouts stay unchanged. Its cell, CFSTR record and NUL-terminated bytes occupy
offsets 0, 32 and 64. Publication registers the constant under the runtime lock
before sealing the page read-only; cached lookup allocates nothing. Retirement
keeps the cell available to callbacks, and shutdown unregisters it before
unmapping the page after pools and Swift contexts drain.

`tests/ios/native-checks.v build-ns-url-creation-date` builds the fixture.
Six host ASan/UBSan runs pass the new fixture, Foundation keys and the ISO8601
calendar-identifier fixture. The optimized ARM64 guest fixture also passes.
Native and runtime checks cover eight mixed-alias readers, both framework
routes, exact storage, immutable copying, CFHash, equal-string dictionary
lookup and a retained one-key NSArray surviving pool drain. Two runtime
lifetimes check isolated storage, retirement guards, callback access, zero
live objects and removal of the key's registration. Generated C and assembly
review covers the fixture and both production runners.

Evidence and seven generated-C/executable pairs are retained under
`build/ios/fortnite/ns-url-creation-date-checks`. The fresh production link probe
clears this import and stops before entry at `_NSURLFileSizeKey`.
Fortnite remains unplayable; the full iOS regression is unpassed.

`_NSURLFileSizeKey` now resolves through Foundation and CoreFoundation.
Native measurements confirm that it and `_kCFURLFileSizeKey` share one aligned
NSString pointer cell under both install names, containing the exact 16-byte
value `NSURLFileSizeKey`. Its cell and NSString are distinct from the
creation-date key. Fortnite's consumers at `0x1000909f0` and `0x100090c08`
load GOT slot `0x10dc9b1e8` and dereference the key. The first builds a two-key
NSArray alongside `NSURLIsRegularFileKey`; the second passes the key in x3.
File-size resource lookup remains unsupported.

The shared URL-resource page preserves the creation-date cell, CFSTR record
and text at offsets 0, 32 and 64, adding file-size storage at 8, 128 and 160.
Both constants register under the runtime lock before read-only publication.
Cached lookup allocates nothing, and both registrations remain available to
shutdown callbacks until pools and Swift contexts drain, then unregister
before the page is unmapped.

`tests/ios/native-checks.v build-ns-url-file-size` builds the new fixture.
Six host ASan/UBSan runs pass the new fixture, Foundation keys and the existing
creation-date fixture. The optimized ARM64 guest fixture also passes.
Native and runtime checks cover eight readers alternating both keys and
their NS/CF aliases under both framework routes, exact distinct storage,
immutable copying, CFHash, equal-string dictionary lookup and a retained
two-key NSArray surviving pool drain. Two runtime lifetimes check isolated
storage, retirement guards, callback access, zero live objects and removal
of both registrations. Generated C and assembly review covers the fixture
and both production runners.

Evidence and seven generated-C/executable pairs are retained under
`build/ios/fortnite/ns-url-file-size-checks`. The fresh production link probe
clears this import and stops before entry at `_NSURLIsExcludedFromBackupKey`.
Fortnite remains unplayable; the full iOS regression is unpassed.

`_NSURLIsExcludedFromBackupKey` now resolves through Foundation and
CoreFoundation. Native measurements confirm that it and
`_kCFURLIsExcludedFromBackupKey` share one aligned NSString pointer cell under
both install names, containing the exact 28-byte value
`NSURLIsExcludedFromBackupKey`. Its cell and NSString are distinct from the
creation-date and file-size keys. Four inspected consumers load GOT slot
`0x10dc9b1f0`: `0x10004d49c` dereferences the key into x25 for a one-key
NSArray, `0x1006279d4` loads it into x19, and `0x100087ef0` and `0x1006281d0`
pass it in x3 alongside NSNumber values. Backup-exclusion metadata reads and
writes remain unsupported.

The shared URL-resource page preserves both existing layouts and adds the
backup-exclusion cell, CFSTR record and NUL-terminated text at offsets 16,
192 and 224. All three constants register under the runtime lock before
read-only publication. Cached lookup allocates nothing. Shutdown keeps all
three keys available to callbacks until pools and Swift contexts drain,
then unregisters them before unmapping the page.

`tests/ios/native-checks.v build-ns-url-backup-exclusion` builds the fixture.
Six host ASan/UBSan runs pass the new fixture and the existing file-size and
creation-date fixtures. The optimized ARM64 guest fixture also passes.
Native and runtime checks cover eight readers alternating all three keys
and their NS/CF aliases under both framework routes, exact distinct storage,
immutable copying, CFHash and equal-string dictionary lookup. Retained
three-key and backup-only NSArrays and an NSNumber dictionary survive pool
drain. Two runtime lifetimes check isolated storage, retirement guards,
callback access, zero live objects and removal of all three registrations.
Generated C and assembly review covers the fixture and both production runners.

Evidence and seven generated-C/executable pairs are retained under
`build/ios/fortnite/ns-url-backup-exclusion-checks`. The fresh production link
probe clears this import and stops before entry at `_NSURLIsRegularFileKey`.
Fortnite remains unplayable; the full iOS regression is unpassed.

`_NSURLIsRegularFileKey` now resolves through Foundation and CoreFoundation.
Native measurements confirm that it and `_kCFURLIsRegularFileKey` share one
aligned NSString pointer cell under both install names, containing the exact
21-byte value `NSURLIsRegularFileKey`. Its cell and NSString are distinct from
the three existing resource keys. Fortnite's inspected consumer at
`0x1000909e8` loads GOT slot `0x10dc9b1f8`, dereferences it into x21 and builds
a two-key NSArray alongside `NSURLFileSizeKey`. File-type resource lookup
remains unsupported.

The shared URL-resource page preserves all three existing layouts and adds
the regular-file cell, CFSTR record and NUL-terminated text at offsets 24,
256 and 288. All four constants register under the runtime lock before
read-only publication. Cached lookup allocates nothing. Shutdown keeps all
four keys available to callbacks until pools and Swift contexts drain,
then unregisters them before unmapping the page.

`tests/ios/native-checks.v build-ns-url-regular-file` builds the fixture.
Six host ASan/UBSan runs pass the new fixture and the existing backup-exclusion
and file-size fixtures. The optimized ARM64 guest fixture also passes.
Native and runtime checks cover eight readers alternating all four keys
and their NS/CF aliases under both framework routes, exact distinct storage,
immutable copying, CFHash and equal-string dictionary lookup. A retained
regular-file/file-size NSArray and matching NSNumber dictionary survive pool
drain, as does a four-key array. Two runtime lifetimes check isolated storage,
retirement guards, callback access, zero live objects and removal of all four
registrations. Generated C and assembly review covers the fixture and both
production runners.

Evidence and seven generated-C/executable pairs are retained under
`build/ios/fortnite/ns-url-regular-file-checks`. The fresh production link probe
clears this import and stops before entry at
`_NSURLVolumeAvailableCapacityForImportantUsageKey`.
Fortnite remains unplayable; the full iOS regression is unpassed.

`_NSURLVolumeAvailableCapacityForImportantUsageKey` now resolves through
Foundation and CoreFoundation. Native measurements confirm that its NS and
CF aliases share one aligned NSString pointer cell under both install names,
containing the exact 48-byte value
`NSURLVolumeAvailableCapacityForImportantUsageKey`. Its cell and NSString
are distinct from all four existing resource keys. Fortnite's inspected
consumer at `0x100628934` loads GOT slot `0x10dc9b200`, selects between this
cell and `NSURLVolumeAvailableCapacityKey`, dereferences the selected cell
into x3 and passes an output slot in x2. Volume-capacity resource queries
remain unsupported.

The shared URL-resource page preserves all four existing layouts. The new
cell occupies unused padding at offset 96, with its CFSTR record and
NUL-terminated text at offsets 320 and 352. All five constants register under
the runtime lock before checked read-only publication. Cached lookup uses
a fixed stack table and allocates nothing. Shutdown keeps all five keys
available until pools and Swift contexts drain, then unregisters them before
checked page unmapping.

`tests/ios/native-checks.v build-ns-url-important-capacity` builds the fixture.
Six host ASan/UBSan runs pass the new fixture and the existing regular-file
and backup-exclusion fixtures. The optimized ARM64 guest fixture also passes.
Native and runtime checks cover eight readers alternating all five keys and
their NS/CF aliases under both framework routes, exact distinct storage,
immutable copying, CFHash and equal-string dictionary lookup. Retained
five-key and one-key NSArrays and a synthetic capacity dictionary containing
a 5 GiB + 17 NSNumber survive pool drain. This collection check does not
query a volume. Two runtime lifetimes check isolated storage, retirement
guards, callback access, zero live objects and removal of all five
registrations. Generated C and assembly review covers the fixture and both
production runners.

Evidence and seven generated-C/executable pairs are retained under
`build/ios/fortnite/ns-url-important-capacity-checks`. The fresh production
link probe clears this import and stops before entry at
`_NSURLVolumeAvailableCapacityKey`. Fortnite remains unplayable; the full
iOS regression is unpassed.

`_NSURLVolumeAvailableCapacityKey` now resolves through Foundation and
CoreFoundation. Native measurements confirm that it and
`_kCFURLVolumeAvailableCapacityKey` share one aligned NSString pointer cell
under both install names, containing the exact 31-byte value
`NSURLVolumeAvailableCapacityKey`. Its cell and NSString are distinct from
all five existing resource keys. Fortnite's inspected consumer at
`0x10062893c` loads GOT slot `0x10dc9b208` into x9, conditionally selects it
or the important-usage key cell, then dereferences the selected cell into x3
and passes an output slot in x2. Volume-capacity queries remain unsupported.

The shared URL-resource page preserves all five existing layouts. The sixth
cell occupies padding at offset 104, with its CFSTR record and NUL-terminated
text at offsets 416 and 448. All six constants register under the runtime
lock before checked read-only publication. Cached lookup allocates nothing.
Shutdown keeps all six keys available until pools and Swift contexts drain,
then unregisters them before checked page unmapping.

`tests/ios/native-checks.v build-ns-url-available-capacity` builds the fixture.
Six host ASan/UBSan runs pass the new fixture and the existing important-usage
capacity and regular-file fixtures. The optimized ARM64 guest fixture also
passes. Native and runtime checks cover eight readers alternating all six
keys and both aliases through both frameworks, exact distinct storage,
immutable copying, CFHash and equal-string dictionary lookup. A retained
six-key NSArray, paired-capacity NSArray and synthetic capacity dictionary
preserve distinct 5 GiB + 17 and 7 GiB + 29 NSNumber values across pool drain;
this collection check does not query a volume. Two runtime lifetimes check
isolated storage, retirement guards, callback access, zero live objects and
removal of all six registrations. Generated C and assembly review covers
the fixture and both production runners.

Evidence and seven generated-C/executable pairs are retained under
`build/ios/fortnite/ns-url-available-capacity-checks`. The fresh production
link probe clears this import and stops before entry at
`_NSURLVolumeTotalCapacityKey`. Fortnite remains unplayable; the full iOS
regression is unpassed.

`_NSURLVolumeTotalCapacityKey` now resolves through Foundation and
CoreFoundation. Native measurements confirm that it and
`_kCFURLVolumeTotalCapacityKey` share one aligned NSString pointer cell under
both install names, containing the exact 27-byte value
`NSURLVolumeTotalCapacityKey`. Its cell and NSString are distinct from all
six earlier resource keys. Fortnite's inspected consumer at `0x100628978`
loads GOT slot `0x10dc9b210`, dereferences it into x3, passes an output slot
in x2 and stores the returned object through x20. Volume-capacity queries
remain unsupported.

The shared URL-resource page preserves all six existing layouts. The seventh
cell occupies padding at offset 112, with its CFSTR record and NUL-terminated
text at offsets 480 and 512. All seven constants register under the runtime
lock before checked read-only publication. Cached lookup allocates nothing.
Shutdown keeps all seven keys available until pools and Swift contexts
drain, then unregisters them before checked page unmapping.

`tests/ios/native-checks.v build-ns-url-total-capacity` builds the fixture.
Six host ASan/UBSan runs pass the new fixture and the existing available and
important-usage capacity fixtures. The optimized ARM64 guest fixture also
passes. Native and runtime checks cover eight readers alternating all seven
keys and both aliases through both frameworks, exact distinct storage,
immutable copying, CFHash and equal-string dictionary lookup. A retained
seven-key NSArray, three-capacity NSArray and synthetic dictionary preserve
distinct 5 GiB + 17, 7 GiB + 29 and 11 GiB + 43 NSNumber values across pool
drain; this collection check does not query a volume. Two runtime lifetimes
check isolated storage, retirement guards, callback access, zero live
objects and removal of all seven registrations. Generated C and assembly
review covers the fixture and both production runners.

Evidence and seven generated-C/executable pairs are retained under
`build/ios/fortnite/ns-url-total-capacity-checks`. The fresh production link
probe clears this import and stops before entry at
`_OBJC_EHTYPE_$_NSException`. Objective-C exception handling remains
unsupported. Fortnite remains unplayable; the full iOS regression is unpassed.

`_OBJC_EHTYPE_$_NSException` now resolves through Foundation and
CoreFoundation as a direct 24-byte type-info record. Native measurement and
[Apple's runtime ABI](https://github.com/apple-oss-distributions/objc4/blob/main/runtime/objc-exception.mm)
confirm its vtable, C string name and Class fields at offsets 0, 8 and 16.
Its shared vtable has the native zero/id type-info prefix, no-op destructors
and a catch-matching callback. An NSObject-derived NSException descriptor
supplies the Class identity; NSException API methods remain unsupported.
The inspected IPA contains 22 PC-relative exception-table references to
GOT slot `0x10dc9b218`.

One locked page holds the record, internal id type-info, fixed vtable and
names. Publication checks read-only protection before exposing the page.
Lookup and matching allocate nothing and create no Objective-C ownership.
Foreign exception types leave the pointer untouched; matching Objective-C
types adjust it before the class check, including failed and missing-class
matches. Internal id matching also accepts nil. The page stays available
through pool and Swift callbacks, then unmaps before class descriptors retire.
This metadata support does not implement throwing or stack unwinding.

`tests/ios/native-checks.v build-ns-exception-type` builds the fixture.
Six host ASan/UBSan runs pass the new fixture and existing total-capacity and
invalid-argument fixtures. The optimized ARM64 guest fixture also passes.
Native and runtime checks cover eight concurrent cold readers, shared
storage, base/subclass/unrelated and foreign types, weak/nil cases,
three- and four-argument callback ABIs, no-op destructors, unchanged live
object counts, isolated exception-name storage, retirement guards, pool
callback access and two drained/unmapped lifetimes. Generated C and assembly
review covers the fixture and both production runners.

Evidence and seven generated-C/executable pairs are retained under
`build/ios/fortnite/ns-exception-type-checks`, including native measurements,
the Apple source snapshot and preserved helper diagnostics. The fresh
production probe clears the type-info and class imports, then stops before
entry at `___NSArray0__`. Fortnite remains unplayable; the full iOS regression
is unpassed.

`___NSArray0__` now resolves through Foundation and CoreFoundation as a
read-only pointer cell containing an immutable empty NSArray. The separately
exported `___NSArray0__struct` returns the object directly. Native measurement
confirms these distinct addresses, a zero CF/NSArray count, nil first object,
immortal caller ownership and identity-preserving immutable copies. Mutable
copies are independent owned NSMutableArrays. The IPA has 12 inspected
consumer sites for GOT slot `0x10dc9b220`, including a second pointer load
and Objective-C retain calls.

The cache owns one ordinary array object and one sealed cell page. Lookup
publishes under the Objective-C initialization lock. Generic collection
mutators reject the singleton, while empty enumeration leaves output buffers
untouched. The cell and object survive pool and Swift context destruction;
shutdown removes caller immortality, releases the cache reference, and checks
the cell unmap before class descriptors retire.

`tests/ios/native-checks.v build-ns-empty-array` builds the new fixture. Six
host ASan/UBSan runs pass the empty-array, exception-type and constant-dictionary
fixtures. The optimized ARM64 guest fixture also passes. Checks cover eight
concurrent cold readers, both export forms and framework routes, copy and
equality/hash behavior, independent mutable copies, guarded empty enumeration,
seven rejected mutations, retained array/dictionary owners across pool drain,
weak loads, retirement guards, pool callback access and two drained/unmapped
runtime lifetimes with no remaining Objective-C objects. Generated C and
assembly review covers the fixture and both production runners.

Evidence and seven generated-C/executable pairs are retained under
`build/ios/fortnite/ns-empty-array-checks`, including native measurements and
the preserved build and review helper diagnostics. The fresh production probe clears
the empty-array import, then stops before entry at `_$s7SwiftUI13_VStackLayoutVMn`. Fortnite
remains unplayable; the full iOS regression is unpassed.

Inspection identifies the next import as a Swift nominal type descriptor:
one indirect context reference in `__TEXT,__swift5_typeref` at `0x10dc7fd3f`
uses relative field `0x10dc7fd40` to reach GOT cell `0x10dc9b2b8`. The encoding
agrees with the [Swift mangling ABI](https://github.com/swiftlang/swift/blob/main/docs/ABI/Mangling.rst),
whose source snapshot is retained with the evidence. SwiftUI remains unsupported.

`_$s7SwiftUI13_VStackLayoutVMn` now resolves only through SwiftUI.framework
to a distinct nongeneric nominal descriptor with a complete metadata accessor.
Native measurement and the SDK's frozen `_VStackLayout` declaration establish
an alignment word at offset 0 and optional CGFloat spacing at offset 8. The
value occupies 17 bytes with a 24-byte stride, POD/inline flags and no extra
inhabitants. The supplied IPA references the descriptor indirectly through
GOT cell `0x10dc9b2b8` from its Swift type-reference record at `0x10dc7fd3f`.

One locked allocation holds an RX accessor page and a read-only metadata page.
Every request returns the same complete metadata in x0/x1 while preserving
x20/x21. Copy/take/assignment witnesses transfer exactly 17 bytes and preserve
all seven padding bytes. Destruction is a no-op. Single-payload enum witnesses
preserve the native 17-byte payload, optional tag byte and UInt32 wrapping
behavior, including nonzero tag writes with a zero empty-case population.
No Objective-C ownership or dependent metadata cache is created by lookup.
Owned Swift buffers, heap objects and Array metadata retire before this arena
unmaps. Cached lookup remains available to earlier teardown callbacks.

`tests/ios/native-checks.v build-swiftui-vstack` builds the fixture. Six host
ASan/UBSan runs pass the new fixture, metadata-state lookup and Dispatch QoS
regressions. The optimized ARM64 guest fixture also passes. Native/runtime
checks cover eight cold readers, exact field offsets and layout, guarded
17-byte copies and unused inputs, enum populations and wrapping, indirect
symbolic type lookup, typed Array ownership, RX/RO protection, retirement
guards, callback access and two drained/unmapped lifetimes. Generated C and
assembly review covers the fixture and both production runners.

Evidence, native measurements, SDK/ABI source snapshots, preserved fixture
compiler diagnostics and seven generated-C/executable pairs are retained in
`build/ios/fortnite/swiftui-vstack-checks`. The fresh production probe clears
the descriptor import and stops before entry at `_$s7SwiftUI13_VariadicViewO4TreeVMn`. Field reflection,
public VStack accessors/constructors, layout/view conformances and SwiftUI
rendering remain unsupported. Fortnite remains unplayable; the full iOS
regression is unpassed.

The next required descriptor has two inspected indirect context references
in `__TEXT,__swift5_typeref`, at `0x10dc7fce8` and `0x10dc7fd38`, whose relative
fields at `0x10dc7fce9` and `0x10dc7fd39` target GOT cell `0x10dc9b2c0`.
No application code was executed during this inspection.

`_$s7SwiftUI13_VariadicViewO4TreeVMn` now resolves only through SwiftUI.framework
as a descriptor export for `SwiftUI._VariadicView.Tree`. Native measurement
and the SDK establish a generic struct with two type parameters, three key
arguments and the requirement `Root: _VariadicView_Root`. The nested enum,
module and protocol descriptor preserve that identity. The struct describes
two fields and a field-offset vector at metadata word five. The supplied IPA
has two indirect context references to this descriptor through GOT cell
`0x10dc9b2c0`, as recorded above.

This export supplies identity and the generic signature. Generic instantiation,
field reflection, the Root getter/default implementation and conformances
remain unsupported. There is no metadata cache or instantiation pattern.
The generic flag remains set, so type-name lookup rejects the descriptor
before reading its accessor. A direct accessor call reports
`iOS: SwiftUI Tree generic instantiation is not implemented` without inspecting
the supplied generic arguments. Native specialization measurements demonstrate
why this cannot reuse a fixed value layout: with `_VStackLayout` as Root,
Int Content gives a 32-byte value, while String Content gives a 40-byte value
with different ownership flags.

A locked allocation publishes one RX diagnostic-accessor page and one
read-only descriptor page. Lookup creates no Swift values, Objective-C owners
or dependent metadata caches. Cached descriptor access remains available to
teardown callbacks; the arena unmaps after owners and Array metadata drain.
`tests/ios/native-checks.v build-swiftui-tree` builds the fixture. Six host
ASan/UBSan runs pass Tree, metadata-state lookup and VStack checks with normal
and deterministic hashing. The optimized ARM64 fixture checks eight cold
readers, the native generic signature, direct/indirect symbolic rejection,
guarded name boundaries and arguments, explicit accessor diagnostics,
RX/RO protection, callback access and two drained/unmapped lifetimes.

Evidence, native specialization measurements, SDK/Swift ABI snapshots and
seven generated-C/executable pairs are retained in
`build/ios/fortnite/swiftui-tree-checks`. The guest fixture, production probe
and both import audits pass their scoped checks. Generated C and assembly
review covers the fixture and both production runners. Fortnite now stops
before entry at `_$s7SwiftUI13_ZStackLayoutVMn`; it remains unplayable, and
the full iOS regression is unpassed.

The next required descriptor has one indirect context reference in
`__TEXT,__swift5_typeref` at `0x10dc7fcef`. Its relative field at `0x10dc7fcf0`
targets GOT cell `0x10dc9b2c8` in `__DATA_CONST,__got`. This inspection executes
no application code.

`_$s7SwiftUI13_ZStackLayoutVMn` now resolves only through SwiftUI.framework
to a distinct nongeneric descriptor and complete metadata accessor. Native
measurements and the SDK's frozen declarations establish one Alignment field
at offset 0, containing horizontal and vertical alignment words. The value
is 16 bytes with a 16-byte stride, POD/inline flags and no extra inhabitants.
The supplied IPA references this descriptor through the GOT cell above.

A locked arena holds a sealed RX accessor page and read-only metadata page.
All requests return canonical complete metadata in x0/x1 while preserving
x20/x21. Five copy/take/assignment witnesses transfer exactly 16 bytes;
destruction is a no-op. Single-payload enum witnesses preserve native payload
and tag-byte behavior, including nonzero case writes with zero empty cases
and UInt32 wrapping. Lookup creates no Objective-C owners or dependent
metadata caches. Swift owners and Array metadata drain before the arena
unmaps; earlier teardown callbacks can still resolve its cached descriptor.

`tests/ios/native-checks.v build-swiftui-zstack` builds the fixture. Six host
ASan/UBSan runs pass ZStack, metadata-state lookup and VStack checks with
normal and deterministic hashing. Checks cover eight cold readers, native
layout/field metadata, guarded value copies and unused inputs, adjacent
canaries, enum populations and wrapping, indirect symbolic lookup, typed
Array ownership, sealed pages, retirement guards, callback access and two
drained/unmapped lifetimes. Field reflection, public ZStack accessors and
constructors, layout/view conformances and SwiftUI rendering remain unsupported.

The optimized ARM64 guest fixture and the scoped production probe/import
audits pass. Generated C and assembly review covers the fixture and both
production runners. Evidence, native measurements, SDK/Swift ABI snapshots,
the preserved evidence-tool ordering diagnostic and seven generated-C/executable
pairs are retained in `build/ios/fortnite/swiftui-zstack-checks`. The fresh
startup probe clears this descriptor import, then stops before entry at
`_$s7SwiftUI14_OpacityEffectVAA12ViewModifierAAWP`. Fortnite remains unplayable;
the full iOS regression is unpassed.

The next import is a protocol witness table, as identified by the retained
Swift mangling ABI. Its GOT cell is `0x10dc9b2d0`; the inspected load at
`0x1015c1304` places the pointer in an argument buffer before the call to
`_swift_getWitnessTable` at `0x1015c1314`. This path also references the
ModifiedContent View conformance descriptor. One consumer site was inspected
without executing application code.

`_$s7SwiftUI14_OpacityEffectVAA12ViewModifierAAWP` now resolves only through
SwiftUI.framework to a concrete, unconditional witness table.
`_$s7SwiftUI14_OpacityEffectVMn` resolves to its nominal descriptor in the same
arena. The ViewModifier declaration preserves its native signature, and the
table has six requirement slots. The opacity value has complete nongeneric
metadata with one Double field, an
8-byte POD size/stride and zero extra inhabitants. The associated Body slot
holds direct private metadata for Swift.Never: enum kind, zero cases, size
zero, stride one, POD/inline flags and no extra inhabitants. Its zero-size
witnesses share the measured Void operations without constructing a Void
metadata arena. Field reflection and public accessor/protocol exports
remain unsupported.

The read-only table supports ordinary static `_swift_getWitnessTable` and
direct `_swift_getAssociatedTypeWitness` lookup. Native Swift also reads the
compatibility table without modifying its associated-type slot. Four graph
requirements report an explicit unsupported-operation error. The associated
Never:View requirement uses native tagged `FF 07` relative-accessor data and
reports its own unsupported-conformance error. No incomplete View table or
rendering output is returned. The View and ViewModifier declarations retain
their Self.Body:View signatures; graph/default implementations and rendering
remain unsupported.

One locked allocation publishes RX metadata/diagnostic thunks and read-only
descriptors, value witnesses and the conformance table. Lookup creates no
Objective-C owner or dependent metadata arena. Swift owners and Array metadata
drain before unmapping; earlier teardown callbacks can read the cached table
and associated Body metadata.

`tests/ios/native-checks.v build-swiftui-opacity` builds the fixture. Six host
ASan/UBSan runs pass opacity, static witness lookup and CocoaError protocol
checks with normal and deterministic hashing. Checks include eight cold
readers, native protocol/layout comparisons, signed native static lookup,
native direct associated-type lookup, guarded POD/zero-size copies and enum
width boundaries/UInt32 wrapping, complete accessor context preservation,
all graph/associated-conformance error paths, typed Array storage without
constructing Never values, sealed pages, callbacks and two drained lifetimes.

The optimized ARM64 fixture, startup probe and both production import audits
pass. Generated C and assembly review covers the host/guest fixture and both
production runners. Native measurements, SDK/Swift ABI snapshots, six sanitizer
logs, four final guest runs and seven generated-C/executable pairs are retained
in `build/ios/fortnite/swiftui-opacity-checks`. The earlier witness-only checkpoint
and both fixture compiler diagnostics are preserved separately. The final probe
clears both opacity imports, then stops before entry at
`_$s7SwiftUI15ModifiedContentVMn`. Fortnite remains unplayable; the full iOS
regression is unpassed.

The next import is a generic nominal descriptor. Its GOT cell is
`0x10dc9b2e0` in `__DATA_CONST,__got`; nine indirect context symbolic references
in `__TEXT,__swift5_typeref` point to that cell. This inspection executed no
application code and does not establish ModifiedContent support.

`_$s7SwiftUI15ModifiedContentVMn` now resolves only through SwiftUI.framework
to a distinct, sealed nominal descriptor. Native measurements and the SDK's
frozen declaration establish a generic struct in the SwiftUI module with two
unconstrained type parameters, two key arguments and no generic requirements.
It declares two fields with their offset vector at metadata word four.
Native Int/Int, String/Int and Never/String specializations confirm that
layout, ownership flags and extra inhabitants depend on those arguments.

This export supplies nominal identity and the generic signature. It supplies
no complete specialization metadata, value witnesses, field reflection,
instantiation cache/pattern or View conformance. The descriptor's generic bit
makes direct and indirect symbolic lookup reject before reading its accessor
or protected generic arguments. Calling its diagnostic accessor reports
`iOS: SwiftUI ModifiedContent generic instantiation is not implemented`.

One locked allocation publishes an RX diagnostic page and read-only descriptor
page. Construction creates no Swift/Objective-C owners or dependent metadata
arenas. Earlier teardown callbacks can still resolve the cached descriptor;
Swift owners and Array metadata drain before unmapping it.

`tests/ios/native-checks.v build-swiftui-modified` builds the fixture. Six host
ASan/UBSan runs pass ModifiedContent, mangled-state lookup and Tree checks with
normal and deterministic hashing. Checks include eight cold readers, the native
generic signature, direct/indirect bounded symbolic references, protected
arguments, four diagnostic requests, sealed pages, retirement guards, callback
access and two drained/unmapped lifetimes. Generic instantiation and SwiftUI
rendering remain unsupported.

The optimized ARM64 fixture, startup probe and both production import audits
pass. Generated C and assembly review covers the host/guest fixture and both
production runners. Native measurements, SDK/Swift ABI snapshots, six sanitizer
logs, four guest runs and seven generated-C/executable pairs are retained in
`build/ios/fortnite/swiftui-modified-checks`, along with the corrected fixture
generator's original diagnostic. The fresh probe clears the nominal descriptor
import, then stops before entry at
`_$s7SwiftUI15ModifiedContentVyxq_GAA4ViewA2aERzAA0E8ModifierR_rlMc`,
ModifiedContent's conditional View conformance. Fortnite remains unplayable;
the full iOS regression is unpassed.

The next import's GOT cell is `0x10dc9b2e8`. Loads at `0x1015c1310` and
`0x1015c1784` pass the descriptor as x0 to `_swift_getWitnessTable` at
`0x1015c1314` and `0x1015c1788`, with specialization metadata in x1 and
conditional witness arguments in x2. Two consumer sites were inspected without
executing application code.

`_$s7SwiftUI15ModifiedContentVyxq_GAA4ViewA2aERzAA0E8ModifierR_rlMc`
now resolves only through SwiftUI.framework to a conditional conformance
descriptor in the existing ModifiedContent arena. Its type reference points
to the same canonical nominal descriptor. Native measurements establish flags
`0x20200` and two key protocol requirements: `Content: View` (`x`) and
`Modifier: ViewModifier` (`q_`). Both protocol declarations retain six
requirements and their `Self.Body: View` signatures.

The native record has a seven-word pattern and two private conditional witness
arguments. The compatibility declaration retains the conditional/generic flags
and private-argument count, supplies no pattern and uses zero copied words with
a diagnostic instantiator. The retained Swift runtime source permits this
instantiator-only profile and a null out-of-line cache. No writable cache or
complete witness table is supplied. Ordinary `_swift_getWitnessTable` continues
to reject conditional/generic records before reading metadata, arguments or
the pattern; directly calling the instantiator reports
`iOS: SwiftUI ModifiedContent View witness instantiation is not implemented`.

The shared allocation remains RX/RO and creates no dependent metadata arena
or Swift/Objective-C owner. Cached declaration lookup remains available during
earlier teardown callbacks; owners and Array metadata drain before unmapping.
`tests/ios/native-checks.v build-swiftui-modified-view` builds the fixture.
Six host ASan/UBSan runs pass conditional conformance, existing witness lookup
and nominal ModifiedContent checks with normal and deterministic hashing.
They cover native requirements/control measurements, eight cold readers,
canonical shared identity, sealed pages, protected unused arguments, both
explicit error paths, callbacks and two drained/unmapped lifetimes. Witness
specialization, generic ModifiedContent instantiation and rendering remain
unsupported.

The optimized ARM64 fixture, startup probe and both production import audits
pass. Generated C and assembly review covers the host/guest fixture and both
production runners. Native measurements, SDK/Swift ABI/runtime snapshots,
six sanitizer logs, four guest runs and seven generated-C/executable pairs are
retained in `build/ios/fortnite/swiftui-modified-view-checks`. The fresh probe
clears the conformance descriptor import, then stops before entry at
`_$s7SwiftUI18LocalizedStringKeyV13stringLiteralACSS_tcfC`.
Fortnite remains unplayable; the full iOS regression is unpassed.

The next initializer's GOT cell is `0x10dc9b2f0`, with stub `0x10c63aa7c`
and branch forwarder `0x107c28eb4`. Calls at `0x1015bfd40` and `0x1015c019c`
follow Swift string-literal construction and feed the resulting key into a
SwiftUI Text initializer. The two call sites and one forwarder were inspected
without executing application code.

`_$s7SwiftUI18LocalizedStringKeyV13stringLiteralACSS_tcfC` now resolves only
through SwiftUI.framework to the literal-key initializer. Native measurements
show a 32-byte frozen value with String at offset 0, `hasFormatting` at 16 and
an arguments Array at 24. The initializer consumes the String by transferring
its two words unchanged, returns false for formatting, and supplies the
canonical immortal empty Array. Unicode, embedded NULs and percent characters
are preserved without parsing or rewriting.

Swift returns this value in x0/x1/w2/x3. The sealed ARM64 entry leaves the
input String in x0/x1, clears x2 and loads the existing empty Array into x3.
It reads no input bytes, indirect-result storage or Swift context registers;
there is no per-call allocation, retain or release. Owned String reference
counts remain unchanged until the returned key is destroyed. Cold lookup
creates one RX page and reuses the existing empty Array singleton. Earlier
teardown callbacks can still use the cached entry; shutdown retires the entry
before unmapping that singleton.

`tests/ios/native-checks.v build-swiftui-localized-key` builds the fixture.
Six host ASan/UBSan runs pass literal keys, String interpolation and empty
Arrays with normal and deterministic hashing. The native comparison covers
direct result registers, preserved x20/x21, protected x8 and opaque input
spans, inline/immortal/owned String forms,
unchanged alias reference counts and canonical empty arguments. Checks also
cover eight cold readers, 600 released owned calls, sealed pages, callbacks
and two drained/unmapped lifetimes. Localized lookup, key interpolation,
public key metadata and Text rendering remain unsupported.

The optimized ARM64 fixture, launch probe and both import audits pass their
expected checks. The probe clears the literal-key import and stops before
entry at `_$s7SwiftUI19HorizontalAlignmentV6centerACvgZ`; its child exit status
remains 1. Generated C and ARM64 disassembly review covers both fixture
variants and both production runners, including unchanged String ownership
and entry retirement before empty Array storage. Seven executable/generated-C
artifact pairs, native results and sanitizer/guest logs are archived under
`build/ios/fortnite/swiftui-localized-key-checks`. A full-disk interruption
affected static-audit archive construction before boot; its partial archive
hash, failed integrity check and recovery diagnostics are retained. Only
that phase was rerun, and its recovered run passed.

The next required import's actual main-image fixup is at `0x10dc9b2f8`, with
stub `0x10c63aa88`, forwarder `0x107c28ed8` and one inspected call at
`0x1015c0564`. The call wrapper returns the horizontal alignment getter's
result directly. These two consumer/forwarder sites were inspected without
executing application code; that probe still stopped before application entry.

`_$s7SwiftUI19HorizontalAlignmentV6centerACvgZ` and
`_$s7SwiftUI9AlignmentV6centerACvgZ` now resolve only through SwiftUI.framework.
Native SDK declarations and three fresh native processes confirm that
HorizontalAlignment is an 8-byte POD identity and Alignment is a 16-byte POD
pair with fields at 0 and 8. The getters return directly in x0 and x0/x1,
preserve x20/x21 and never use indirect-result memory.

AlignmentKey is an integer identity, not a pointer. Native center keys differ
with initialization order, while bit 0 remains 0 for horizontal and 1 for
vertical. The compatibility runtime reserves identities 1 and 2 for the two
center axes (encoded as 2 and 5); both getters share the horizontal key.
Future alignment registrations must allocate distinct identities starting
at 3. These getters have no allocation, ARC, metadata or runtime storage
dependency, so their values and entry points survive runtime shutdown.
Custom alignment IDs, public alignment metadata and layout remain unsupported.

`tests/ios/native-checks.v build-swiftui-alignment` builds the center fixture.
Six host ASan/UBSan runs pass center getters, ZStack metadata and localized
string keys with normal and deterministic hashing. The center checks cover
16,384 concurrent iterations, exact framework routing, protected x8,
preserved Swift context registers, component consistency and two drained
lifetimes, including callbacks and post-shutdown calls. The initial fixture
assumed a retirement flag was already set before deallocation callbacks;
that setup was corrected and the failing source, executable/generated C and
logs are retained with hashes in `callback-fixture-diagnostic` under
`build/ios/fortnite/swiftui-alignment-checks`.

The optimized ARM64 center fixture, launch probe and both import audits pass
their expected checks. Both center imports are cleared; the probe remains
before entry with child status 1 at
`_$s7SwiftUI19UIViewRepresentablePAAE09dismantleC0_11coordinatory0C4TypeQz_11CoordinatorQztFZ`.
Its actual main-image fixup is `0x10dc9b300`, stub `0x10c63aa94`, forwarder
`0x107c28e30` and call `0x1015be63c`. The call wrapper forwards the default
UIViewRepresentable teardown operation and returns. These two consumer/forwarder
sites were inspected without executing application code; that probe stopped
at the teardown import. Generated C and ARM64 disassembly review covers both
fixture variants and both production runners. Seven executable/generated-C
artifact pairs and the joined validation logs are archived in the same cohort.

`_$s7SwiftUI19UIViewRepresentablePAAE09dismantleC0_11coordinatory0C4TypeQz_11CoordinatorQztFZ`
now resolves through SwiftUI.framework to the empty protocol-extension default.
The hook borrows its view and generic coordinator; it accesses no arguments,
metadata, witness tables, indirect results or Swift context storage. It performs
no allocation, ARC, custom witness dispatch or view-hierarchy removal and has
no runtime storage dependency.

Apple's [default-hook declaration](https://developer.apple.com/documentation/swiftui/uiviewrepresentable/dismantleuiview(_:coordinator:)-94s0o)
and the installed Mac Catalyst SDK establish its signature. The pinned
[OpenSwiftUI default](https://github.com/OpenSwiftUIProject/OpenSwiftUI/blob/da91cd90de7285da284e785d9b0376bf78ae5809/Sources/OpenSwiftUI/Integration/Representable/UIKit/UIViewRepresentable.swift#L217)
corroborates an empty hook. The available native NSViewRepresentable counterpart
is a single `ret` and passes 4,000 calls with protected borrowed arguments.
The UIKit symbol is unavailable in this Mac runtime; UIKit execution was not
measured natively. The compatibility implementation follows the empty-default
contract, with that native-comparison limit recorded in the evidence.

`tests/ios/native-checks.v build-swiftui-dismantle` builds the fixture. Six
host ASan/UBSan runs pass the default hook, center alignments and Objective-C
supplied storage with normal and deterministic hashing. The hook checks
16,384 concurrent calls, 600 borrowed ownership cycles with unchanged aliases,
read-only coordinator storage at a protected boundary, untouched x8 and
preserved x0-x3/x20/x21, callbacks and two drained runtime lifetimes.

Evidence is retained under `build/ios/fortnite/swiftui-dismantle-checks`.
The storage regression resumed after restoring its archived native C++
fixture into this cohort; its initial missing-library failure is preserved
in `regression-fixture-diagnostic`. A source-fetch HTTP 403 and the verified
snapshot recovery are recorded separately. Build and VM staging use an owned
4 GiB RAM volume after host disk exhaustion; completion verifies retained
files on the repository filesystem before detaching it.

The launch probe clears the default teardown import and remains before entry,
with child exit status 1, at
`_$s7SwiftUI19UIViewRepresentablePAAE12sizeThatFits_6uiView7contextSo6CGSizeVSgAA08ProposedI4SizeV_0C4TypeQzAA0cD7ContextVyxGtF`.
Its main-image fixup is `0x10dc9b308`, stub `0x10c63aaa0`, forwarder
`0x107c28e3c` and call `0x1015be6d0`. The wrapper forwards the proposal and
normalizes the optional result's tag in w2 after the call. These two
consumer/forwarder sites were inspected without executing application code;
the sizing default remains unsupported.

The optimized ARM64 fixture, launch probe and both import audits pass their
expected checks. Generated C and ARM64 disassembly review covers both fixture
variants and both production runners, including the empty body and direct
return without argument or ownership operations. Seven executable/generated-C
artifact pairs, native/source evidence and joined logs are retained.

`_$s7SwiftUI19UIViewRepresentablePAAE12sizeThatFits_6uiView7contextSo6CGSizeVSgAA08ProposedI4SizeV_0C4TypeQzAA0cD7ContextVyxGtF`
now resolves through SwiftUI.framework to the protocol-extension default that
returns no preferred size. Its V ARM64 entry returns `Optional<CGSize>.none`
in x0/x1/w2 (0/0/1); a C aggregate return would use indirect result storage.
The entry accesses no proposal, view, context, metadata or witness storage,
performs no ownership operations or allocation, and remains callable after
runtime shutdown. Custom sizing and layout remain unsupported.

The installed UIKit and AppKit SDK declarations establish the optional-size
signature. The pinned
[OpenSwiftUI default](https://github.com/OpenSwiftUIProject/OpenSwiftUI/blob/da91cd90de7285da284e785d9b0376bf78ae5809/Sources/OpenSwiftUI/Integration/Representable/UIKit/UIViewRepresentable.swift#L247)
returns nil. The native NSViewRepresentable counterpart returns the measured
0/0/1 registers in four instructions and passes 2,048 protected-argument calls.
UIKit execution remains unverified: this Mac has no available native UIKit
entry for the comparison. Native and SDK/source evidence is retained under
`build/ios/fortnite/swiftui-sizing-checks`.

`tests/ios/native-checks.v build-swiftui-sizing` builds the fixture. Six host
ASan/UBSan runs pass sizing, dismantling and center alignments with normal
and deterministic hashing. The sizing fixture also passes in the optimized
ARM64 guest: 16,384 concurrent calls, 600 borrowed ownership cycles with
unchanged Objective-C/Swift aliases, nil/finite/infinite/NaN proposals,
read-only context storage at a protected boundary, protected x8, preserved
x3-x7/x20/x21/d0/d1, callbacks and two drained runtime lifetimes.

The launch probe clears the sizing default and stops before entry, with child
status 1, at
`_$s7SwiftUI19UIViewRepresentablePAAE13_makeViewList4view6inputsAA01_fG7OutputsVAA11_GraphValueVyxG_AA01_fG6InputsVtFZ`.
Its main-image fixup is `0x10dc9b310`, stub `0x10c63aaac`, forwarder
`0x107c28e54` and call `0x1015be814`. The wrapper obtains a protocol witness
table and forwards indirect view-list result storage in x8. These two
consumer/forwarder sites were inspected without executing application code;
view-list graph construction remains unsupported.

The sizing fixture, launch probe and both import audits pass their expected
checks. Generated C and ARM64 disassembly review covers both fixture variants
and both production runners, including the three result-register writes and
direct return without ownership or memory access. Seven executable/generated-C
artifact pairs and joined validation logs are archived in the same cohort.

`_$s7SwiftUI19UIViewRepresentablePAAE13_makeViewList4view6inputsAA01_fG7OutputsVAA11_GraphValueVyxG_AA01_fG6InputsVtFZ`
now has a diagnostic binding. Calling it terminates with
`iOS: SwiftUI UIViewRepresentable view-list graph construction is not implemented`.
The handler accesses no graph, inputs, metadata, witness, Swift self or indirect
result storage. It never returns an uninitialized `_ViewListOutputs` and requires
no runtime-owned storage. Unary graph construction remains unsupported.

The installed UIKit/AppKit SDK declarations and pinned OpenSwiftUI source
identify this as a unary graph-list factory. The native AppKit wrapper loads
the inherited View witness from x3+8 and tail-calls framework machinery.
Only its instructions were inspected; no native graph factory was executed,
and the UIKit entry is unavailable on this Mac. Evidence is retained under
`build/ios/fortnite/swiftui-view-list-checks`.

`tests/ios/native-checks.v build-swiftui-view-list` builds the fixture. Six
host ASan/UBSan runs pass the diagnostic entry, sizing default and Tree
descriptor with normal and deterministic hashing. Each diagnostic fixture
run checks 20 child calls that exit 1 with the exact error, protected input
and x8 pointers, unchanged shared read-only/writable result pages next to a
protected boundary, 16,384 concurrent resolutions, exact framework routing,
callback access and two drained runtime lifetimes.

The optimized ARM64 guest fixture passes the same diagnostic and shared-result
checks. The launch probe binds `_makeViewList` and remains before application
entry, with child status 1, at
`_$s7SwiftUI19UIViewRepresentablePAAE14_layoutOptionsyAA013_PlatformViewd6LayoutF0V0C4TypeQzFZ`.
Its main-image fixup is `0x10dc9b318`, stub `0x10c63aab8`, forwarder
`0x107c28e4c` and call `0x1015be728`. These two consumer/forwarder sites were
inspected without executing application code.

The fixture, launch probe and both audits pass their expected checks. Generated
C and ARM64 disassembly review covers both fixture variants and both production
runners: a terminal diagnostic with no graph/result/context dereference or
ownership operations. Seven executable/generated-C artifact pairs and joined
validation logs are archived in the same cohort.

`_$s7SwiftUI19UIViewRepresentablePAAE14_layoutOptionsyAA013_PlatformViewd6LayoutF0V0C4TypeQzFZ`
now resolves to the default option-producing hook. It initializes `rawValue`
to 1 in eight bytes of caller-owned storage supplied through x8. The current
resilient option set stores one Int; its Swift return ABI remains indirect.
The V ARM64 entry has no borrowed-view, metadata or witness accesses, ownership
operations, allocation or runtime-storage dependency. Custom options and
SwiftUI layout/graph execution remain unsupported.

Native metadata reports POD size/stride/alignment 8/8/8. The option-set
constructor and getter round-trip rawValue 1 across 1,024 protected-boundary
cases, and 1,024 native AppKit defaults also return 1 through x8. Only the
eight result bytes change; protected borrowed arguments remain untouched and
x20/x21 are preserved. The installed UIKit declaration confirms the resilient
Int-backed type; the pinned OpenSwiftUI default corroborates rawValue 1.
UIKit execution remains unverified because
its entry is unavailable on this Mac. Evidence is retained under
`build/ios/fortnite/swiftui-layout-options-checks`.

The dedicated fixture passes normal and deterministic ASan/UBSan host runs
with its result hook compiled at O2, plus the optimized ARM64 guest run. It
checks both protected result-page boundaries, 16,384 concurrent calls across
eight readers and two runtime lifetimes, 600 borrowed UIView ownership cycles,
a read-only provider next to an inaccessible page, protected metadata/witness
arguments, exact framework routing, and calls during and after teardown.
Only the eight result bytes change; x0-x3/x8/x20/x21 remain intact. Host sizing
and view-list diagnostic regressions also pass normal and deterministic
sanitizer runs. The public test driver accepts the new fixture and rejects
an unknown fixture.

The fresh launch probe links past the layout-options import and exits 1
before application entry at the next required SwiftUI import,
`_$s7SwiftUI19UIViewRepresentablePAAE19_identifiedViewTree2inAA011_IdentifiedfG0O0C4TypeQz_tF`.
Its main-image fixup is `0x10dc9b320`, stub `0x10c63aac4`, forwarder
`0x107c28e38` and call `0x1015be664`. These two consumer/forwarder sites were
inspected without executing application code. Fortnite remains unplayable.

The fixture, launch probe and both import audits pass their expected checks.
Generated C and ARM64 disassembly review of both fixture variants and both
production runners confirms a constant eight-byte store through x8 and return,
with no frame, borrowed argument/context reads, ownership, allocation or
runtime-storage dependency. Seven executable/generated-C artifact pairs and
joined validation logs are archived in the same cohort.

`_$s7SwiftUI19UIViewRepresentablePAAE19_identifiedViewTree2inAA011_IdentifiedfG0O0C4TypeQz_tF`
now has an exact SwiftUI diagnostic binding. Calling it terminates with
`iOS: SwiftUI UIViewRepresentable identified-view tree result is not implemented`
before accessing the borrowed view, Swift self, metadata, witnesses or x8
result storage. This does not construct an empty tree. The resilient enum's
metadata and value witnesses, nonempty trees and application rendering remain
unsupported.

The pinned UIKit default returns `.empty`, but that semantic value is not a
zero pointer. Native AppKit metadata reports non-POD size/stride/alignment
169/176/8; the default obtains enum metadata and constructs an indirect result
through x8. Its current representation has 168 zero payload bytes followed
by tag 2. UIKit execution and layout remain unverified: this Mac cannot load
the Catalyst SwiftUI entry into the host process. The compatibility hook does
not copy this platform-specific layout. Evidence is retained under
`build/ios/fortnite/swiftui-identified-tree-checks`.

The native default passes 1,024 cases with result storage at both protected
page boundaries. Only those 169 bytes change, the native enum tag getter
reports 2, and the native destroy witness accepts each result. Inaccessible
borrowed arguments are untouched and x20/x21 remain intact. These are AppKit
observations; they do not verify UIKit's private enum layout.

The diagnostic fixture passes normal and deterministic ASan/UBSan host runs
with the primary hook compiled at O2, and an optimized ARM64 guest run. Each
primary run checks 20 child calls exiting 1 with the exact enum diagnostic,
inaccessible provider/metadata/witness/self/x8 arguments, and unchanged shared
read-only and writable result pages next to an inaccessible page. Eight
readers perform 16,384 concurrent resolutions across two drained runtime
lifetimes, including teardown callbacks. Layout-options and view-list host
regressions also pass normal and deterministic sanitizer runs. The public
driver selects the new fixture and rejects an unknown fixture.

The fresh launch probe links past this diagnostic binding and exits 1 before
application entry at the next required SwiftUI import,
`_$s7SwiftUI19UIViewRepresentablePAAE21_overrideLayoutTraits_3foryAA01_fG0Vz_0C4TypeQztF`.
Its main-image fixup is `0x10dc9b328`, stub `0x10c63aad0`, forwarder
`0x107c28e44` and call `0x1015be700`. These two consumer/forwarder sites were
inspected without executing application code. This does not establish that
the identified-tree method can execute; Fortnite remains unplayable.

The fixture, launch probe and both audits pass their expected checks.
Generated C and ARM64 disassembly review covers both fixture variants and
both production runners: a terminal diagnostic with no provider/result/context
dereference or ownership operations. Seven executable/generated-C artifact
pairs and joined validation logs are archived in the same cohort.

`_$s7SwiftUI19UIViewRepresentablePAAE21_overrideLayoutTraits_3foryAA01_fG0Vz_0C4TypeQztF`
now resolves to the extension's empty default. It leaves caller-owned inout
traits unchanged and does not access the borrowed view, Swift self, generic
metadata/witnesses or x8 storage. Custom trait overrides, layout and graph
execution remain unsupported.

The native AppKit counterpart is a single `ret`. It passes 4,000 calls with
protected arguments and 2,048 read-only/writable inout boundary calls with
every byte unchanged and x0-x3/x8/x20/x21 preserved. The installed SDK declares
the traits argument inout, and the pinned OpenSwiftUI UIKit source marks this
default as empty. UIKit execution remains unverified because its entry is
unavailable on this Mac. Evidence is retained under
`build/ios/fortnite/swiftui-layout-traits-checks`.

The dedicated fixture passes normal and deterministic ASan/UBSan host runs
with its default hook compiled at O2, plus the optimized ARM64 guest run. It
checks 16,384 concurrent calls across eight readers and two runtime lifetimes,
600 ownership cycles with unchanged ObjC/Swift aliases, unchanged read-only
and writable traits buffers at both protected boundaries, read-only Swift
self storage, protected metadata/witness/x8 arguments, exact framework
routing, and calls during and after teardown. Host layout-options and
identified-tree diagnostic regressions also pass normal and deterministic
sanitizer runs. The public driver selects the new fixture and rejects an
unknown fixture.

The fresh launch probe links past the layout-traits default and exits 1
before application entry at the next required SwiftUI import,
`_$s7SwiftUI19UIViewRepresentablePAAE21_overrideSizeThatFits_2in6uiViewySo6CGSizeVz_AA09_ProposedF0V0C4TypeQztF`.
Its main-image fixup is `0x10dc9b330`, stub `0x10c63aadc`, forwarder
`0x107c28e40` and call `0x1015be6ec`. These two consumer/forwarder sites were
inspected without executing application code. Fortnite remains unplayable.

The layout-traits fixture, launch probe and both audits pass their expected
checks. Generated C and ARM64 disassembly review of both fixture variants and
both production runners confirms an empty hook and one `ret`, with no
argument/result/context access, ownership operations, allocation, runtime
storage or custom witness dispatch. Seven executable/generated-C artifact
pairs and joined validation logs are archived in the same cohort.

`_$s7SwiftUI19UIViewRepresentablePAAE21_overrideSizeThatFits_2in6uiViewySo6CGSizeVz_AA09_ProposedF0V0C4TypeQztF`
now resolves to the extension's empty default. It preserves every bit of the
caller-owned inout CGSize and does not access the proposal, view, Swift self,
generic metadata/witnesses or x8 storage. Custom sizing overrides, layout and
graph execution remain unsupported.

The native AppKit counterpart is a single `ret`. It passes 4,000 protected
proposal calls and 2,048 read-only/writable CGSize boundary calls, including
NaNs, negative zero and infinities. Size bits and x0-x8/x20/x21/d0/d1 remain
unchanged. The SDK declares an inout CGSize and a proposed-size value; the
pinned OpenSwiftUI UIKit source marks this default as empty. UIKit execution
remains unverified because its entry is unavailable on this Mac. Evidence is
retained under `build/ios/fortnite/swiftui-size-override-checks`.

The dedicated fixture passes normal and deterministic ASan/UBSan host runs
with its default compiled at O2, plus the optimized ARM64 guest run. It checks
16,384 concurrent calls across eight readers and two runtime lifetimes, 600
ownership cycles with unchanged ObjC/Swift aliases, unchanged read-only and
writable CGSize bits at both protected boundaries, nil/finite/infinite/NaN
proposals, read-only Swift self storage, protected metadata/witness/x8,
x0-x8/x20/x21/d0/d1, exact framework routing, and calls during and after
teardown. Layout-traits and sizeThatFits host regressions also pass normal
and deterministic sanitizer runs.

The initial public-driver check used a fixture table compiled before
registration; that failure is archived under `public-route-stale-build`.
Rebuilding from the registered source passes both valid and unknown fixture
routing checks. The build helper now requires registration before compiling
this driver.

The fresh launch probe links past the size-override default and exits 1
before application entry at the next required SwiftUI import,
`_$s7SwiftUI19UIViewRepresentablePAAE24_modifyBridgedViewInputsyyAA01_gH0VzFZ`.
Its main-image fixup is `0x10dc9b338`, stub `0x10c63aae8`, forwarder
`0x107c28e48` and call `0x1015be714`. These two consumer/forwarder sites were
inspected without executing application code. Fortnite remains unplayable.

The size-override fixture, launch probe and both audits pass their expected
checks. Generated C and ARM64 disassembly review of both fixture variants and
both production runners confirms an empty hook and one `ret`, with no
argument/result/context access, ownership operations, allocation, runtime
storage or custom witness dispatch. Seven executable/generated-C artifact
pairs and joined validation logs are archived in the same cohort.

The required SwiftUI import
`_$s7SwiftUI19UIViewRepresentablePAAE24_modifyBridgedViewInputsyyAA01_gH0VzFZ`
now resolves to the static extension's empty default. It leaves the opaque
inout `_ViewInputs` storage unchanged and does not read metadata, witnesses,
Swift contexts or x8 storage. It does not dispatch custom representable
implementations or assume a private `_ViewInputs` layout.

The native AppKit counterpart is a single `ret`. It passes 4,000 calls with
protected arguments and 2,048 calls with read-only/writable input buffers at
both protected boundaries, preserving every buffer byte and
x0-x3/x8/x20/x21. The SDK declares the static inout method; the pinned
OpenSwiftUI UIKit source supplies an empty body. Native UIKit execution
remains unverified because its entry is unavailable on this Mac. Evidence is
retained under `build/ios/fortnite/swiftui-bridged-inputs-checks`.

The dedicated fixture passes normal and deterministic ASan/UBSan host runs
with the default compiled at O2, plus the optimized ARM64 guest run. It
checks 16,384 concurrent calls across eight readers and two runtime
lifetimes, 600 ownership cycles with unchanged ObjC/Swift aliases,
read-only/writable input bytes at both protected boundaries, protected
metadata/witness/x8/contexts, x0-x3/x8/x20/x21, exact framework routing, and
calls during and after teardown. The borrowed payload is a test fixture,
not a model of private `_ViewInputs`. Layout-traits and size-override host
regressions also pass normal and deterministic sanitizer runs. Public
fixture routing passes after registration, including rejection of an
unknown fixture.

The fresh launch probe links past the bridged-inputs default and exits 1
before application entry at the next required import,
`_$s7SwiftUI19UIViewRepresentablePAAE4bodys5NeverOvg`. Its main-image fixup is
`0x10dc9b340`, stub `0x10c63aaf4`, forwarder `0x107c28e5c` and call
`0x1015be858`, followed by a `brk`. These two consumer/forwarder sites were
inspected without executing application code. Fortnite remains unplayable.

The bridged-inputs fixture, launch probe and both audits pass their expected
checks. Generated C and ARM64 disassembly review of both fixture variants
and both production runners confirms an empty hook and one `ret`, with no
input/result/context access, ownership operations, allocation, runtime
storage or custom witness dispatch. Seven executable/generated-C artifact
pairs and joined validation logs are archived in the same cohort.

The required SwiftUI import
`_$s7SwiftUI19UIViewRepresentablePAAE4bodys5NeverOvg` now resolves to the
primitive `Body == Never` getter. Calling it writes a fixed diagnostic and
traps with `BRK`/`SIGTRAP`, including when stderr is closed. It does not
return a value or access caller metadata, witnesses, Swift self or x8.
Native generic type-name reporting and crash annotations remain unsupported.

The native AppKit counterpart projects the inherited View witness from
x1, calls its failure path and has a trailing `brk #1`. Two child probes
deliver `SIGTRAP`, with normal and closed stderr. They use valid native
EmptyView metadata/View conformance in a read-only surrogate witness
projection, with protected self/x8; no NSView object is constructed. The
normal diagnostic says the body must not be called on EmptyView. The SDK
declares a `Swift.Never` result, and the pinned OpenSwiftUI UIKit source
calls `bodyError()`. Native UIKit execution remains unverified because its
entry is unavailable on this Mac. Evidence is retained under
`build/ios/fortnite/swiftui-body-checks`.

The dedicated fixture passes normal and deterministic ASan/UBSan host runs
with the getter compiled at O2, plus the optimized ARM64 guest run. Each
run checks 24 child calls that deliver `SIGTRAP` without returning, the
fixed diagnostic and closed-stderr path, nil/protected/invalid metadata,
witnesses and self, protected x8, and unchanged shared read-only/writable
pages at a protected boundary. Eight readers complete 16,384 concurrent
resolutions across two runtime lifetimes, with exact framework routing,
teardown callbacks and calls after shutdown. Bridged-inputs and view-list
host regressions also pass normal and deterministic sanitizer runs. Public
fixture routing passes, including rejection of an unknown fixture.

The fresh launch probe links past the body getter and exits 1 before
application entry at the next required SwiftUI import,
`_$s7SwiftUI19UIViewRepresentablePAAE9_makeView4view6inputsAA01_F7OutputsVAA11_GraphValueVyxG_AA01_F6InputsVtFZ`.
Its main-image fixup is `0x10dc9b348`, stub `0x10c63ab00`, forwarder
`0x107c28e50` and call `0x1015be768`. These two consumer/forwarder sites were
inspected without executing application code. SwiftUI graph construction
remains unsupported, and Fortnite remains unplayable.

The body fixture, launch probe and both audits pass their expected checks.
Generated C and ARM64 disassembly review of both fixture variants and both
production runners confirms a fixed diagnostic followed by `brk #1`, with
no return, caller-storage access, ownership operations, allocation or
runtime storage. Seven executable/generated-C artifact pairs and joined
validation logs are archived in the same cohort.

The required SwiftUI import
`_$s7SwiftUI19UIViewRepresentablePAAE9_makeView4view6inputsAA01_F7OutputsVAA11_GraphValueVyxG_AA01_F6InputsVtFZ`
now has a diagnostic binding. Calling it exits 1 with an explicit view graph
construction diagnostic before reading graph/inputs/metadata/witness/self
or writing caller-owned x8 storage. It does not create a view, synthesize
`_ViewOutputs`, dispatch a custom witness or provide rendering.

The native AppKit factory requests PlatformViewRepresentableAdaptor
metadata and preserves the indirect result pointer from x8 for downstream
calls. Its instructions were inspected through its authenticated return;
the factory was not executed. The SDK declares graph-value/input arguments
and a `_ViewOutputs` result. The pinned OpenSwiftUI UIKit source conditionally
checks the representable's value type and delegates to the platform adapter's
factory. The platform adapter, graph engine and resilient result remain
unsupported. Native UIKit execution is unverified because its entry is
unavailable on this Mac. Evidence is retained under
`build/ios/fortnite/swiftui-view-factory-checks`.

The dedicated fixture passes normal and deterministic ASan/UBSan host runs
with the entry compiled at O2, plus the optimized ARM64 guest run. It checks
32 child calls that exit 1 with the graph diagnostic, protected graph,
inputs, metadata, witnesses, self and x8, and unchanged shared read-only and
writable result pages at both protected boundaries. These fixture offsets
do not specify the private `_ViewOutputs` layout. Eight readers complete
16,384 concurrent resolutions across two runtime lifetimes, with exact
framework routing, teardown callbacks and calls after shutdown. The body
and view-list host regressions also pass normal and deterministic sanitizer
runs. Public fixture routing passes, including rejection of an unknown
fixture.

The fresh launch probe links past the factory binding and exits 1 before
application entry at the required `Coordinator == Void` default,
`_$s7SwiftUI19UIViewRepresentablePAAyt11CoordinatorRtzrlE04makeE0yyF`.
Its main-image fixup is `0x10dc9b350`, stub `0x10c63ab0c`, forwarder
`0x107c28e34` and call `0x1015be650`. These two consumer/forwarder sites were
inspected without executing application code. The `_makeView` binding
remains diagnostic-only, and Fortnite remains unplayable.

The view-factory fixture, launch probe and both audits pass their expected
checks. Generated C and ARM64 disassembly review of both fixture variants
and both production runners confirms a terminal diagnostic, with no return,
graph/input/result/context dereference, ownership operations or runtime
storage. Seven executable/generated-C artifact pairs and joined validation
logs are archived in the same cohort.

The required SwiftUI import
`_$s7SwiftUI19UIViewRepresentablePAAyt11CoordinatorRtzrlE04makeE0yyF`
now resolves to the empty `makeCoordinator()` default constrained to
`Coordinator == Void`. Swift Void has no result bytes: the entry creates no
coordinator, leaves result storage unchanged and does not access borrowed
self, metadata or witnesses. Custom coordinator implementations and SwiftUI
graph execution remain unsupported.

The native AppKit counterpart is a single `ret`. It passes 4,000 calls with
protected arguments and 2,048 read-only/writable self/result boundary calls,
preserving every byte and x0-x3/x8/x20/x21. The SDK declares the Void
constraint and result, and the pinned OpenSwiftUI UIKit source supplies an
empty default. Native UIKit execution remains unverified because its entry
is unavailable on this Mac. Evidence is retained under
`build/ios/fortnite/swiftui-coordinator-checks`.

The dedicated fixture passes normal and deterministic ASan/UBSan host runs
with its default compiled at O2, plus the optimized ARM64 guest run. It
checks 16,384 concurrent calls across eight readers and two runtime
lifetimes, 600 ownership cycles with unchanged ObjC/Swift aliases,
read-only/writable borrowed self and result boundary storage, aliased
self/result pointers, protected metadata/witness/x8/contexts,
x0-x3/x8/x20/x21, exact framework routing, and calls during and after
teardown. The borrowed payload exercises ownership without assuming a
representable self layout. Bridged-inputs and view-factory host regressions
also pass normal and deterministic sanitizer runs. Public fixture routing
passes, including rejection of an unknown fixture.

The fresh launch probe links past the coordinator default and exits 1
before application entry at the required SwiftUI nominal type descriptor,
`_$s7SwiftUI32_EnvironmentKeyTransformModifierVMn`. Its main-image fixup is
`0x10dc9b358` in `__DATA_CONST,__got`; ten indirect context symbolic
references in `__TEXT,__swift5_typeref` point to this cell. These data
references were inspected without executing application code. SwiftUI graph
construction remains unsupported, and Fortnite remains unplayable.

The coordinator fixture, launch probe and both audits pass their expected
checks. Generated C and ARM64 disassembly review of both fixture variants
and both production runners confirms an empty hook and one `ret`, with no
argument/result/context access, ownership operations, allocation, runtime
storage or custom witness dispatch. Seven executable/generated-C artifact
pairs and joined validation logs are archived in the same cohort.

The required nominal descriptor
`_$s7SwiftUI32_EnvironmentKeyTransformModifierVMn` now resolves through
SwiftUI.framework to sealed type identity and its generic signature. Native
measurement establishes a unique generic struct in module SwiftUI, one
unconstrained type parameter, one key argument, no generic requirements and
two fields with their offset vector at metadata word three. The frozen SDK
declaration stores a writable environment key path and a transform closure.
Native Int, String and Never specializations each have size/stride 24, field
offsets 0/8, ownership flags `0x10007` and 2,147,483,647 extra inhabitants.

This binding supplies no complete specialization metadata, value witnesses,
field reflection, instantiation cache/pattern or ViewModifier conformance.
Key-path and closure ownership and environment execution remain unsupported.
The generic bit makes direct and indirect symbolic lookup reject before
reading the accessor or protected generic arguments. Calling the diagnostic
accessor reports
`iOS: SwiftUI environment transform generic instantiation is not implemented`.

One locked allocation publishes an RX diagnostic page and a read-only
descriptor page. Cached identity remains available during earlier teardown
callbacks; Swift owners and Array metadata drain before both pages unmap.
Retirement guards prevent late allocation and resolution after unmapping.

`tests/ios/native-checks.v build-swiftui-environment-transform` selects the
fixture. Normal and deterministic ASan/UBSan host runs pass the new fixture
with its entry compiled at O2, plus ModifiedContent and mangled-state lookup
regressions. The optimized ARM64 fixture checks eight cold readers, native
signature and page permissions, bounded direct/indirect symbolic references,
protected arguments, four diagnostic requests per lifetime, callback access
and two drained/unmapped lifetimes. The launch probe and both import audits
also pass their expected checks. Generated C and ARM64 review covers locked
publication, generic rejection and retirement in both fixture variants and
both production runners. Seven executable/generated-C pairs, native
measurements, SDK/Swift ABI snapshots and joined logs are retained under
`build/ios/fortnite/swiftui-environment-transform-checks`.

The fresh launch probe clears the nominal descriptor and exits 1 before
application entry at its ViewModifier conformance descriptor,
`_$s7SwiftUI32_EnvironmentKeyTransformModifierVyxGAA04ViewF0AAMc`.
Its GOT cell is `0x10dc9b360`. The load at `0x1015c17f8` passes this descriptor
as x0 to `_swift_getWitnessTable` at `0x1015c17fc`, with metadata in x1 and
witness arguments in x2. This consumer was inspected without executing app
code. Generic instantiation and SwiftUI graph execution remain unsupported,
and Fortnite remains unplayable.

The required conformance descriptor
`_$s7SwiftUI32_EnvironmentKeyTransformModifierVyxGAA04ViewF0AAMc` now resolves
in the existing environment-transform arena, pointing to the same nominal
descriptor. Native inspection establishes an unconditional conformance with
flags zero and a fixed seven-word witness table, despite the nominal type
being generic. There are no conditional requirements, generic instantiator
or instantiation cache. Both private protocol declarations retain the native
six-slot ViewModifier/View signatures and `Self.Body: View` requirement.

The fixed table supports ordinary `_swift_getWitnessTable` lookup without
reading the unused metadata or argument pointers. Its four graph entries
exit 1 with an explicit environment-transform diagnostic. Its tagged
associated-conformance record reports that `Never: View` is unsupported.
The associated-type slot contains the tagged mangled name `s5NeverO`; the
current decoder rejects it explicitly before publishing metadata or writing
the read-only table. Complete modifier specialization, Never resolution and
environment graph execution remain unsupported.

Native associated-type lookup on a valid Int specialization returns the
canonical Swift.Never metadata. No native environment values or graph
operations were executed. The binding introduces no dependent metadata
arenas or Swift/Objective-C owners; its table, protocols and diagnostics
share the existing sealed pages and their quiescent retirement.

`tests/ios/native-checks.v build-swiftui-environment-conformance` selects the
fixture. Normal and deterministic ASan/UBSan host runs pass the new fixture
with its entry compiled at O2, plus environment-transform nominal and opacity
regressions. The optimized ARM64 fixture checks eight cold readers and
concurrent static-table lookup, shared identity, exact protocol signatures,
protected unused metadata/arguments, twelve terminal graph/body/type child
probes, tagged data, page permissions, callback access and two drained/unmapped
lifetimes. The launch probe and both audits also pass their expected checks.
Generated C and ARM64 review covers both fixture variants and both production
runners. Seven executable/generated-C pairs, native measurements, SDK/Swift
ABI snapshots and joined logs are retained under
`build/ios/fortnite/swiftui-environment-conformance-checks`.

The fresh probe clears the conformance descriptor and exits 1 before
application entry at `_$s7SwiftUI4FontV5titleACvgZ` (`SwiftUI.Font.title`).
Its main-image fixup is `0x10dc9b368`, stub `0x10c63ab18`, forwarder
`0x107c28ebc` and call `0x1015bfdc4`; the caller stores the x0 result at
`0x1015bfddc`. These two consumer/forwarder sites were inspected without
executing application code. Fortnite remains unplayable.

The next cohort binds `_$s7SwiftUI4FontV5titleACvgZ` only to an explicit
`Font.title` provider-construction diagnostic. It terminates with exit 1 if
called, before returning a Font or touching caller arguments, metadata,
witnesses, context or result storage. Resolution accepts only the exact
symbol in the SwiftUI framework. It creates no provider or runtime owner.

The frozen SDK declares Font as an `AnyFontBox` provider reference. Typed
native host measurements show an eight-byte value, stride eight, returned in
x0 with one owned reference. Eight simultaneous calls share a cached
`SwiftUI.FontBox<SwiftUI.Font.TextStyleProvider>` whose native instance size is
33 bytes; each getter and retain increments its strong count once, and each
release balances that reference. This measures host ABI/ownership only.
Provider construction, its virtual methods and font rendering remain
unsupported; the diagnostic does not fabricate a FontBox.

`tests/ios/native-checks.v build-swiftui-font-title` selects the fixture.
Normal and deterministic ASan/UBSan runs pass it with its entry compiled at
O2, plus environment-conformance and view-factory regressions. The optimized
ARM64 fixture passes eight readers and 16,384 concurrent resolutions, 32
terminal child calls, protected unused arguments/metadata/witness/self/x8,
unchanged shared read-only/writable result pages at both guarded boundaries,
exact routing, callback access and two drained runtime lifetimes. Generated
C and ARM64 review covers both fixture variants and both production runners.
Seven executable/generated-C pairs, native measurements, SDK/Swift ABI
snapshots and joined logs are retained under
`build/ios/fortnite/swiftui-font-title-checks`.

The fresh probe resolves the title import and exits 1 before application
entry at `_$s7SwiftUI4TextV4boldACyF` (`SwiftUI.Text.bold()`). Its main-image
fixup is `0x10dc9b370`, stub `0x10c63ab24`, forwarder `0x107c28ec4` and call
`0x1015bfea0`. The caller supplies Text in x0-x3 and stores the result
fields at `0x1015bfeb8` through `0x1015bfec4`. These two consumer/forwarder
sites were inspected without executing application code. Font creation,
SwiftUI graph execution and application rendering remain unsupported;
Fortnite remains unplayable.

The next cohort binds `_$s7SwiftUI4TextV4boldACyF` only to an explicit
`Text.bold` modifier-construction diagnostic. It exits 1 if called, before
reading Text storage, modifiers, metadata, witnesses, contexts or result
storage. Resolution accepts only the exact symbol in the SwiftUI framework;
it allocates no Text, modifier array or boxed modifier.

The frozen SDK declares Text's storage and `[Text.Modifier]` fields. Typed
native host metadata and ARM64 calls measure Text size/stride 32 and
Text.Modifier size 9, stride 16. For short, heap-backed and Unicode verbatim
strings, `bold()` borrows unchanged storage and returns owned Text in x0-x3.
Its one-element array contains a boxed `SwiftUI.BoldTextModifier`, native
instance size 17. Calling it twice creates a separate two-element array and
leaves the input array intact. Native value-witness destruction balances the
result arrays and String references. These measurements do not implement
Text modifier ownership, boxed virtual methods or text rendering.

`tests/ios/native-checks.v build-swiftui-text-bold` selects the fixture.
Normal and deterministic ASan/UBSan runs pass it with its entry compiled at
O2, plus Font.title and LocalizedStringKey regressions. The optimized ARM64
fixture passes eight readers and 16,384 concurrent resolutions, 32 terminal
child calls, protected unused arguments/metadata/witness/self/x8, unchanged shared
read-only/writable result pages at both guarded boundaries, exact routing,
callback access and two drained runtime lifetimes. Generated C and ARM64
review covers both fixture variants and both production runners. The cohort
retains seven executable/generated-C pairs, native measurements, SDK/Swift ABI
snapshots and joined logs under `build/ios/fortnite/swiftui-text-bold-checks`.

The fresh probe resolves the bold import and exits 1 before application
entry at `_$s7SwiftUI4TextV4fontyAcA4FontVSgF` (`SwiftUI.Text.font(_:)`). Its
main-image fixup is `0x10dc9b378`, stub `0x10c63ab30`, forwarder `0x107c28ec0`
and call `0x1015bfe08`. The caller supplies the optional Font in x0 and Text
in x1-x4, stores the result fields at `0x1015bfe14` through `0x1015bfe20`,
then releases the Font provider at `0x1015bfe44`. These two consumer/forwarder
sites were inspected without executing application code. Text modifier
construction, SwiftUI graph execution and rendering remain unsupported;
Fortnite remains unplayable.

The next cohort binds `_$s7SwiftUI4TextV4fontyAcA4FontVSgF` only to an explicit
`Text.font` modifier-construction diagnostic. It exits 1 if called, before
reading the optional Font, Text storage/modifiers, contexts or result
storage. Only the exact symbol in the SwiftUI framework resolves. It creates
no Text, modifier array or provider owner.

Typed native host metadata and ARM64 calls confirm Text size/stride 32,
Text.Modifier size 9/stride 16 and Font size 8. For nil and `.title` arguments
across short, heap-backed and Unicode verbatim strings, `font(_:)` borrows
the Font in x0 and Text in x1-x4 and returns owned Text in x0-x3. Nil adds a
one-element font modifier with a nil payload; `.title` adds the same modifier
with its provider pointer and retains that provider. Applying it twice
creates a separate two-element array without changing the input array.
Native value-witness destruction balances String, array and provider
ownership. These measurements do not implement modifier arrays, Font
provider ownership or text rendering in the runner.

`tests/ios/native-checks.v build-swiftui-text-font` selects the fixture.
Normal and deterministic ASan/UBSan runs pass it with its entry compiled at
O2, plus Text.bold and Font.title regressions. The optimized ARM64 fixture
passes eight readers and 16,384 concurrent resolutions, 32 terminal child
calls, nil/protected/invalid Font values, protected Text/self/x8, unchanged
shared read-only/writable result pages at both guarded boundaries, exact
routing, callback access and two drained runtime lifetimes. Generated C and
ARM64 review covers both fixture variants and both production runners. Seven
executable/generated-C pairs, native measurements, SDK/Swift ABI snapshots
and joined logs are retained under `build/ios/fortnite/swiftui-text-font-checks`.

The fresh probe resolves the font import and exits 1 before application
entry at `_$s7SwiftUI4TextVAA4ViewAAWP` (Text's View protocol witness table).
Its main-image fixup is `0x10dc9b380` with no call stub. The consumers at
`0x1015bff3c` and `0x1015c023c` load the table into x2 at `0x1015bff40` and
`0x1015c0240`, then save it for later generic calls alongside Text metadata.
These two data consumers were inspected without executing application code.
Text modifier construction, provider ownership, SwiftUI graph execution and
rendering remain unsupported; Fortnite remains unplayable.

The Text View witness-table slice binds `_$s7SwiftUI4TextVAA4ViewAAWP` as
sealed data. Its seven-word table links an unconditional conformance with
native flags 8 through an indirect Text descriptor. The View signature has
one Body requirement and six witness slots. Tagged associated-conformance
data and an indirect symbolic reference identify Body as `Swift.Never`.
Typed native runtime measurement confirms that Body resolves to canonical
Never without constructing Text values or executing graph operations.

Private Text and Never declarations carry diagnostic metadata accessors;
Text metadata and value witnesses remain unsupported. Graph witnesses and
the Body conformance accessor also stop with explicit diagnostics. The
arena publishes only after sealing separate RX/RO pages, stays available to
shutdown callbacks and unmaps after Swift owners and collections drain.

`tests/ios/native-checks.v build-swiftui-text-view` selects the fixture.
Normal and deterministic ASan/UBSan runs cover it at O2 plus Text.font and
environment-conformance regressions. The optimized ARM64 fixture checks
eight cold readers, native signatures and tagged data, protected unused
arguments, 16 terminal graph/body/metadata child probes, exact routing,
callback access and two drained/unmapped runtime lifetimes. Native
measurements, SDK/Swift ABI snapshots, seven executable/generated-C pairs
and joined logs are retained in `build/ios/fortnite/swiftui-text-view-checks`.

The fresh launch resolves the witness-table import and exits 1 during
linking at `_$s7SwiftUI4TextVMn`, Text's nominal descriptor. Its GOT fixup is
`0x10dc9b388`; ten indirect symbolic references in `__swift5_typeref` were
verified without executing application code. Text metadata, value ownership,
SwiftUI graph execution and rendering remain unsupported; Fortnite remains
unplayable.

The Text nominal slice binds `_$s7SwiftUI4TextVMn` to the same sealed
descriptor referenced by its View conformance. Native inspection confirms a
nongeneric SwiftUI.Text struct, two fields and an offset vector at word two.
Six native metadata requests return the same complete Text metadata; its
32-byte size/stride and non-POD value witnesses require real ownership for
the reflected `storage` and `modifiers` fields. The runner supplies descriptor
identity with a diagnostic accessor; Text metadata, value ownership, field
reflection and rendering remain unsupported.

`tests/ios/native-checks.v build-swiftui-text-nominal` selects the fixture.
Normal and deterministic ASan/UBSan runs cover it at O2 plus Text View and
Text.font regressions. The optimized ARM64 fixture checks eight cold
readers, shared descriptor/table identity, sealed RX/RO storage, 32 terminal
direct/indirect symbolic-reference and metadata-access probes, bounded names
at a protected boundary, protected contexts/arguments, exact routing,
shutdown callbacks and two drained/unmapped lifetimes. Native measurements,
SDK/Swift ABI snapshots, seven executable/generated-C pairs and joined logs
are retained in `build/ios/fortnite/swiftui-text-nominal-checks`.

The fresh probe resolves the descriptor import and exits 1 during linking at
`_$s7SwiftUI4TextVN`, Text's type metadata. Its GOT fixup is `0x10dc9b390`
with no call stub. The consumers at `0x1015bff30` and `0x1015c0230` load it
into x1 and save it alongside the View witness table for generic calls.
These two data consumers were inspected without executing application code.
Text ownership and SwiftUI graph execution remain unsupported; Fortnite
remains unplayable.

The Text metadata slice binds `_$s7SwiftUI4TextVN` to complete struct metadata
sharing the existing Text nominal descriptor and View table. Its measured
layout is size/stride 32, field offsets 0/24, flags `0x02030007` and
`INT32_MAX` extra inhabitants. The nominal accessor returns the same complete
metadata through direct and bounded symbolic lookups.

All eight value witnesses now handle Text's frozen String/object storage
and modifier-array owner. Copying retains both owners; takes transfer them.
Copies and assignments preserve the seven padding bytes after the storage
tag, while initializing take copies all 32 bytes. Native deallocation probes
confirm that assignments publish new storage before releasing its previous
owner, then update the array. Registered non-inline boxes support shared
buffer copies and Any, validate their provenance and destroy Text before
deallocating the box. Field reflection, Text construction, graph execution
and rendering remain unsupported.

`tests/ios/native-checks.v build-swiftui-text-metadata` selects the fixture.
Normal and deterministic ASan/UBSan runs cover its O2 entry plus nominal and
View regressions. Native and runner fixtures compare all String/object
assignment combinations, callback-visible state and reference counts,
read-only source spans, padding, guarded enum boundaries, shared boxes and
Any. A heap String shared by Text storage and a typed array verifies final
element destruction. Eight cold readers and two drained lifetimes exercise
publication and retirement. Native measurements, SDK/Swift ABI snapshots,
seven executable/generated-C pairs and joined logs are retained under
`build/ios/fortnite/swiftui-text-metadata-checks`.

The fresh launch resolves Text metadata and exits 1 during linking at its
localized-string initializer
`_$s7SwiftUI4TextV_9tableName6bundle7commentAcA18LocalizedStringKeyV_SSSgSo8NSBundleCSgs06StaticI0VSgtcfC`.
Its fixup is `0x10dc9b398`, stub `0x10c63ab3c` and forwarder `0x107c28eb8`.
The calls at `0x1015bfd8c` and `0x1015c01e4` pass a literal LocalizedStringKey,
nil table/bundle/comment arguments and receive Text in x0-x3. These sites
were inspected without executing application code. Fortnite remains
unplayable, with Text construction and SwiftUI graph/rendering still absent.

The localized Text initializer now has an exact SwiftUI diagnostic binding.
Native ARM64 measurements cover 24 literal-key/table/comment combinations
with a nil bundle. The result is an owned Text in x0-x3 with object storage
and an empty modifier array. Its 72-byte LocalizedTextStorage provider consumes
the key and optional table owners. Text copies retain the shared provider;
final destruction releases its fields. The comment does not become a stored
field. These observations do not provide provider construction or localization.

`tests/ios/native-checks.v build-swiftui-text-localized` selects the new fixture.
Normal and deterministic ASan/UBSan runs cover its O2 entry, Text metadata and
literal-key regressions. Thirty-two terminal child probes verify the diagnostic
with protected key/table/bundle/comment pointers, stack arguments, Self and x8,
including unchanged shared result pages at both protected boundaries. Eight
readers, exact framework routing and callbacks exercise two drained lifetimes.
Native declarations and measurements, seven executable/generated-C pairs and
joined logs are retained under `build/ios/fortnite/swiftui-text-localized-checks`.
Localized provider construction, localization and rendering remain unsupported.

The fresh launch resolves this diagnostic binding and exits 1 during linking
at SwiftUI's default View graph factory,
`_$s7SwiftUI4ViewPAAE05_makeC04view6inputsAA01_C7OutputsVAA11_GraphValueVyxG_AA01_C6InputsVtFZ`.
Its fixup is `0x10dc9b3a0`, stub `0x10c63ab48` and forwarder `0x107c28ee4`.
The call at `0x1015c0aa8` forwards the caller's arguments through a small wrapper.
These sites were inspected without executing application code. Fortnite still
stops before application entry and remains unplayable.

The default `View._makeView`, `View._makeViewList` and `View._viewListCount`
imports now have distinct terminal diagnostics. They require Body's View
conformance and graph traversal, which remain unsupported. Native metadata
inspection measures `_GraphValue<Int>` at 4 bytes, `_ViewInputs` at 84,
`_ViewListInputs` at 129 and `_ViewListCountInputs` at 80. The native entries
read graph values and inputs indirectly. `_ViewOutputs` and `_ViewListOutputs`
are resilient owned values of 16 and 65 bytes; the count result is `Int?`,
size 9 and stride 16. Binding these diagnostics does not construct graph
outputs or supply a count.

Fresh IPA inspection finds these required default View imports and calls:

| Hook | GOT fixup | Stub | Forwarder | Calls |
| --- | --- | --- | --- | --- |
| `_makeView` | `0x10dc9b3a0` | `0x10c63ab48` | `0x107c28ee4` | `0x1015c0aa8` |
| `_makeViewList` | `0x10dc9b3a8` | `0x10c63ab54` | `0x107c28ee8` | `0x1015c0abc` |
| `_viewListCount` | `0x10dc9b3b0` | `0x10c63ab60` | `0x107c28e58` | `0x1015be82c`, `0x1015c0ad0` |

The count hook also serves a UIViewRepresentable wrapper. Both callers mask
the optional-result tag. No graph factory or application code was executed.

`tests/ios/native-checks.v build-swiftui-view-defaults` selects the fixture.
Normal and deterministic ASan/UBSan runs cover its O2 entry and the existing
representable factory/list diagnostics. The fixture checks seven native ABI
layouts and 96 terminal child calls with protected graph, inputs, metadata,
witness, stack, Self and x8 values, unchanged shared result pages at both
protected boundaries, exact routing, eight readers and two drained lifetimes.
Seven executable/generated-C pairs, SDK/ABI snapshots, native measurements,
call-site traces and joined logs are retained under
`build/ios/fortnite/swiftui-view-defaults-checks`. Graph construction, count
traversal and rendering remain unsupported.

The fresh launch resolves all three diagnostic bindings and exits 1 during
linking at `_$s7SwiftUI4ViewPAAE7opacityyQrSdF`, View's opacity modifier.
Its fixup is `0x10dc9b3b8`, stub `0x10c63ab6c` and forwarder `0x107c28eac`.
The call at `0x1015bfa7c` passes opacity 0 or 1 in d0, Self in x20 and an
indirect result in x8. These sites were inspected without executing application
code. Fortnite still stops before application entry and remains unplayable.

`View.opacity` now constructs its returned value. It borrows Self in x20,
copies it once through `initializeWithCopy` using the caller's type metadata,
and writes the opacity Double into the frozen
`ModifiedContent<Self, _OpacityEffect>` result in x8. The modifier begins at
Self's size rounded up to eight bytes; using Self's stride would misplace it
for types with trailing padding. The adapter preserves x20/x21 and the
opacity's exact bits, including signed zero, infinity and NaN payloads.
It neither clamps the value nor changes ownership of the source.

Native SwiftUI comparison covers five generic POD layouts (Void, UInt8, Int,
Optional<Int> and SIMD4<Float>), EmptyView and a Color with an owned opacity
provider. Both implementations copy that provider once and balance the result's
destruction. Generic POD metadata exercises the value ABI with a protected,
unused View table; it does not fabricate conformances for non-View types.
The Vinix fixture also checks fifteen sizes with distinct strides, exact
read-only sources, writable results and untouched alignment padding at both
guard boundaries, ten IEEE bit patterns,
overflow rejection before touching Self or result, an instrumented copy witness,
native ARC, eight concurrent readers, and two drained/unmapped lifetimes.

`tests/ios/native-checks.v build-swiftui-view-opacity` selects the fixture.
Its sanitizer runs, neighboring opacity/ModifiedContent regressions, isolated
ARM64 fixture and import audits, native SDK/ABI snapshots, generated C and
call-site evidence are retained under
`build/ios/fortnite/swiftui-view-opacity-checks`. The adapter shares the existing
opacity arena's sealing and retirement. This implements value construction;
generic ModifiedContent metadata and View conformance instantiation, graph
construction and rendering remain unsupported.

The new launch resolves `View.opacity` and exits 1 during linking at
`_$s7SwiftUI4ViewPAAE8disabledyQrSbF`. Fresh IPA inspection locates its fixup
at `0x10dc9b3c0`, stub at `0x10c63ab78`, forwarder at `0x107c28ecc` and call
at `0x1015c0030`. The caller passes the disabled Bool in w0, type metadata in
x1, a View table in x2, borrowed Self in x20 and the result in x8. These sites
were inspected without executing application code. Fortnite still stops
before application entry and remains unplayable.

`View.disabled` now has a terminal diagnostic for its missing environment
transform construction. Native SwiftUI returns
`ModifiedContent<Self, _EnvironmentKeyTransformModifier<Bool>>`, storing an
owned writable key path to `EnvironmentValues.isEnabled` and a closure that
captures the disabled Bool. Applying that closure computes
`inheritedEnabled && !disabled`: passing false preserves a disabled ancestor.
Native measurements put EnvironmentValues at 16 bytes and the transform at 24
bytes, with the key path at offset zero and the closure at offset eight.
For EmptyView, the complete returned value is also 24 bytes. Native copy/destroy
checks confirm ownership of the captured context and a canonical key path
across both Bool values.

Key-path construction and environment execution remain unsupported. The new
binding reports that limitation before reading Self, metadata or witnesses,
changing ownership, or writing an indirect result. The public fixture
`tests/ios/native-checks.v build-swiftui-view-disabled` checks the native
layouts and four inherited-enabled cases, plus 128 diagnostic child calls
with guarded inputs, unchanged shared writable/read-only result pages,
four Bool register patterns, eight readers, exact routing, teardown callbacks
and two drained lifetimes. Sanitizer runs also cover the existing opacity value
constructor and environment-transform descriptor. Native measurements,
SDK/ABI snapshots, isolated ARM64 results, generated C and call-site evidence
are retained under `build/ios/fortnite/swiftui-view-disabled-checks`.
Binding this diagnostic does not implement disabled controls or rendering.

The new launch resolves this binding and exits 1 during linking at
`_$s7SwiftUI5StateV12wrappedValuexvg`. Fresh IPA inspection locates its fixup
at `0x10dc9b3c8`, stub at `0x10c63ab84` and forwarder at `0x107c28e60`.
The three calls at `0x1015be924`, `0x1015bfa08` and `0x1015c0000` pass an
indirect result in x8 and read its Bool byte afterward. These sites were
inspected without executing application code. Fortnite still stops before
application entry and remains unplayable.

`State.wrappedValue` now reads a cached value when `_location` is nil. Its
ARM64 argument is complete State<Value> metadata in x0, borrowed Self in x20
and an indirect Value result in x8. The getter reads the signed location field
offset from State metadata, then copies `_value` through Value's
`initializeWithCopy` witness. That preserves the source and gives the result
its own reference ownership. It copies Value's size rather than State's size
or Value's stride.

Native comparisons cover State<Void>, Bool, UInt8, Int, Optional<Int>, String
and SIMD4<Float>. Their location offsets are 0, 8 or 16; State<SIMD4<Float>>
has size 24 and stride 32. An owned native String confirms that both native and
Vinix reads retain one result reference and balance destruction while the
source remains intact. The fixture also covers fifteen instrumented size/stride
cases, guard pages and untouched padding, zero-sized results, a reentrant copy
witness, eight cold readers, RX publication and two drained/unmapped lifetimes.

A non-nil location needs AnyLocation virtual calls and graph/update tracking.
It now diagnoses before accessing the location object, Value's metadata or
bytes, or result storage; negative field offsets also diagnose. Thirty-four
child calls check these paths using protected values and shared writable/read-only
results. The adapter remains available to teardown callbacks after concurrent
work is retired, and is unmapped with the runtime's metadata after owners drain.

`tests/ios/native-checks.v build-swiftui-state-value` selects the fixture.
Sanitizer regressions also cover opacity construction and disabled diagnostics.
Native SDK/ABI measurements, generated C, isolated ARM64 runs, import audits and
call-site evidence are retained under
`build/ios/fortnite/swiftui-state-value-checks`. State construction, generic
metadata instantiation, bindings, live locations, graph execution and
rendering remain unsupported.

The matching setter, `_$s7SwiftUI5StateV12wrappedValuexvs`, now handles a nil
location with native nonmutating semantics: cached `_value` remains unchanged,
while the incoming Value is consumed through its own `destroy` witness. It
receives the new Value indirectly in x0, complete State metadata in x1 and
borrowed Self in x20; there is no result in x8. Its fixup is
`0x10dc9b3d0`, stub `0x10c63ab90` and forwarder `0x107c28e68`. The calls at
`0x1015bea28` and `0x1015bee20` pass the new Bool indirectly in x0, State
metadata in x1 and borrowed State in x20. These sites were inspected without
executing application code.

Native comparisons cover the same seven State specializations. Both native and
Vinix leave read-only cached State intact and release exactly one incoming
owned String reference without changing its bytes. Fifteen instrumented
size/stride cases check the exact destroy argument and Value metadata, including
a zero-sized Value with inaccessible storage. A reentrant destructor resolves
the adapter on another thread without holding the initialization lock. Thirty-four
child calls verify that non-nil locations and negative field offsets diagnose
before accessing cached Value bytes, new Value metadata/owners or location
objects. Live writes require AnyLocation virtual set and transaction behavior;
they remain unsupported.

`tests/ios/native-checks.v build-swiftui-state-set` selects the setter fixture.
Its adapter is sealed RX before publication, remains available to drained
teardown callbacks and is unmapped after owners retire. Native disassembly,
six sanitizer runs including getter/opacity regressions, isolated ARM64 checks,
generated C and call-site evidence are retained under
`build/ios/fortnite/swiftui-state-set-checks`.

`State.projectedValue` now has an explicit diagnostic binding for unsupported
Binding construction. Native SwiftUI returns an owned Binding even when State's
location is nil: an empty Transaction, a constant AnyLocation object and a
cached Value. The three fields are at offsets 0, 8 and 16. Native comparisons
cover Binding<Void>, Bool, UInt8, Int, Optional<Int>, String and SIMD4<Float>.
Binding<Bool> has size 17 and stride 24. An owned String gains two references,
one for the cached Value and one captured by the constant location; copying and
destroying Binding balance both owners. A native Bool Binding continues to read
its original value after the source State changes, confirming constant snapshot
behavior. No attached locations, graph or application code are executed by
these comparisons.

The getter receives complete State metadata in x0, borrowed Self in x20 and an
indirect Binding result in x8. Its fixup is `0x10dc9b3d8`, stub `0x10c63ab9c`, forwarder
`0x107c28e6c` and direct call `0x1015beac0`; inspection executes no application
code. That call reads two words and a Bool from the returned Binding. Vinix's
diagnostic stops before reading metadata, Self or Value owners, allocating a
location, or writing any result bytes. Binding metadata, constant/live location
construction, transactions, graph execution and rendering remain unsupported.

`tests/ios/native-checks.v build-swiftui-state-projected` selects the fixture.
It checks 128 child calls, protected metadata/Self/stack/x8 pointers and unchanged
shared writable/read-only result pages at both guard boundaries, eight readers,
exact framework routing and two drained runtime lifetimes. Native ownership
measurements, sanitizer regressions for both wrapped-value accessors, isolated
ARM64 checks and call-site evidence are retained under
`build/ios/fortnite/swiftui-state-projected-checks`.

`_$s7SwiftUI5StateVMn` now supplies State's nominal identity and unconstrained
generic signature. Native measurements confirm unique generic-struct flags
`0xd1`, one type parameter, zero requirements and one key argument. There are
two fields with the field-offset vector at metadata word three. Native complete
State<Bool> and State<Int> have size/stride 16 and offsets 0/8; State<String>
has size/stride 24 and offsets 0/16. These specialization measurements describe
native SwiftUI; Vinix does not construct complete State metadata.

The descriptor's module is SwiftUI and its type name is State. Its required GOT cell
is `0x10dc9b3e0`; the indirect context symbolic reference at `0x10dc7fc3c`
points to it from `__swift5_typeref`. A sealed read-only data page holds the
descriptor/module/names; a separate RX page holds its diagnostic accessor.
Reflection, instantiation cache and default pattern pointers remain null. The
generic bit remains set, so direct and indirect symbolic lookup reject before
calling a nongeneric accessor ABI or reading protected generic arguments.
Calling the accessor directly diagnoses unsupported State instantiation.

`tests/ios/native-checks.v build-swiftui-state-nominal` selects the fixture.
It compares the native descriptor signature, exercises guarded symbolic names
and arguments, eight cold readers, retirement guards, callback access after
concurrency retirement and two drained/unmapped lifetimes. Native measurements,
sanitizer regressions for environment-transform descriptors and projected-value
diagnostics, generated C, isolated ARM64 runs and import evidence are retained
under `build/ios/fortnite/swiftui-state-nominal-checks`. State specialization,
construction, locations, DynamicProperty conformance and rendering remain
unsupported.

`Button(action:label:)` now has an explicit diagnostic binding. The native
initializer takes the escaping action function/context in x0/x1, the borrowed
label function/context in x2/x3, Label metadata and its View witness in x4/x5,
and an indirect result in x8. It evaluates the label once and transfers the
action context into owned Button storage; construction does not invoke the
action.

Button is not frozen. Native measurements show private action storage larger
than a closure pair: Button<EmptyView> has size 106, stride 112 and field
offsets 0/8/106; Button<Text> has size/stride 144 and offsets 0/8/112. The native
fixture obtains result size and label placement from metadata. An owned action
context verifies transferred ownership, one retained reference per Button copy,
balanced destruction, and a stored action that remains callable after the
original Button is destroyed. The label builder runs once with a protected
borrowed context and an empty result, using the measured arm64e closure signing
discriminator `0x720f`. No Button graph, UI event loop or application code is
executed by these comparisons.

The required import is
`_$s7SwiftUI6ButtonV6action5labelACyxGyyc_xyXEtcfC`. Its fixup is
`0x10dc9b3e8`, stub `0x10c63aba8`, forwarder
`0x107c28ec8` and direct call `0x1015bffc8`. These references were inspected
without executing application code. Vinix diagnoses before invoking either
closure, touching metadata or owners, or writing result storage. Button
metadata, construction, action storage, graph execution and rendering remain
unsupported.

`tests/ios/native-checks.v build-swiftui-button` selects the fixture. It checks
136 child calls with protected closures, contexts, Label metadata, View witness,
stack and result pointers; shared writable/read-only result pages remain
unchanged at both guard boundaries, and valid callbacks are never invoked.
Eight readers, exact framework routing, teardown callbacks and two drained
runtime lifetimes are covered. Native measurements, sanitizer regressions for
State descriptors/projected-value diagnostics, generated C and isolated ARM64
runs are retained under `build/ios/fortnite/swiftui-button-checks`.

Button's nominal descriptor, `_$s7SwiftUI6ButtonVMn`, now supplies sealed
`SwiftUI.Button` identity with the native generic signature: one Label type
parameter, a `Label: View` requirement and two key arguments (Label metadata and
its View witness). It records three fields with the offset vector at metadata
word four. The requirement includes the native View declaration and its
`Body: View` signature. It supplies no Button metadata, witness table, reflection
record, instantiation cache or metadata pattern. The accessor explicitly
diagnoses unsupported specialization; the generic bit makes direct/indirect
symbolic lookup reject before attempting the nongeneric accessor ABI.

The descriptor's required GOT fixup is
`0x10dc9b3f0`, referenced indirectly by ten context symbolic references in
`__swift5_typeref`, from `0x10dc7fc84` through `0x10dc7feac`. These references
were inspected without executing application code.

`tests/ios/native-checks.v build-swiftui-button-nominal` checks native signature
agreement, eight concurrent cold readers, data/code protections, protected
symbolic inputs and 128 child accessor calls with protected Label metadata and
View witnesses. Teardown retains the descriptor through drained callbacks,
then unmaps both pages; fresh publication is rejected after retirement. Two
runtime lifetimes and regressions for State descriptors and Button initializer
diagnostics are recorded under
`build/ios/fortnite/swiftui-button-nominal-checks`. Button specialization,
construction, action storage, View witness specialization and rendering remain
unsupported.

Button's View conformance descriptor, `_$s7SwiftUI6ButtonVyxGAA4ViewAAMc`, now
shares the existing sealed Button arena, its nominal descriptor and its View
protocol declaration. Native measurements show an unconditional conformance
with a generic witness table: `Label: View` is already required by the nominal
type, so there are no conditional or private witness arguments. Its control
word is `0x10007` (seven copied words, RequiresInstantiation, zero private words),
with no native instantiator. Native lookup returns stable, distinct cached
tables for Button<EmptyView> and Button<Text>; both copy all seven pattern words.
No witness methods, Button construction, graph or application code are invoked
by these native comparisons.

Vinix preserves the generic conformance flag `0x20000` and RequiresInstantiation,
with zero copied words, a null pattern/cache and an explicit diagnostic
instantiator. Witness lookup rejects the generic declaration before touching
metadata, arguments or the pattern. The instantiator diagnoses before reading
caller inputs or writing a table. This supplies the conformance declaration;
Button witness specialization, construction, graph execution and rendering
remain unsupported.

The required GOT fixup is `0x10dc9b3f8`; the consumer at `0x1015c16f0` loads it
before calling `swift_getWitnessTable` at `0x1015c16f8`. These references were
inspected without executing application code.

`tests/ios/native-checks.v build-swiftui-button-view` checks eight concurrent
cold readers resolving nominal/conformance descriptors in both orders, shared
canonical identity, RX/RO protections and 192 child calls with protected
metadata, arguments and table pointers. Shared writable/read-only table pages
remain unchanged at both guard boundaries. Teardown callbacks retain descriptor
access until users drain; both pages unmap across two runtime lifetimes.
Measurements, native Button descriptor/ModifiedContent conformance regressions,
generated C and isolated ARM64 results are retained under
`build/ios/fortnite/swiftui-button-view-checks`.

`VStack(alignment:spacing:content:)` now has an explicit diagnostic binding.
The SDK declares frozen VStack storage as
`_VariadicView.Tree<_VStackLayout, Content>`, with a borrowed content builder.
Native ARM64 construction takes alignment in x0, optional spacing payload/tag
in x1/x2, builder function/context in x3/x4, Content metadata and its View
witness in x5/x6, and the indirect result in x8. Native measurements show size
17/stride 24 for VStack<EmptyView> and size/stride 56 for VStack<Text>, with
Content offsets 17 and 24 respectively.

Six native construction cases verify the 17-byte layout root, spacing payloads
and optional tags, one builder evaluation with a protected borrowed context,
and owned Text content copied and destroyed through native value witnesses.
The builder receives temporary Content storage before the value is moved into
VStack. Copies and destruction balance the String owner, and x20/x21 remain
preserved. No graph, rendering or application code executes in these comparisons.

Vinix diagnoses before invoking the builder, reading Content metadata or its
View witness, changing ownership, or writing result storage. Frozen generic
storage still needs dependent Tree/VStack metadata and ownership support;
VStack construction, Tree specialization, graph execution and rendering remain
unsupported.

The import is
`_$s7SwiftUI6VStackV9alignment7spacing7contentACyxGAA19HorizontalAlignmentV_12CoreGraphics7CGFloatVSgxyXEtcfC`.
Its required fixup is
`0x10dc9b400`, stub `0x10c63abb4`, forwarder `0x107c28ea8` and direct call
`0x1015bf9c0`. These references were inspected without executing application
code.

`tests/ios/native-checks.v build-swiftui-vstack-init` checks 136 child calls with
protected builder/context, Content metadata, View witness, stack, Self and x8,
arbitrary alignment/spacing bits and valid builders that must never run.
Shared writable/read-only result pages remain unchanged at both guard
boundaries. Eight readers, exact routing, teardown callbacks and two drained
runtime lifetimes are covered. Native preflight measurements, sanitizer
regressions for _VStackLayout and Button construction diagnostics, generated C
and isolated ARM64 results are retained under
`build/ios/fortnite/swiftui-vstack-init-checks`.

VStack's nominal type descriptor, `_$s7SwiftUI6VStackVMn`, now supplies its
generic struct declaration in module SwiftUI, one stored field, a field-offset
vector at metadata word four, the `Content: View` requirement and two key
arguments: Content metadata and its View witness. Its View declaration includes
the `Body: View` signature and six requirement flags, with no default
implementations. Native descriptor checks and EmptyView/Text specializations
confirm the declaration and dependent sizes of 17/stride 24 and 56/stride 56.

The descriptor occupies read-only storage; its accessor thunk occupies a
separate executable page. No reflection records, instantiation cache, generic
metadata pattern or complete generic metadata are supplied. The generic bit
keeps direct/indirect symbolic lookup from calling the nongeneric accessor ABI.
Explicit specialization attempts diagnose before reading Content metadata or
its View witness. Dependent Tree ownership, VStack specialization, construction
and rendering remain unsupported.

`tests/ios/native-checks.v build-swiftui-vstack-nominal` checks eight cold
readers, exact routing, the native generic signature, 128 protected accessor
calls, symbolic rejection, retirement guards, teardown callback access and two
drained/unmapped runtime lifetimes. Native measurements, Button descriptor and
VStack initializer sanitizer regressions, generated C and isolated ARM64
results are retained under `build/ios/fortnite/swiftui-vstack-nominal-checks`.
The required import cell is `0x10dc9b408` in `__DATA_CONST,__got`, referenced by
five indirect context symbolic references in `__TEXT,__swift5_typeref`.
These data references were inspected without executing application code.

VStack's View conformance declaration, `_$s7SwiftUI6VStackVyxGAA4ViewAAMc`,
now shares the nominal descriptor's sealed arena. Native measurement shows
zero conformance flags and one static seven-word witness table: both EmptyView
and Text specializations return the exact pattern pointer. Content's View
constraint belongs to the nominal signature; there are no conditional
requirements, generic witness controls or instantiation caches.

The table preserves tagged Body/Never type and conformance-accessor records.
Lookup returns the canonical table without reading unused metadata or argument
pointers. Body/Never metadata and conformance access and all four graph witness
slots diagnose before reading caller storage or writing results. No complete
VStack/Never metadata, graph engine or rendering support is supplied.

`tests/ios/native-checks.v build-swiftui-vstack-view` checks both resolution
orders with eight cold readers, native static table and symbolic Never
declarations, protected unused metadata/arguments, 256 terminal child calls,
protected graph stack arguments, Self and x8, and unchanged shared writable/read-only
result pages at both guard boundaries. Teardown callbacks and two drained/unmapped
lifetimes use the existing arena. Native measurements, VStack nominal and
Button View sanitizer regressions, generated C and isolated ARM64 results are
retained under `build/ios/fortnite/swiftui-vstack-view-checks`.
The required fixup is `0x10dc9b410`; a consumer at `0x1015c1190` loads it before
calling `swift_getWitnessTable` at `0x1015c1198`. These references were inspected
without executing application code.

`ZStack(alignment:content:)` now has an explicit diagnostic binding. Frozen
ZStack stores `_VariadicView.Tree<_ZStackLayout, Content>`. Native ARM64
construction takes the two Alignment words in x0/x1, builder function/context
in x2/x3, Content metadata and its View witness in x4/x5, and the indirect
result in x8. EmptyView and Text specializations have size/stride 16 and 48
respectively, with Content at offset 16 in both.

Six native construction cases cover `.center`, `.topLeading` and `.bottomTrailing`
alignments with both content types. Each calls the builder once with a
protected borrowed context and temporary Content storage. Copies and
destruction balance owned Text/String references, preserve x20/x21 and leave
result canaries intact. No graph, rendering or application code executes.

Vinix stops before calling the builder, reading Content metadata or its View
witness, changing ownership or writing results. Generic Tree/ZStack metadata,
Content ownership, construction and rendering remain unsupported.
`tests/ios/native-checks.v build-swiftui-zstack-init` checks 136 terminal child
calls, protected builder/context/metadata/witness/stack arguments/Self/x8,
arbitrary alignment words, valid builders that must never run, unchanged
shared writable/read-only result pages at both guard boundaries, eight
readers, callbacks and two drained runtime lifetimes. Native measurements,
_ZStackLayout and VStack initializer sanitizer regressions, generated C and
isolated ARM64 results are retained under
`build/ios/fortnite/swiftui-zstack-init-checks`.

The import is
`_$s7SwiftUI6ZStackV9alignment7contentACyxGAA9AlignmentV_xyXEtcfC`.
Its required fixup is `0x10dc9b418`,
stub `0x10c63abc0`, forwarder `0x107c28ea4` and direct call `0x1015bf6f8`.
These references were inspected without executing application code.

ZStack's nominal descriptor, `_$s7SwiftUI6ZStackVMn`, now resolves through
SwiftUI.framework in sealed storage. Native ARM64 measurement confirms one
generic Content parameter, its `Content: View` requirement, two key arguments
(metadata and witness), and one field with its offset vector at metadata word
four. The View declaration includes its six requirements and `Body: View`
signature. Native EmptyView and Text specializations have size/stride 16 and
48 respectively; their field offset is zero.

The generic descriptor retains its generic bit. Symbolic lookup rejects it
before attempting the nongeneric accessor ABI, and its three-argument generic
accessor diagnoses without reading Content metadata or its witness. No
complete ZStack metadata, instantiation cache, generic metadata pattern or
reflection is supplied.
ZStack specialization, construction, dependent Tree ownership, complete
Body/Never metadata and rendering remain unsupported.

`tests/ios/native-checks.v build-swiftui-zstack-nominal` checks eight cold
readers, the native declaration, read-only descriptor and executable accessor
protections, direct/indirect symbolic rejection at a guard boundary, 128
terminal child calls with protected metadata and witnesses, retirement
guards, teardown callbacks and two drained/unmapped lifetimes. Native
measurements, VStack nominal and ZStack initializer sanitizer regressions,
generated C and isolated ARM64 results are retained under
`build/ios/fortnite/swiftui-zstack-nominal-checks`. Its required
import cell is `0x10dc9b420` in `__DATA_CONST,__got`, referenced by an indirect
context symbolic reference at `0x10dc7fc5a` in `__TEXT,__swift5_typeref`.
These data references were inspected without executing application code.

ZStack's View conformance declaration, `_$s7SwiftUI6ZStackVyxGAA4ViewAAMc`,
now shares the nominal descriptor's sealed arena. Native measurement shows
zero conformance flags and a static seven-word witness table: EmptyView and
Text specializations return the same pattern pointer. Content's View
constraint belongs to the nominal signature; no conditional requirements,
generic witness controls or instantiation caches are supplied.

The table preserves tagged Body/Never type and conformance-accessor records.
Lookup returns the canonical table without reading unused metadata or argument
pointers. Body/Never metadata and conformance access and all four graph witness
slots diagnose before reading caller storage or writing results. Complete
ZStack/Never metadata, graph execution and rendering remain unsupported.

`tests/ios/native-checks.v build-swiftui-zstack-view` checks both resolution
orders with eight cold readers, native static table and symbolic Never
declarations, protected unused metadata/arguments, 256 terminal child calls,
protected graph stack arguments, Self and x8, and unchanged shared writable/read-only
result pages at both guard boundaries. Teardown callbacks and two drained/unmapped
lifetimes use the existing arena. Native measurements, ZStack nominal and
VStack View sanitizer regressions, generated C and isolated ARM64 results are
retained under `build/ios/fortnite/swiftui-zstack-view-checks`.
Its required import cell is `0x10dc9b428`; a consumer at `0x1015c06b8` loads
it before calling `swift_getWitnessTable` at `0x1015c06c0`. These references
were inspected without executing application code.

TupleView's nominal descriptor, `_$s7SwiftUI9TupleViewVMn`, now resolves
through SwiftUI.framework in sealed storage. Native ARM64 measurement confirms
one unconstrained T parameter, zero generic requirements, one metadata key
argument and one field with its offset vector at metadata word three. Frozen
TupleView stores its T value directly. Native Bool, Int and String
specializations have size/stride 1, 8 and 16 respectively, with field offset
zero; T has no View constraint or witness argument.

The generic bit stays set. Symbolic lookup rejects before attempting the
nongeneric accessor ABI, and the two-argument generic accessor diagnoses
without reading T metadata. No complete metadata, instantiation cache,
generic metadata pattern or reflection is supplied. TupleView metadata
instantiation and rendering remain unsupported.

`tests/ios/native-checks.v build-swiftui-tuple-nominal` checks eight cold
readers, the native declaration, read-only descriptor and executable accessor
protections, direct/indirect symbolic rejection at a guard boundary, 32
terminal child calls with protected or invalid T metadata, retirement guards,
teardown callbacks and two drained/unmapped lifetimes. Native measurements,
State nominal and ZStack View sanitizer regressions, generated C and isolated
ARM64 results are retained under
`build/ios/fortnite/swiftui-tuple-nominal-checks`. Its
required import cell is `0x10dc9b438` in `__DATA_CONST,__got`, referenced by
seven indirect context symbolic references in `__TEXT,__swift5_typeref`.
These data references were inspected without executing application code.

TupleView's value initializer, `_$s7SwiftUI9TupleViewVyACyxGxcfC`, now
constructs the stored value through T's `initializeWithTake` witness. Native
ARM64 takes the consumed source address in x0, complete T metadata in x1 and
the indirect result in x8. The sealed adapter rearranges these arguments and
calls the take witness once, without retaining or releasing the moved value.
The source becomes uninitialized. No TupleView metadata or View graph is
needed for this operation.

Native/Vinix comparisons cover seven layouts: Void, Bool, UInt8, Int,
Optional<Int>, String and SIMD4<Float>. An owned native String moves without
an extra retain; native TupleView copies and destruction balance ownership.
Fifteen synthetic size/stride cases cover both guard boundaries, read-only
POD sources, exact result spans and protected zero-size source/result pointers.
A forbidden copy witness checks that construction uses the take slot, and a
reentrant witness resolves the initializer from another thread.

`tests/ios/native-checks.v build-swiftui-tuple-init` also checks eight cold
readers, exact routing, executable adapter protection, preserved x20/x21,
unused protected registers/stack, warm teardown callbacks and two
drained/unmapped lifetimes. Native measurements, TupleView nominal and State
getter sanitizer regressions, generated C and isolated ARM64 results are
retained under `build/ios/fortnite/swiftui-tuple-init-checks`.
TupleView metadata instantiation, graph execution and rendering remain
unsupported. Its required
import cell is `0x10dc9b440`, stub `0x10c63abd8`, forwarder `0x107c28ed4`
and direct call `0x1015c053c`. These references were inspected without
executing application code.

TupleView's View conformance descriptor, `_$s7SwiftUI9TupleViewVyxGAA0D0AAMc`,
now resolves through SwiftUI.framework in the existing sealed nominal arena.
Native Bool, Int and String specializations share one static seven-word
witness table. Conformance flags are zero, with no conditional requirements,
generic witness control or instantiator; T remains unconstrained in the
nominal signature. The declaration includes View's Body: View signature and
tagged symbolic Body == Never records. Never metadata, its View conformance
and all four graph witnesses terminate with explicit diagnostics when used.
They do not read caller metadata or arguments or write an indirect result.

`tests/ios/native-checks.v build-swiftui-tuple-view` checks eight cold readers
in both resolution orders, canonical descriptors, the native static table,
read-only data and executable thunk protections, protected unused arguments,
256 terminal child calls, protected graph stack/Self/x8, unchanged shared
writable/read-only result pages at both guard boundaries, teardown callbacks
and two drained/unmapped lifetimes. Native measurements, TupleView nominal
and initializer sanitizer regressions, generated C and four isolated ARM64
phases are retained under `build/ios/fortnite/swiftui-tuple-view-checks`.
TupleView metadata instantiation, graph execution and rendering remain unsupported.
The conformance's required cell is `0x10dc9b448`. Consumers at `0x1015c05d4` and
`0x1015c111c` load it before calling `swift_getWitnessTable` at `0x1015c05dc`
and `0x1015c1124` respectively. These references were inspected without
executing application code.
SwiftUI's global Never: View witness table, `_$ss5NeverO7SwiftUI4ViewACWP`,
now resolves in the existing opacity arena. The seven-word static table has
conformance flags 8 and an indirect reference to the arena's Never descriptor.
It shares complete zero-size, stride-one Never metadata and the existing
View declaration. Body metadata lookup returns Never; the tagged `FF 07`
associated-conformance accessor returns this same canonical table without
reading caller metadata or arguments. No additional arena or owner is allocated.

Native measurements confirm `Never.Body == Never`, recursive `Body: View`
and a view-list count of `nil`. The count witness returns zero in x0 and the
None tag in w1, without reading inputs or writing x8. The two graph factories
and `Never.body` stop with explicit diagnostics. TupleView's dependent
metadata and graph paths still diagnose as described above.

`tests/ios/native-checks.v build-swiftui-never-view` checks eight cold readers
in both opacity/table resolution orders, shared metadata, recursive conformance,
protected arguments, native-compatible count results, x20/x21 preservation,
120 terminal graph/body child calls, protected stack/Self/x8 and unchanged
writable/read-only result pages at both guard boundaries. Native Swift's
associated-conformance lookup caches authenticated pointers; its cross-check
uses a writable table copy while Vinix's table remains read-only. Shutdown
callbacks and two drained/unmapped lifetimes use the existing arena.
Native measurements, opacity and TupleView View sanitizer regressions,
generated C and four isolated ARM64 phases are retained under
`build/ios/fortnite/swiftui-never-view-checks`. Graph construction and rendering
remain unsupported.

Its required cell is `0x10dc9b450`; a consumer at `0x1015c103c` loads the
table and returns it directly. This reference was inspected without executing
application code.
The Objective-C exception personality import, `___objc_personality_v0`, now
resolves through libobjc.A.dylib to an explicit terminal diagnostic. The
unwinder supplies version, actions, exception class, exception storage and
context in x0..x4. The diagnostic stops before reading or modifying exception
state and returns no unwind reason code. It allocates no metadata or owners.
Native export inspection and [Apple's runtime source](https://github.com/apple-oss-distributions/objc4/blob/main/runtime/objc-exception.mm)
establish the ABI and alternate-handler/C++ personality delegation. Mach-O
frame registration, exception throwing, catching and unwinding remain unsupported.

`tests/ios/native-checks.v build-objc-personality` checks eight readers and
16,384 concurrent resolutions, exact library routing and 180 terminal child
calls across version/action/class combinations, null/invalid/protected
exception/context pointers and protected unused registers, stack, Self and x8.
Shared writable/read-only state stays unchanged at both guard boundaries.
The entry remains stable before startup, in shutdown callbacks and after
two drained runtimes. Native source/export measurements, NSException type
metadata and uncaught-handler sanitizer regressions, generated C and four
isolated ARM64 phases are retained under `build/ios/fortnite/objc-personality-checks`.

Its required cell is `0x10dc9b458` in `__DATA_CONST,__got`. The compact-unwind
personality entry at `0x10dc81200` references this cell as personality index
zero. These unwind data were inspected without executing application code.
The next required import was `_imp_implementationWithBlock`, Objective-C's
block-to-method adapter.
Its required cell is `0x10dc9b498`, stub `0x10c63dd4c` and branch forwarder
`0x107c28ddc`. Calls at `0x10833f5a4` and `0x10008b258` pass Blocks and use
the resulting IMP for method replacement or installation. These references
were inspected without executing application code.
`imp_implementationWithBlock`, `imp_getBlock` and `imp_removeBlock` now resolve
through libobjc.A.dylib. The adapter copies its Block and emits a four-instruction
ARM64 tail call from `(self, _cmd, args...)` to `(block, self, args...)`.
It discards the selector, preserves x2..x8, q0..q7 and the original stack and
link register, and leaves the Block's return convention intact. Each live IMP
owns one page sealed read/execute after emission; no writable executable page
is published. Global Blocks retain their identity and heap Blocks share their
existing copy reference. This follows the [Apple SDK/runtime contract](https://github.com/apple-oss-distributions/objc4/blob/main/runtime/objc-block-trampolines.mm).

Lookup returns a borrowed Block. Removal drops the registry entry before
releasing its copy and unmapping the adapter. Callers must detach the IMP and
drain its invocations before removal, and coordinate borrowed Block use with
removal. Copy and disposal helpers run outside the runtime lock. Quiescent
shutdown releases remaining IMPs after ordinary app owners and threads drain,
while class metadata, Foundation objects and autorelease pools remain available
to capture destructors. Those destructors must not invoke retired IMPs.

`tests/ios/native-checks.v build-objc-block-imp` compares raw ARM64 x0..x8,
all eight SIMD argument registers, four stack words and result bits against
Apple's native adapter. It also checks stack/global/shared heap Block ownership,
four concurrent creators, real method installation and replacement, cross-thread
copy/dispose reentry, captured-object weak lifetime, invalid identities and two
drained runtimes. Six sanitizer runs, property/monitor regressions, generated C,
native source snapshots and four isolated ARM64 phases are retained under
`build/ios/fortnite/objc-block-imp-checks`.

The begin-catch import has required cell `0x10dc9b508`, stub `0x10c63e190`
and branch forwarder `0x107c28288`.
The inspector found 27 direct calls, including `0x100008668`, followed by
exception cleanup and `_objc_end_catch` paths. These references were inspected
without executing application code. The paired end-catch import has cell
`0x10dc9b548`, stub `0x10c63e1f0`, forwarder `0x107c2828c`, an additional tail
forwarder at `0x1000555d8` and 45 direct calls.

With `ios_cxx`, `_objc_begin_catch` and `_objc_end_catch` now resolve to the
existing C++ backend's `__cxa_begin_catch` and `__cxa_end_catch` addresses.
This matches [Apple's delegation](https://github.com/apple-oss-distributions/objc4/blob/main/runtime/objc-exception.mm):
both languages share adjusted exception pointers, handler ownership and
thread-local catch bookkeeping. The compatibility layer adds no private
exception layout, TLS, Objective-C retain or pointer adjustment. In particular,
a foreign catch-all result must not be interpreted as an Objective-C object.
Builds without `ios_cxx` bind explicit terminal diagnostics before reading
exception storage or returning a fabricated catch result.

`tests/ios/native-checks.v build-objc-catch` checks exact backend aliases,
four mixed-language begin/end combinations, foreign adjusted pointers,
single cleanup, empty-stack end after a completed catch and four simultaneous
thread-local catches. Native Apple comparisons use the same cases without
throwing or unwinding. Eight resolver readers, exact library routing, shutdown
callback access and two drained runtimes are also checked. The no-backend
host variant checks 48 terminal child calls with null/invalid/protected storage,
protected unused registers/stack/x8 and unchanged writable/read-only result
pages. Six sanitizer runs, the personality regression, generated C, native
source snapshots and four isolated ARM64 phases are retained under
`build/ios/fortnite/objc-catch-checks`. This implements catch bookkeeping for
valid unwind records; full Objective-C throwing/catching and Mach-O frame
unwinding remain unsupported.

The atomic C++ property helper has required cell `0x10dc9b518`, stub
`0x10c63e1a8` and branch forwarder
`0x107c28cc0`. Four additional tail forwarders, including `0x100b60788` and
`0x102155080`, pass storage and a copy callback to this atomic C++ property
helper. These references were inspected without executing application code.

`_objc_copyCppObjectAtomic` now resolves through libobjc.A.dylib. It locks
both storage addresses in a consistent order and invokes the supplied copy
callback exactly once, including for self-copy. Equal addresses and hash
collisions acquire one lock. The callback defines the copy and C++ resource
ownership; the helper neither reads storage itself nor retains Objective-C
objects. This follows [Apple's accessor implementation](https://github.com/apple-oss-distributions/objc4/blob/main/runtime/objc-accessors.mm)
and [lock ordering](https://github.com/apple-oss-distributions/objc4/blob/main/runtime/Threading/mixins.h).
Eight padded native mutexes occupy a fixed 1 KiB table, use the iOS pointer
hash and remain available before startup, during shutdown callbacks and across
runtime lifetimes. The registry lock is released before locking storage or
calling the callback, and the helper allocates no per-copy storage.

`tests/ios/native-checks.v build-objc-cpp-copy` compares callback forwarding
for null/invalid/protected identities, self-copy and callback-managed ownership
with Apple's native runtime. It checks eight simultaneous cold callers,
eight-worker torn-copy and opposing-pair stress, hash collisions, nested
disjoint copies, cross-thread registry/independent-copy progress, shutdown
callbacks and two drained runtimes. Six sanitizer runs, property/monitor
regressions, generated C/ARM64 review, native sources and four isolated ARM64
phases are retained under `build/ios/fortnite/objc-cpp-copy-checks`.

The struct-copy helper has required cell `0x10dc9b520`, stub `0x10c63e1b4`
and branch forwarder `0x107c290fc`.
The additional tail forwarder at `0x1020c18d0` passes a 32-byte size,
atomic=true and hasStrong=false. These references were inspected without
executing application code.

`_objc_copyStruct` now resolves through libobjc.A.dylib. It performs an
overlap-safe `memmove` of the requested bytes. Atomic calls lock both endpoint
addresses in a consistent order, acquiring equal or colliding stripes once.
Nonatomic calls bypass initialization and all locks. As in [Apple's implementation](https://github.com/apple-oss-distributions/objc4/blob/main/runtime/objc-accessors.mm),
the obsolete `hasStrong` flag is ignored: copied bytes receive no Objective-C
ownership treatment. The eight native mutexes occupy a separate 1 KiB table
and remain available across runtime lifetimes; the C++ callback-copy table is
independent. There is no per-copy allocation.

`tests/ios/native-checks.v build-objc-struct-copy` compares guard-page lengths,
unaligned endpoints, zero-byte protected boundaries, self/overlapping moves,
opaque pointer bytes with both flags and eight-worker 16 KiB copy contention
against Apple's native runtime. It also checks eight simultaneous cold callers,
hash collisions, nonatomic progress with the registry and all struct locks held,
independence from the C++ copy table, unrelated-stripe progress, shutdown
callbacks and two drained runtimes. Six sanitizer runs, C++ copy/property
regressions, generated C/ARM64 review, native sources and four isolated ARM64
phases are retained under `build/ios/fortnite/objc-struct-copy-checks`.

The rethrow import has required cell `0x10dc9b558`, stub `0x10c63e208` and branch forwarder
`0x107c2837c`. Four direct calls, including `0x1000554a0` and `0x10005ebb8`,
were inspected without executing application code.

With `ios_cxx`, `_objc_exception_rethrow` now resolves to the existing C++
backend's `___cxa_rethrow` address, following [Apple's delegation](https://github.com/apple-oss-distributions/objc4/blob/main/runtime/objc-exception.mm).
That backend currently stops with an explicit diagnostic because Mach-O
unwinding is unsupported. Builds without `ios_cxx` bind a dedicated terminal
diagnostic. This closes the import binding; actual rethrowing remains
unsupported. No native host unwinder is called, and the compatibility entry
adds no exception layout, TLS, ownership or fabricated unwind result.

`tests/ios/native-checks.v build-objc-rethrow` checks the exact backend alias,
96 terminal child calls with empty/foreign catch bookkeeping, protected values
in unused registers/stack words/Self/x8 and unchanged writable/read-only pages
at both guard boundaries. The no-backend host variant checks 48 terminal child
calls. Eight readers perform 16,384 resolutions across two drained runtimes;
shutdown callbacks can still resolve the entry. Native exports and source
delegation were checked without invoking native rethrowing or unwinding.
Six sanitizer runs, the catch bookkeeping regression, generated C/ARM64 review,
native sources and four isolated ARM64 phases are retained under
`build/ios/fortnite/objc-rethrow-checks`.

The throw import has required cell `0x10dc9b560`, stub `0x10c63e214`, branch forwarder
`0x107c28414` and direct call `0x10009f110`. These references were inspected
without executing application code.

`_objc_exception_throw` now binds a dedicated terminal diagnostic with its
single object argument, in both C++ backend configurations. Actual throwing
remains unsupported. The entry stops before reading the object, changing its
ownership, invoking an uncaught handler or allocating exception metadata.
[Apple's implementation](https://github.com/apple-oss-distributions/objc4/blob/main/runtime/objc-exception.mm)
builds an Objective-C exception record, preprocesses and retains the object,
and passes typeinfo plus a release destructor to the three-argument C++ throw
entry. Those requirements prevent forwarding the raw object directly to
`__cxa_throw`; Mach-O unwinding must be implemented before adding that path.

`tests/ios/native-checks.v build-objc-throw` checks the exact diagnostic binding,
192 terminal child calls per run with null/invalid/protected/managed/class
objects and absent/trapping/protected uncaught handlers, protected values in
unused registers/stack words/Self/x8 and unchanged writable/read-only pages
at both guard boundaries. Eight concurrent resolver readers, shutdown callback
access and two drained runtimes are also checked. Native exports and the Apple
ownership contract were inspected without invoking native throwing/unwinding.
Six sanitizer runs cover both backend configurations and the rethrow regression;
generated C/ARM64 review, native sources and four isolated ARM64 phases are
retained under `build/ios/fortnite/objc-throw-checks`.

The terminate import has required cell `0x10dc9b6e8`, stub `0x10c63e454`
and branch forwarder `0x107c28380`.
Four direct calls, including `0x1000554b8` and `0x10005ebd0`, were inspected
without executing application code.

With `ios_cxx`, `_objc_terminate` now resolves to the existing backend's
`__ZSt9terminatev` address, following [Apple's public entry](https://github.com/apple-oss-distributions/objc4/blob/main/runtime/objc-exception.mm).
It shares the backend's C++ terminate-handler state. Custom handlers receive
the call; default handlers and handlers that return end in SIGABRT. Builds
without `ios_cxx` bind an explicit terminal backend-required diagnostic.
The entry adds no separate handler registry, exception ownership or unwinder.
Objective-C uncaught-handler delivery is not implemented by this binding;
full Objective-C throwing/catching and Mach-O frame unwinding remain unsupported.

`tests/ios/native-checks.v build-objc-terminate` checks the exact backend alias,
384 terminal child calls with empty/foreign catch bookkeeping, two custom
handlers, default/returning-handler SIGABRT, protected unused arguments, stack
words, Swift Self and x8, and unchanged writable/read-only pages at both guard
boundaries. The no-backend variant checks 192 terminal diagnostic calls even
when C++ handlers are installed. Test-only typed declarations access the linked
backend's handler state without exposing new application imports. Native Mac
comparisons check both custom handlers and returning-handler SIGABRT in isolated
children, without throwing or unwinding. Eight concurrent resolver readers,
shutdown callback access and two drained runtimes are also checked.
Six sanitizer runs cover both backend configurations and the throw regression;
generated C/ARM64 review, native sources and four isolated ARM64 phases are
retained under `build/ios/fortnite/objc-terminate-checks`.

The protocol-method import has required cell `0x10dc9b710`, stub `0x10c63e568`,
branch forwarder `0x107c283c4` and two direct calls (`0x100055b28`, `0x100080f04`)
that were inspected without executing application code.

`_protocol_getMethodDescription` now returns the canonical selector and borrowed
type-encoding pointer in ARM64 registers x0/x1. Required/optional and
instance/class declarations use four separate lists. Lookup checks the protocol
itself before walking adopted protocols depth first in declaration order,
matching [Apple's runtime](https://github.com/apple-oss-distributions/objc4/blob/main/runtime/objc-runtime-new.mm).
Nil protocols/selectors and missing methods return two null pointers. A found
declaration preserves the distinction between null and empty type encodings.

Image registration validates big and direct/indirect relative method lists
before publishing protocol roots or rewriting references. Protocol declarations
have no executable implementation to validate; their IMP fields are not followed.
Selectors are interned and type encodings copied into protocol-owned storage.
Duplicate aliases keep the first declaration, so returned pointers remain valid
after source metadata is retired and until quiescent runtime shutdown. The six
built-in protocols also carry their 26 ARM64 method declarations. Each list is
limited to 4096 entries; names and type encodings retain the existing 1023-byte
and 65535-byte limits. Lookup uses bounded stack scratch and allocates no heap
storage. Shutdown frees every owned encoding and method map.

`tests/ios/native-checks.v build-protocol-method` compares all four lookup modes,
own/inherited/diamond precedence, Unicode and long encodings, nil/missing results
and the raw x0/x1 ABI against the native Mac runtime. Private fixtures cover
all three list formats, null/empty type strings, duplicate aliases, guarded
limits, malformed registration without partial publication, protected source
retirement, invalid identities, cycles, eight concurrent readers and callback
access during two drained runtime lifetimes. Six sanitizer runs cover both C++
backend configurations and the existing protocol lookup regression. Its test
class helper was renamed to avoid a collision with the system resolver header.
Generated C/ARM64 review, native sources and four isolated ARM64 phases are
retained under `build/ios/fortnite/protocol-method-checks`.

Fortnite imports 18 fixed-argument functions from `/usr/lib/libsqlite3.dylib`.
The `_sqlite3_bind_blob` required cell `0x10dc9b720`, stub `0x10c63e8ec`, branch forwarder
`0x107c28408` and direct call `0x100057980` were inspected without executing
application code. That call passes the statement, index 3, borrowed blob bytes,
byte length and a null destructor.

The optional `ios_sqlite` backend now binds all 18 functions directly to one
native SQLite engine. Handles, error strings, statement storage and callbacks
stay with that engine; Objective-C shutdown does not close database handles.
Only the exact library and symbol names resolve. Without the backend the
imports remain unresolved. Variadic APIs and extension-loading APIs are not
exported. Static, transient and custom-destructor ownership follows the
[SQLite binding API](https://www.sqlite.org/c3ref/bind_blob.html).

`tests/ios/sqlite-build.v` builds the unmodified SQLite 3.53.4 amalgamation
verified against `tests/packages/sqlite-source.json`. The ARM64 archive reserves
x18, enables thread safety and omits extension loading. The public native-checks
driver enables the backend when `build/ios/sqlite/build.status.txt` exists;
`VINIX_IOS_SQLITE_SDK` selects another SDK directory. A host build using
`-d ios_sqlite` links its system SQLite through `-lsqlite3`.

`tests/ios/native-checks.v build-sqlite` checks all 18 aliases, signed integers,
embedded-NUL text/blob bytes, null/empty/failed binds, destructor counts and
guarded raw ARM64 calls. It also checks reentrant and aborting callbacks, owned
errors, constraint failures, busy close, eight shared-connection writers,
transaction rollback, persistent database files and read-only failures.
The same cases run against native Mac SQLite, and handles survive two drained
Objective-C runtimes. Six host sanitizer runs cover enabled/disabled backends
and the protocol-method regression. Four isolated ARM64 phases, generated C,
resolver disassembly and the complete SQLite archive disassembly are retained
under `build/ios/fortnite/sqlite-checks`; no engine instruction uses x18 or w18.

The `_$sBbWV` data import has required cell `0x10dc9b7b8` and consumer
`0x1000657d8`. The consumer passes the table's layout tail (offset 64) to
`swift_initStructMetadata`; this was inspected without executing application
code.

`Builtin.BridgeObject` now has its own eight-slot value-witness table, following
the [Swift runtime's bridge-aware ownership operations](https://github.com/swiftlang/swift/blob/main/stdlib/public/runtime/MetadataImpl.h).
Copy and destroy preserve the encoded word while using bridge-object ARC.
Assignment publishes the replacement before releasing the old owner, so
reentrant destructors see the new value. Takes leave moved bytes unchanged.
The table has size/stride eight, flags `0x10007` and `0x7fffffff` extra
inhabitants. Its take and enum operations share the existing object-reference
implementations; its ownership operations differ. Both tables are populated
before sealing their shared page and retire together at quiescent shutdown.
Resolving this import adds no extra mapping or per-witness allocation.

`tests/ios/native-checks.v build-bridge-value` compares all eight native slots,
encoded native/Objective-C ownership, spare bridge bits, self copy/take,
null/tagged values and guarded eight/nine-byte enum boundaries. Raw ARM64 calls
check protected unused inputs and result registers. Eight concurrent publishers
and workers, destructor reentry, read-only tables and two unmapped runtime
lifetimes are also checked. Six host sanitizer runs cover both C++ backend
configurations and the existing UnknownObject regression. Native measurements,
generated C/ARM64 review and four isolated ARM64 phases are retained under
`build/ios/fortnite/bridge-value-checks`.

The Dictionary metadata accessor `_$sSDMa` has required cell `0x10dc9b7c8`,
stub `0x10c63ac80`, branch forwarder
`0x107c28a50` and call `0x10006df64` were inspected without executing app code.

The accessor now returns complete metadata in ARM64 x0/x1 for each exact
Key/Value/Key:Hashable triple. The three supplied identities remain borrowed;
the one-word dictionary layout does not require inspecting or completing them.
The generic descriptor records two type parameters, the Key:Hashable requirement,
three key arguments and the field-offset vector at metadata word five, matching
the native runtime. Its descriptor accessor and instantiation pattern return
the same canonical records as direct calls. Specialization pages are sealed
before publication; cache hits allocate nothing. All specialization pages, the
descriptor/accessor arena and cache storage retire after workers and owners
drain. The witnesses share the existing BridgeObject ownership and enum code.
Dictionary construction, mutation, field reflection, String hashing and generic
Encodable/Decodable conformances remain separate unsupported operations.

`tests/ios/native-checks.v build-dictionary-metadata` compares twelve generic
combinations (including Date, Any, Void and a nested Dictionary), six request
states, descriptor fields, all eight value-witness slots and native/Cocoa
ownership. Guarded opaque arguments, invalid and retired requests, raw ARM64
responses, eight publishers/workers, destructor reentry and two unmapped runtime
lifetimes are checked. A caller-supplied Hashable fixture traps on invocation;
metadata construction never invokes it. The host build also corrected the
`mach_timebase_info` pointer declaration to match its native header.
Eight sanitizer runs cover both C++ backend configurations, Array metadata and
process-usage regressions. Native measurements, generated C/ARM64 review and
four isolated ARM64 phases are retained under
`build/ios/fortnite/dictionary-metadata-checks`.

Dictionary's generic Encodable descriptor `_$sSDyxq_GSEsSERzSER_rlMc` now
supports conditional witness specialization. Its required cell `0x10dc9b7d0`
and consumer `0x10006e108` were inspected without executing app code; the
consumer passes Dictionary metadata and two conditional witnesses to
`swift_getWitnessTable`. The descriptor names the canonical Encodable protocol,
the existing Dictionary nominal descriptor, Key/Value conformance requirements
and a two-word pattern with two private words. Specialization follows the
[Swift runtime's conditional argument layout](https://github.com/swiftlang/swift/blob/main/stdlib/public/runtime/Metadata.cpp):
the Key witness precedes the table address point, then the Value witness.
The cache uses canonical Dictionary metadata identity. Hits read no argument
array; misses copy the two borrowed witness identities and seal the page before
publication. Shutdown unmaps these tables before Dictionary metadata, and a
remembered descriptor address rejects stale lookups before reading freed pages.

This implements conformance metadata and table specialization. Calling the
encode witness still stops with `iOS: Swift Dictionary encoding is not
implemented`; Dictionary iteration, Encoder containers and JSONEncoder
serialization remain unsupported.

`tests/ios/native-checks.v build-dictionary-encoding` compares six native
String/Int-key and String/Int/Date-value specializations, descriptor requirements,
private witness order, expired argument cache hits and ARM64 x20/x21 preservation.
Protected borrowed witnesses, an exact argument-array boundary, sealed pages,
eight concurrent publishers/workers, invalid/foreign/retired requests, an encode
diagnostic child process and two drained/unmapped lifetimes are checked.
Eight ASan/UBSan runs cover both C++ backend configurations, Dictionary metadata
and Date regressions. Four isolated ARM64 phases pass. Fresh binaries, generated
C/ARM64 reviews, native measurements and logs are retained under
`build/ios/fortnite/dictionary-encoding-checks`.

Dictionary's generic Decodable descriptor `_$sSDyxq_GSesSeRzSeR_rlMc` now
supports the same conditional specialization. Its required cell `0x10dc9b7d8`
and consumer `0x10006deec` were inspected without executing application code.
The descriptor names the canonical Decodable protocol and its Key/Value
requirements. Encodable and Decodable share the descriptor/table construction
code while keeping distinct method entries, patterns and caches. Both tables
for a type remain canonical under concurrent mixed lookups; neither cache reads
expired argument arrays. Both sets of sealed pages retire before Dictionary
metadata, and stale descriptor lookups fail before reading unmapped storage.
Calling the decoding initializer still stops with `iOS: Swift Dictionary
decoding is not implemented`, without inspecting the Decoder or writing its
indirect result. Dictionary construction, iteration, Encoder/Decoder containers
and JSON serialization remain unsupported.

`tests/ios/native-checks.v build-dictionary-decoding` compares six native
String/Int-key and String/Int/Date-value specializations, conditional descriptor
fields, private witness order, expired input hits and distinct Encodable and
Decodable tables. Guarded witnesses and argument boundaries, x20/x21 preservation,
read-only tables, eight cold publishers and mixed workers, invalid/foreign/retired
requests, a diagnostic child with protected x8 output, and two drained/unmapped
lifetimes are checked. Ten ASan/UBSan runs cover both C++ backend configurations
and the existing Encodable, Dictionary metadata and Date fixtures. Four isolated
ARM64 validation phases pass. Native measurements, binaries, generated C/ARM64
reviews and logs are retained under
`build/ios/fortnite/dictionary-decoding-checks`.

String's `hash(into:)` entry `_$sSS4hash4intoys6HasherVz_tF` now feeds NFC UTF-8
and a separate `0xff` terminator into the existing Hasher, following the
[Swift String hashing contract](https://github.com/swiftlang/swift/blob/main/stdlib/public/core/StringHashable.swift).
Its required cell `0x10dc9b800`, stub `0x10c63acd4`, forwarder `0x107c2892c`
and eight call sites were inspected without executing application code. The
entry borrows the inout Hasher in x0 and String in x1/x2, preserving x20/x21
and the source's ownership. Checked inline strings, immutable literal spans,
registered native tails and registered foreign NSString/decoded constants are
supported up to 1 MiB. Shared/custom storage remains unsupported. Invalid
inputs are rejected before changing the Hasher. ASCII hashing allocates nothing.

Unicode normalization is implemented in V using canonical decomposition,
stable combining-class ordering, blocked composition and algorithmic Hangul.
The tables are generated by `tests/ios/unicode-nfc.v` from pinned Unicode 17.0.0
data, with the Unicode license included in the generated source. The generator
verifies download hashes and can check byte-for-byte reproducibility:

```sh
v run tests/ios/unicode-nfc.v check
```

`tests/ios/native-checks.v build-string-hash` prepares the pinned conformance
data. Its fixture checks all 20,034 records and the five NFC invariants in
[Unicode's normalization conformance test](https://www.unicode.org/Public/17.0.0/ucd/NormalizationTest.txt).
Native Swift comparisons check all 72 Hasher bytes across eight incoming tail
lengths and repeated strings, including composed/decomposed text, Hangul,
combining-order changes, compatibility characters and embedded NULs. Guarded
source boundaries, native-tail/foreign ownership, invalid/retired input rejection,
four workers and two drained lifetimes also pass. Eight ASan/UBSan runs cover
both C++ backend configurations and the existing Hasher and String replacement
fixtures. Four isolated ARM64 phases, generated C/ARM64 reviews, original-image
traces and native measurements are retained under
`build/ios/fortnite/string-hash-checks`.

The fresh launch exits 1 during linking at String's `count` getter,
`_$sSS5countSivg`. Its required cell `0x10dc9b808`, stub `0x10c63ace0`,
forwarder `0x107c28a80` and call `0x10006fb98` were inspected without executing
application code.
Fortnite still stops before application entry and remains unplayable.

`run-ios --audit BINARY` now checks each bundled library's imports as well as
the executable, without mapping or executing app code. The static C++ runner reports:

| Image | Resolved | Unresolved strong | Unresolved weak |
| --- | ---: | ---: | ---: |
| Fortnite executable | 1,900 | 261 | 78 |
| EOSSDK | 661 | 3 | 16 |
| MarketplaceKitWrapper | 179 | 0 | 20 |
| All images | 2,740 | 264 | 114 |

The C++/GLES/Text variant reports 2,754 resolved imports, 250 unresolved strong
imports and 114 unresolved weak imports, including its native zlib/text backends.
Both measurements include the optional SQLite backend.

Resolved imports measure linker bindings. Diagnostic entries such as the
view and view-list factories and identified-tree hook still stop execution
when reached; the count does not measure functional API coverage.

The executable's available imports include the bundled frameworks' exports;
their own unresolved dependencies still prevent execution. Results depend on
compiled optional backends. The executable includes these substantial dependencies:

| Dependency | Imports | Remaining work |
| --- | ---: | --- |
| Bundled EOSSDK | 589 | The SDK's own Foundation, Swift, networking, security and other dependencies |
| Swift core runtime | 207 | Darwin Swift runtime ABI |
| Foundation | 159 | Broader Objective-C and Swift APIs |
| SwiftUI | 73 | Framework implementation |
| Metal | 22 | Device, shader, rendering and presentation implementation |

Swift concurrency, networking, security, audio and other frameworks are also
referenced. Chained strong imports must resolve before execution. Successful
metadata inspection, an unencrypted executable, or the tagged-pointer fix
does not establish Fortnite compatibility. Startup, rendering, input, asset
loading and online play remain unsupported or unverified; there is no Fortnite
desktop launcher or claim of playable support.

On this prepared Mac checkout, the V driver uses the ARM64 userland sysroot,
native C++ archives, private GLES closure, preserved socket kernel, existing
fixtures and extracted IPA under `build/ios/fortnite`:

```sh
v -nocache -cc clang run tests/ios/sqlite-build.v \
  build/package-sqlite-work/inputs/source build/ios/sqlite
v -nocache -cc clang run tests/ios/native-checks.v build
v -nocache -cc clang run tests/ios/native-checks.v regression
v -nocache -cc clang run tests/ios/native-checks.v swift
v -nocache -cc clang run tests/ios/native-checks.v objc
v -nocache -cc clang run tests/ios/native-checks.v probe
v -nocache -cc clang run tests/ios/native-checks.v audit
v -nocache -cc clang run tests/ios/native-checks.v static-audit
v -nocache -cc clang run tests/ios/native-checks.v verify-monitor
```

`VINIX_IOS_CHECK_NAME` selects a single output directory name under
`build/ios/fortnite` (default `select-checks`; the timestamp/UUID verification uses
`file-time-checks`, the audio constants use `audio-session-checks`, and
CoreFoundation dictionaries use `cf-dictionary-checks`, supplied Objective-C
storage uses `objc-storage-checks`, associated objects use
`objc-associated-checks`, property access uses `objc-property-checks`,
object monitors use `objc-sync-checks`, Swift strings/buffers use
`swift-string-checks`, and String metadata/witnesses use
`swift-metadata-checks`). Each
mode records its own state path and guest `serial.log`
there. Regression runs the native V select, semaphore, signal, error, sysctl,
terminal, thread-policy, file timestamp, UUID, audio-session constant and
CoreFoundation dictionary, supplied Objective-C storage, associated-object,
property, object-monitor, Swift string/buffer and String metadata/witness checks before the
existing Mach-O suite and requires the guest PASS marker.

`swift` runs all twenty-eight Swift ABI checks in a small, independent guest and
requires `VINIX iOS SWIFT: PASS`. It does not establish full regression success.
Probe, audit and Swift modes retire their staging copies after archiving the
root filesystem, before constructing the boot disk, to limit host disk use.
Probe/audit streams the preserved Fortnite executable through this Mac's
libarchive without extracting another large copy. Probe/audit completion records
the actual child exit status, which remains 1
for Fortnite. Completion does not mean the game ran. The driver does not build
missing dependency trees or invoke the concurrent Python controller migration.
`tests/ios/trace-import.v` finds direct ARM64 calls and tail branches to an
import's Mach-O stub with the installed LLVM tools. The proprietary IPA and
its extracted bytes are not committed.

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
tests/ios/run --no-build --with-cxx --with-ppsspp
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

**The unchanged PPSSPP release binary renders its menus and runs PSP homebrew
and a commercial PSP demo on Vinix, with sound disabled.** With the optional
runtime, it runs
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
tests/ios/run --no-build --with-cxx --with-gles --with-2048 \
  --with-ppsspp --ppsspp-muted --timeout 300 > build/ios/ppsspp-guest.log 2>&1
tests/ios/frame build/ios/ppsspp-guest.log build/ios/ppsspp-settings.png
```

The test uses the installed launcher with fresh preferences, runs beyond the
splash transition, clicks Settings through native UIKit, checks detailed changing
pixels and verifies exit status zero and shared-surface removal. It emits
`iOS PASS: upstream PPSSPP native framebuffer and process lifecycle (muted)`.

To exercise PSP emulation, use the pinned `cube.pbp` from PPSSPP's
[upstream PSP tests](https://github.com/hrydgard/pspautotests/blob/f93c29855718a587360976e793f5b41a88ef7e68/demos/cube.pbp).
The downloader verifies the 50,600-byte PBP header and SHA-256
`4018ec0da8a88a1600380661bcd4461c09c4c69bc45139ec626a754f0eec3fc0`.
Its `Cube Sample` MIPS executable draws the textured rotating cube from the
[PSPSDK cube sample](https://github.com/pspdev/pspsdk/blob/master/src/samples/gu/cube/cube.c).
Neither the PSP binary nor the iOS executable is rewritten.

```sh
tests/ios/run --no-build --with-cxx --with-gles --with-2048 \
  --with-ppsspp --ppsspp-muted --ppsspp-cube --timeout 300 \
  > build/ios/ppsspp-cube-guest.log 2>&1
tests/ios/frame build/ios/ppsspp-cube-guest.log build/ios/ppsspp-cube.png
```

The test passes `/opt/ios/cube.pbp` to the installed launcher. UIKit supplies a
real file `NSURL` through `UIApplicationLaunchOptionsURLKey` and the scene's
`UIOpenURLContext`; PPSSPP's native scene delegate puts that path in its own
startup arguments. Its CPU uses the normal IR interpreter fallback when Darwin
JIT probes fail. Its Mach allocation/remap calls share PSP RAM across the
emulator's address views, and `pread` reads the actual PBP. Native pattern fills
clear that RAM and native wide-character functions support its loading paths.

The regression requires PPSSPP's own `Booted /opt/ios/cube.pbp...` diagnostic,
the demo's ABGR clear color in two frames after boot, thousands of colored
geometry pixels, and at least 1,000 changed pixels within the PSP viewport.
The screenshot contains the cube and PPSSPP's original touch controls.
Calculator, 2048, native C++/UIKit/GLES fixtures and process teardown run in the
same Vinix guest. Separate iOS fixtures test RAM aliases after source removal,
occupied fixed targets, real VM errors, positional-I/O offsets, pattern-fill
boundaries, and file-URL encoding/ARC ownership. The VM, file-launch and stdio
fixtures also pass the ARM64 host's ASan/UBSan checks.

For a full 3D game, the regression downloads the developer's PSP build of
[Nazi Zombies: Portable](https://docs.nzp.gay/landing/), a Quake-based survival
shooter. Its engine is GPL-2.0 and its project assets are CC-BY-SA-4.0; the
download retains the packaged licenses. The pinned
[2026-09-24 nightly](https://github.com/nzp-team/nzportable/releases/tag/nightly)
is `2.0.0-indev+20260924124055`:

```text
PSP ZIP:    64,412,845 bytes
SHA-256:    2983183a7d7d6471e8ebf2c5c95290ddd558a1c44d46b9ba6a68e9987f02e89f
EBOOT.PBP:  1,539,962 bytes
SHA-256:    4b916c0b1d9f1607604623240b31c7291fcb9ec1585836d0a2eb3fcbd0e16d57
```

The upstream nightly URL changes when a new build is published. The downloader
checks the pinned size and hash and rejects a changed release. Keep the verified
`build/ios/nzportable/nzportable-psp.zip` cache to reproduce this exact build.
Its 1,310 ZIP members expand to 98,449,920 bytes, including maps, models,
textures, game code and sounds. Neither `EBOOT.PBP` nor PPSSPP's Mach-O is
patched or rebuilt.

```sh
tests/ios/run --no-build --with-cxx --with-gles --with-2048 \
  --with-ppsspp --ppsspp-muted --ppsspp-nzp --timeout 300 \
  > build/ios/ppsspp-nzp-guest.log 2>&1
tests/ios/frame build/ios/ppsspp-nzp-guest.log build/ios/ppsspp-nzp-before.png --frame 0
tests/ios/frame build/ios/ppsspp-nzp-guest.log build/ios/ppsspp-nzp.png
```

The game is installed under the emulated memstick's `PSP/GAME/nzportable`,
preserving its asset paths. The test presses PPSSPP's original touch controls
to select **SOLO → Nacht der Untoten → START GAME**. It uses normal `setup.ini`
arguments `-condebug +developer 1 +exec vinix-input.cfg`; the extra
config binds SELECT to the engine's existing `edict 1` diagnostic command,
followed by an `echo` marker so each report is read after all fields are written.
This exposes the actual player's origin, health and magazine count in
`nzp/condebug.log`. No engine test mode or substitute game implementation is
used. The regression requires the game's `SpawnServer: ndu` and `Server spawned.`
messages, movement of at least ten map units after holding Triangle, and a
decreased magazine count after pressing the right shoulder button. It checks
the emulator's own boot diagnostic, detailed changing pixels and process
teardown, and exports full 390×680 gameplay frames before and after input.
Success emits `iOS PASS: unchanged PPSSPP iOS binary plays NZP PSP shooter`.
The 2026-10-06 ARM64 QEMU run reported position `(1194.1, 2103.7, 80.0)`
changing to `(1024.0, 2076.7, 80.0)`, magazine `8 → 5`, health `100`, and
84,592 changed framebuffer pixels. The full guest regression passed, including
calculator, 2048, C++/UIKit/GLES and shutdown checks. This run uses the IR
interpreter and software OpenGL rendering; sound remains disabled.

The next commercial-game probe uses **God of War: Chains of Olympus — Battle
of Attica**, Sony's playable PSP demo, disc ID `UCUS98713`. Sony announced
[the Battle of Attica demo](https://blog.playstation.com/2007/09/27/god-of-war-chains-of-olympus-special-edition-demo-disc/)
in 2007. The PBP used here comes from
[PlayDreamCreate's demo archive](https://playdreamcreate.com/), linked by
[PPSSPP's official demos documentation](https://www.ppsspp.org/docs/getting-started/how-to-get-demos-and-homebrew/).
It does not require App Store credentials. The downloader pins the following
locally measured sizes and hashes, not publisher-supplied checksums:

```text
PSP ZIP:    169,451,774 bytes
SHA-256:    6c1e4cffecf389e5dbcc995564e3d311afcfd9beaa493e6feace642aa57785ea
EBOOT.PBP:  169,451,184 bytes
SHA-256:    7d147100be1127d87351042a22526cc64c3229e9b0a9fb984bcd5e0aa20a1523
```

Its original `PARAM.SFO` identifies `God of War(R): Chains of Olympus Demo`,
version `1.00`, requiring PSP firmware `3.51`. The PBP retains its encrypted
`NPUMDIMG` data; PPSSPP's own loader handles it. The downloader checks the exact
archive members, executable size/hash and headers, and installs it under
`PSP/GAME/UCUS98713`. Neither the demo nor PPSSPP's iOS executable is rebuilt or
patched. The binaries remain in the ignored build directory.

```sh
tests/ios/run --no-build --with-cxx --with-gles --with-2048 \
  --with-ppsspp --ppsspp-muted --ppsspp-gow --timeout 1200 \
  > build/ios/ppsspp-gow-guest.log 2>&1
tests/ios/frame build/ios/ppsspp-gow-guest.log build/ios/ppsspp-gow.png
```

The probe sets the normal `[Graphics] InternalResolution=1` preference instead
of PPSSPP's iOS default of 2× resolution. This reduces the software renderer's
work while preserving the demo's PSP rendering effects. It waits for colored
title-screen pixels, then presses Cross to start/skip the introduction until
the game's green health HUD appears. PPSSPP's original fast-forward control
runs the landing and camera introduction; the test releases it before capturing
the opening scene, dragging the original analog stick left and pressing Square
three times. The pixel checks require the health HUD and a detailed environment
in both game frames, and at least
1,000 changed pixels inside the PSP viewport, excluding the controls below it.
Full 390×680 frames preserve the scene before movement, after movement and after
the attack inputs. Start opens the game's own pause/upgrade menu, which removes
the gameplay health HUD; pressing Start again must restore it and the environment.
The test then confirms/jumps with Cross, performs light combos with Square,
uses Triangle for heavy attacks and advances with the analog stick. It requires
the game's red-orb counter to grow from its initial single `0` into an additional
digit, identified by red font pixels in the fixed HUD field. This checks an
actual combat/pickup result; a changing camera sequence alone cannot pass it.
The emulator's own native boot diagnostic and normal process teardown are also
required. The final exported frame is after combat and pickups.

The demo's first rendering work can exceed the small fixtures' 30-second IPC
deadline. This probe allows 120 seconds per reply, with the outer VM deadline
still bounding the whole run. It captures actual GLKView shared-buffer pixels,
and feeds ordinary UIKit touch events to PPSSPP's original on-screen controls.

Verified on 2026-10-06 in the ARM64 Vinix QEMU guest: 82,841 changed viewport
pixels after the analog input, health-HUD pixels `52 → 0 → 52` across
pause/resume, and second-digit red font pixels `0 → 9` after nine combat batches.
The final native frame shows **14 red orbs and a six-hit combo**, with Kratos
alive. PPSSPP's native boot and clean process/surface teardown passed, followed
by the calculator, 2048, C++/UIKit/GLES and other iOS regression checks. The
complete log is `build/ios/ppsspp-gow-guest.log`; its final combat screenshot is
`build/ios/ppsspp-gow.png`. This run uses the original IR interpreter fallback
and Mesa software OpenGL; sound remains disabled. The complete retail game and
the rest of the demo have not been tested.

`vinix-ios-ppsspp [PSP game file]` accepts a startup file;
`VINIX_IOS_OPEN_FILE` supplies one when the launcher has no file argument. The
file must exist in the guest. As with other GUI apps, the launching compositor
must supply its request/response pipes; the command alone in a shell does not
create a desktop window. General URL schemes and subsequent open-file events
remain unsupported.

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
fixtures cover the legacy Fortnite/EOSSDK C++ imports, futures, weak ownership,
Darwin random_device tokens/storage and formatted abort diagnostics. The same
extended fixture runs against the installed Mac library as a reference. Its
native ELF version catches vector length/range errors using the runner's actual
archive and registered ELF unwind metadata. This does not provide Mach-O
exception unwinding. Additional native
Mach-O fixtures cover lazy unsupported imports, Darwin FILE/varargs/stat/mmap
layouts, superclass/category load order, reentrant class initialization,
Objective-C++ ivar lifetime, UTF-16 strings, notification removal/weak filtering,
weak GameController notification constants, scene connection, and preferences
across separate process executions. XML plist tests preserve whitespace and
mixed text/CDATA order:

```sh
tests/ios/run --with-cxx --with-2048 --with-ppsspp
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

The rotating-cube homebrew, NZ:P's Nacht der Untoten and God of War's opening
demo scene have been tested. The full retail God of War game and the rest of
the demo are untested. Remaining work includes audio/device
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
./tests/ios/uikit # after building build/ios/run-ios-host above
tests/ios/run
./tests/ios/desktop --desktop build/vinix-desktop
# Upstream iOS-2048, including original model tests and real guest swipes:
./tests/ios/build-2048-model.sh # after building the app
build/ios/run-ios-host build/ios/2048/model-tests
./tests/ios/game2048
tests/ios/run --with-2048
./tests/ios/desktop --app 2048 --desktop build/vinix-desktop
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
