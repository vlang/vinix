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

`run-ios --audit BINARY` now checks each bundled library's imports as well as
the executable, without mapping or executing app code. The static C++ runner reports:

| Image | Resolved | Unresolved strong | Unresolved weak |
| --- | ---: | ---: | ---: |
| Fortnite executable | 1,483 | 677 | 79 |
| EOSSDK | 659 | 3 | 18 |
| MarketplaceKitWrapper | 176 | 0 | 23 |
| All images | 2,318 | 680 | 120 |

The C++/GLES/Text variant reports 2,331 resolved imports, 667 unresolved strong
imports and 120 unresolved weak imports, including its native zlib/text backends.

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
