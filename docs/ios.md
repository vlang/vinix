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
| Entry point | `LC_MAIN`, `argc`/`argv`, empty null-terminated environment and Apple vectors, integer exit status |
| Dynamic linking | Chained pointer formats `DYLD_CHAINED_PTR_64` and `DYLD_CHAINED_PTR_64_OFFSET`, import formats 1/2/3; legacy rebase/bind/lazy/weak streams, export-trie lookup, signed addends and tagged RTTI pointers; app-bundled dylibs with `@executable_path`, `@loader_path` and own/executable `@rpath` lookup, shared mappings for repeated dependencies; checked lazy function slots resolve on first call through register-preserving ARM64 thunks; built-in and already-linked library `dlopen`/`dlsym`/`dlerror`, image/section lookup |
| Image lifecycle | Superclass-first Objective-C `+load`, category attachment and category `+load` before C++ image constructors; checked `LC_ROUTINES_64`, initializer pointers/offsets, terminators and reverse-order `__cxa_atexit`/`__cxa_finalize` callbacks |
| Thread-local storage | Darwin TLV descriptors, independent initialized and zero-filled templates for each image, lazy per-thread allocation and pthread-key cleanup; register-preserving ARM64 thunk |
| C++ (optional) | `--with-cxx` builds LLVM libc++ with Apple ARM64 string, 128-byte `mbstate_t`, 32-bit ctype masks and eight-byte TLS keys; native strings and legacy growth/substring helpers, integer sorts, streams, regex, futures, shared/weak ownership and synchronization; V adapters for Darwin random_device and variadic abort |
| libSystem | Memory/string/conversion/math subset, repeated 4/8/16-byte pattern fills and 32-bit wide characters; Darwin 152-byte `FILE` objects over native libc streams; ARM64 printf/scanf/asprintf and `va_list` adapters; checked formatting/copies; CPU/page-size queries, clocks, calendar time, locale categories, stack guards and ASCII rune tables; translated open/mmap flags, positional reads/writes, shared-memory aliases and 144-byte stat records; pthread and `dispatch_once` adapters |
| Objective-C | Class/metaclass registration, superclass dispatch, checked absolute/relative method lists and type encodings, canonical selectors, method/ivar reflection, inherited method replacement and saved IMPs, dynamic class/ivar creation and disposal, checked `object_setClass`, nonfragile ivar adjustment, native methods, reentrant once-per-class `+initialize`, nil returns, allocation/new/class, ARC ownership including 52 register-specific entry points, native `dealloc` and Objective-C++ ivar constructors/destructors, zeroing weak references and copied block properties |
| Foundation | UTF-8 and UTF-16 constant NSString, UTF-16 length, concatenation, integer/object formatting; NSNumber, NSData, file-reading NSFileHandle, main NSBundle, document paths, absolute file URLs with UTF-8 percent encoding, immutable binary/XML property lists; collections, fast enumeration, timers, synchronous notification observers, operation queue configuration and file-backed standard user defaults |
| CoreFoundation | Owned UTF-8/ASCII strings including embedded NUL, UTF-16 ranges and partial UTF-8/ASCII conversion, arrays/dictionaries with type or NULL callbacks, mutable data with zero-filled growth, signed integer/floating numbers, distinct Boolean IDs, equality/hash and callback tables; default allocation and absolute time |
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
per page are rejected. Objective-C exceptions and Swift metadata are unsupported.
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
iOS: linking /opt/ios/Frameworks/EOSSDK.framework/EOSSDK: iOS: libSystem symbol is not implemented: _accept
```

`run-ios --audit BINARY` now checks each bundled library's imports as well as
the executable, without mapping or executing app code. The static C++ runner reports:

| Image | Resolved | Unresolved strong | Unresolved weak |
| --- | ---: | ---: | ---: |
| Fortnite executable | 1,233 | 925 | 81 |
| EOSSDK | 446 | 216 | 18 |
| MarketplaceKitWrapper | 52 | 124 | 23 |
| All images | 1,731 | 1,265 | 122 |

The C++/GLES/Text variant reports 1,744 resolved imports, 1,252 unresolved strong
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

`sh tests/ios/reference-frameworks.sh` builds and runs the reference fixtures on
a Mac with Catalyst libraries. `python3 tests/ios/run.py --with-cxx` checks the
same fixtures in Vinix, import auditing, native iOS tagged pointers through
both chained and legacy relocation, and the existing UIKit, TLS and C++
regressions. The proprietary IPA and its extracted bytes are not committed.

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
python3 tests/ios/frame.py build/ios/ppsspp-guest.log build/ios/ppsspp-settings.png
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
python3 tests/ios/frame.py build/ios/ppsspp-cube-guest.log build/ios/ppsspp-cube.png
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
python3 tests/ios/frame.py build/ios/ppsspp-nzp-guest.log build/ios/ppsspp-nzp-before.png --frame 0
python3 tests/ios/frame.py build/ios/ppsspp-nzp-guest.log build/ios/ppsspp-nzp.png
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
python3 tests/ios/frame.py build/ios/ppsspp-gow-guest.log build/ios/ppsspp-gow.png
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
