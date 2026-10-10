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
| Dynamic linking | Chained pointer formats `DYLD_CHAINED_PTR_64` and `DYLD_CHAINED_PTR_64_OFFSET`, import formats 1/2/3; legacy rebase/bind/lazy/weak streams, export-trie lookup, signed addends and tagged RTTI pointers; app-bundled dylibs with `@executable_path`, `@loader_path` and own/executable `@rpath` lookup, shared mappings for repeated dependencies; checked lazy function slots resolve on first call through register-preserving ARM64 thunks; built-in and already-linked library `dlopen`/`dlsym`/`dlerror`, image/section lookup |
| Image lifecycle | Superclass-first Objective-C `+load`, category attachment and category `+load` before C++ image constructors; checked `LC_ROUTINES_64`, initializer pointers/offsets, terminators and reverse-order image-scoped `atexit`/`__cxa_atexit`/`__cxa_finalize` callbacks; native `exit` and immediate `_exit` termination |
| Thread-local storage | Darwin TLV descriptors, independent initialized and zero-filled templates for each image, lazy per-thread allocation and pthread-key cleanup; register-preserving ARM64 thunk |
| C++ (optional) | `--with-cxx` builds LLVM libc++ with Apple ARM64 string, 128-byte `mbstate_t`, 32-bit ctype masks and eight-byte TLS keys; native strings and legacy growth/substring helpers, integer sorts, streams, regex, futures, shared/weak ownership and synchronization; V adapters for Darwin random_device and variadic abort |
| libSystem | Memory/string/conversion/math subset, repeated 4/8/16-byte pattern fills and 32-bit wide characters; Darwin 152-byte `FILE` objects over native libc streams; ARM64 printf/scanf/asprintf and `va_list` adapters; checked formatting/copies; CPU/page-size queries, clocks, calendar time, locale categories, stack guards and C/UTF-8 Unicode rune tables; translated open/mmap flags, positional reads/writes, shared-memory aliases, 144-byte stat records and native `utime` timestamps; version-4 UUIDs from native entropy; IPv4/IPv6 TCP, UDP and Unix sockets with Darwin addresses, options, flags and errors; pthread, `dispatch_once`, main/global/serial dispatch queues, delayed work and synchronous callbacks |
| Objective-C | Class/metaclass registration, superclass dispatch, checked absolute/relative method lists and type encodings, canonical selectors, method/ivar reflection, inherited method replacement and saved IMPs, dynamic class/ivar creation and disposal, checked `object_setClass`, nonfragile ivar adjustment, native methods, reentrant once-per-class `+initialize`, nil returns, allocation/new/class, caller-supplied instance construction and destruction, ARC ownership including 52 register-specific entry points, native `dealloc` and Objective-C++ ivar constructors/destructors, zeroing weak references and copied block properties |
| Foundation | UTF-8 and UTF-16 constant NSString, UTF-16 length, concatenation, integer/object formatting; NSNumber, NSData, file-reading NSFileHandle, main NSBundle, document paths, absolute file URLs with UTF-8 percent encoding, immutable binary/XML property lists; collections, fast enumeration, timers, synchronous notification observers, operation queue configuration and file-backed standard user defaults |
| CoreFoundation | Owned UTF-8/ASCII strings including embedded NUL, UTF-16 ranges and partial UTF-8/ASCII conversion, arrays/dictionaries with type or NULL callbacks, dictionary add-if-absent and raw null entries, exported immutable empty dictionary, mutable data with zero-filled growth, signed integer/floating numbers, distinct Boolean IDs, equality/hash and callback tables; default allocation and absolute time |
| UIKit | UIApplicationMain with its principal class/application/delegate objects, file launch options and scene URL contexts, single manifest window-scene connection, idle-timer state and native controller gesture/home-indicator preference callbacks, UIWindow, UIScreen, UIViewController presentation, nested UIView ownership/removal, UILabel, UIButton target/action, opaque UIColor, UIFont size, CALayer corner radius, single-touch swipe recognizers and simple alerts; accessibility labels/hints/values/identifiers, traits and absolute frames, UIAccessibilityElement with a weak container; scaled/nested per-thread image contexts, immutable UIImage snapshots, upright PNG/JPEG decode and representation |
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
App groups, custom preference suites and security-scoped bookmarks are unsupported.
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
python3 tests/ios/run.py --with-cxx --with-gles --with-2048
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
TLS reads from key destructors and C++ thread-local destructor ordering remain
unverified. The full ARM64 C++/GLES/PPSSPP regression passes; an earlier attempt
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

The actual Fortnite probe now resolves Void and exits with status 1 before
entry at EOSSDK's `__swift_stdlib_operatingSystemVersion` import. Evidence is
retained under `swift-void-checks`, including native measurements of that next
entry's indirect 24-byte return ABI. Full regression remains unpassed and the
five published runners retain their last passing hashes.

`run-ios --audit BINARY` now checks each bundled library's imports as well as
the executable, without mapping or executing app code. The static C++ runner reports:

| Image | Resolved | Unresolved strong | Unresolved weak |
| --- | ---: | ---: | ---: |
| Fortnite executable | 1,386 | 772 | 81 |
| EOSSDK | 597 | 65 | 18 |
| MarketplaceKitWrapper | 90 | 86 | 23 |
| All images | 2,073 | 923 | 122 |

The C++/GLES/Text variant reports 2,086 resolved imports, 910 unresolved strong
imports and 122 unresolved weak imports, including its native zlib/text backends.

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
v -nocache -cc clang run tests/ios/native-checks.v build
v -nocache -cc clang run tests/ios/native-checks.v regression
v -nocache -cc clang run tests/ios/native-checks.v swift
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

`swift` runs all fourteen Swift ABI checks in a small, independent guest and
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
python3 tests/ios/run.py --no-build --with-cxx --with-gles --with-2048 \
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
python3 tests/ios/run.py --no-build --with-cxx --with-gles --with-2048 \
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
python3 tests/ios/run.py --no-build --with-cxx --with-gles --with-2048 \
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
python3 tests/ios/run.py --no-build --with-cxx --with-gles --with-2048 \
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
