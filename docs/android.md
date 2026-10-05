# Android APKs on Vinix

Vinix's ARM64 desktop runs Android APKs with
[Android Translation Layer](https://gitlab.com/android_translation_layer/android_translation_layer)
and ART. ART executes the application's DEX bytecode; ATL implements Android
framework calls using native Linux libraries and GTK. The runtime, its helpers
and ARM64 JNI libraries execute directly on the ARM64 CPU. Java bytecode
interpretation is provided by ART with its JIT disabled.

Vinix uses 16 KiB memory pages. The standard Alpine ART package assumes 4 KiB,
so the builder requires a source-built ART overlay adapted for 16 KiB pages.
The APK native-library linker also needs matching 16 KiB page rounding.
The source-built ATL overlay supplies matching native helpers, framework DEX,
Android resources and fonts from one pinned upstream commit. The Alpine
package's framework is replaced as a unit so its Java and JNI APIs stay in sync.
It verifies the pinned source, checked-in patch, compiler flag and every output
file's hash, architecture and load-segment alignment before staging it. A
missing or incompatible overlay fails the build. ART's androidfw library and
ATL are patched together to expose real NDK configuration snapshots and
qualifiers; rebuild both overlays when their checked-in patches change.

First build ART on a native ARM64 Alpine Linux host. On an ARM64 Mac, an ARM64
Linux VM using hardware virtualization is suitable for building the runtime.
ART's build generates and executes native host tools, so a macOS cross compiler
alone cannot build it. Enable Alpine's `edge/main`, `edge/community` and
`edge/testing` repositories and install its ART build dependencies:

```sh
apk add --upgrade build-base bash python3 zip curl pkgconf patch \
  bionic_translation-dev bsd-compat-headers expat-dev icu-dev java-common \
  libbsd-dev libcap-dev libpng-dev libselinux-dev libunwind-dev lz4-dev meson \
  openjdk8-jdk openssl-dev valgrind-dev wolfssl-jni-dev xz-dev zlib-dev vixl-dev
ln -sf python3 /usr/bin/python
```

The pinned dependency ABI uses musl `1.2.6-r4`, GCC/libstdc++ `15.2.0-r9`,
ICU `78.1-r0` and VIXL `8.0.0-r0`. Match the package lock when rebuilding;
the build script and manifest record the exact source, patch, compiler and
dependency packages. `--dependency-cache DIR` records available package
archive checksums for reproducing that build:

```sh
build-support/android/build-art.sh --output /path/to/art-runtime
build-support/android/build-bionic.sh --output /path/to/bionic-runtime
```

Build ATL on the same native ARM64 Alpine host with its framework dependencies.
The build uses OpenJDK 8 for Java compilation and Java 17 or newer for the
checksum-pinned D8 compiler:

```sh
apk add alsa-lib-dev android-build-tools art_standalone-dev libandroidfw-dev \
  gtk4.0-dev libgudev-dev libsecret-dev libdrm-dev libportal-dev \
  ffmpeg-dev mesa-dev openxr-dev sqlite-dev vulkan-loader-dev \
  wayland-dev wayland-protocols webkit2gtk-6.0-dev openjdk17-jre-headless
PATH=/usr/lib/jvm/java-8-openjdk/bin:$PATH \
  build-support/android/build-atl.sh --output /path/to/atl-runtime \
  --art-runtime /path/to/art-runtime --java /usr/lib/jvm/java-17-openjdk/bin/java
```

Copy all three resulting directories to the build host. Desugar ART's own Java
boot libraries using the pinned D8 compiler; this removes unresolved Java
lambda bootstrap calls while retaining the classes and resources. Application
APKs remain unchanged. This host step requires Java 17 or newer. Then stage
the native runtime and optional calculator APK. The staging host also needs
Python 3, curl and `aarch64-linux-musl-gcc`:

```sh
python3 build-support/android/art-bootclasspath.py \
  --build-dir build-aarch64-android/aarch64/java-build --art-runtime /path/to/art-runtime
./scripts/build-android-aarch64.sh --art-runtime /path/to/art-runtime \
  --bionic-runtime /path/to/bionic-runtime --atl-runtime /path/to/atl-runtime \
  --with-calculator
./scripts/build-desktop-aarch64.sh --compact-initramfs --with-android
./scripts/run-desktop-aarch64.sh --no-build --mem=12288
```

The default ART overlay location is
`build-aarch64-android/aarch64/art-runtime`; the native-library linker defaults
to `build-aarch64-android/aarch64/bionic-runtime`, and ATL defaults to
`build-aarch64-android/aarch64/atl-runtime`. `VINIX_ANDROID_ART_RUNTIME`,
`VINIX_ANDROID_BIONIC_RUNTIME` and `VINIX_ANDROID_ATL_RUNTIME` override those
locations. The runtime builder installs the
checksum-pinned Alpine ARM64 dependency closure and patched ART under
`/opt/vinix-android-aarch64`. Its musl loader, GTK and libraries remain private
to APK processes. It installs no CPU translator. `packages.lock.json`,
`runtime-manifest.json`, `art-runtime-manifest.json`,
`bionic-runtime-manifest.json` and `atl-runtime-manifest.json` preserve provenance.
`--update-lock` explicitly regenerates the Alpine package selection.

The private libc is rebuilt from checksum-pinned musl 1.2.6 with the recorded
Alpine patches, heap retention and Android allocation accounting. Its build
must preserve the packaged libc's exports and use 16 KiB-compatible ELF
segments. `usr/share/vinix/musl-build.json` records its source, patch and payload
hashes; Android, Roblox and desktop staging verify that receipt.

Android's 80-byte ARM64 `mallinfo` reports actual live payload bytes, reusable
slot capacity, anonymous allocation-group mappings and peak mapped bytes.
Allocator metadata arenas are excluded. This private allocator leaves unused
ELF image-page space with its image so borrowed library backing cannot distort
heap statistics. Counters and allocation state share musl's fork lock. The
ordinary desktop allocator keeps its existing behavior.

Open **Android Calculator** from Start or Quick Launch. The sample is the
developer's unchanged Arity 1.1 APK, extracted from its
[official source archive](https://code.google.com/archive/p/arity-calculator/).
The archive and APK are verified against recorded SHA256 hashes. Click the
input field above the history list before typing; this version uses keyboard
input.

On an existing X11 display, including a session started with `startx`, launch
another APK with:

```sh
run-android /root/example.apk
run-android /root/example.apk -l com/example/MainActivity -w 480 -h 640
```

`-l` selects an activity using slash-separated names. Other arguments are
passed to ATL. App data is stored under `$XDG_DATA_HOME/vinix/android`, normally
`$HOME/.local/share/vinix/android`. `ANDROID_APP_DATA_DIR` selects another root.
The launcher supplies a finite 32 MiB stack limit; `VINIX_ANDROID_STACK_KB`
overrides it. The compatibility library reports the usable initial stack
within both Vinix's mapped reservation and that limit. Worker stack metadata
remains supplied by musl. ARM ART uses its own low-address allocator for
compressed object references.

The private compatibility library also implements Android's DSO-associated
fork callbacks through real host callbacks. It preserves their order with
ART's callbacks and removes them when the Android library finalizes. Since
musl cannot unregister a host callback, the process retains an inert thunk
after finalization. The table supports 128 successful Android registrations
per process; further registrations return `ENOMEM`. Registering or finalizing
handlers from inside a running fork callback is unsupported.

Compatibility follows ATL's implemented Android API subset. APKs containing
native libraries need `arm64-v8a` libraries. Pure Java/DEX APKs do not require
an architecture-specific native payload. Modern Android APIs, services and
resource qualifiers can require additional ATL implementation; the presence
of an APK launcher does not establish compatibility with every application.
The unchanged Roblox 2.738.1397 APK initializes its content providers and
completes the ARM64 engine's `JNI_OnLoad` through native ATL/ART. The coherent
framework, fork callbacks, real NDK configuration API, fortified I/O wrappers
and private allocator statistics resolve its earlier missing native imports.
Android resolver flags and EAI errors are translated at the Bionic boundary;
its native loader permits recursive constructor loads and retains the DSO
through callbacks. The launcher selects the private JKS trust store for Java
HTTPS. Native Vinix fixtures verify real public HTTPS and rejection of an
untrusted local certificate. XML `<requestFocus />` tags are consumed during
inflation and restore focus once children attach, respecting hidden views. The latest client launch then
aborts on the missing `View.OnCapturedPointerListener` API. A usable Roblox
screen, authentication and gameplay remain unverified. The [Roblox desktop entry](roblox.md) uses this
same native ATL/ART runtime.

Run the real guest test after building the runtime, desktop and kernel:

```sh
python3 tests/android/launcher-test.py
python3 tests/android/art-runtime-test.py
python3 tests/android/bootclasspath-test.py
python3 tests/android/musl-runtime-test.py
python3 tests/android/run.py --memory 12288
```

The guest test opens the unchanged calculator APK in the Vinix desktop,
checks native stack and memory prerequisites, types `123+456` through the
guest keyboard, verifies that the APK draws `579`, and captures the actual
framebuffer. Its test-only text observer does not calculate the result or
modify the APK. Logs and screenshots are retained in `build/android-smoke`.
The native runtime passed this test on 3 October 2026 in both the minimal
test image and the built compact desktop image with 12 GiB RAM: the unchanged
APK displayed `579` with zero key retries. The Java boot probe also passed
date parsing, UTC formatting and stream ordering against the desugared boot
libraries. These results cover that APK and those Java platform calls.
`--observe --apk /path/to/app.apk` captures another APK's real window and logs
without claiming a functional pass. See [the harness instructions](../tests/android/README.md).
