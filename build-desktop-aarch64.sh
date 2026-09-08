#!/bin/bash
# Cross-compile the Vinix desktop environment for aarch64 and stage it into an
# initramfs that boots straight into it.
#
# Usage: ./build-desktop-aarch64.sh [--no-initramfs] [--compact-initramfs] [--wifi-bundle=DIR]
#
# V translates the program to C; clang compiles that C against the static musl
# sysroot extracted from the userland image. The result is a freestanding
# static binary. The bootable desktop image is the full userland with that
# binary and its desktop init overlaid, so opening a terminal exposes the same
# preinstalled commands as booting the userland directly.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/build-support/find-v.sh"

BUILD_DIR="$SCRIPT_DIR/build"
SYSROOT="$SCRIPT_DIR/build-aarch64-musl/aarch64-linux-musl-native"
GCCLIB="$SYSROOT/lib/gcc/aarch64-linux-musl/11.2.1"
LLVM_BIN="/opt/homebrew/opt/llvm/bin"
# <stdatomic.h> has to be ours. See build-support/aarch64-cc-shim/stdatomic.h:
# -nostdinc leaves GCC 11's on the path, whose atomics clang rejects on the
# _Atomic pointers V generates, and clang's own header forwards straight back
# to it. This only started to matter when the desktop began importing os and
# time, which pull in sync.stdatomic.
CC_SHIM="$SCRIPT_DIR/build-support/aarch64-cc-shim"
BASE_INITRAMFS="$SCRIPT_DIR/build-support/init-aarch64/initramfs.tar"
DESKTOP_INITRAMFS="$SCRIPT_DIR/build-support/init-aarch64/initramfs-desktop.tar"
PYTHON_STAGING="${VINIX_PYTHON_STAGING:-$SCRIPT_DIR/build-aarch64-python/staging}"
NETWORK_TOOLS_STAGING="${VINIX_NETWORK_TOOLS_STAGING:-$SCRIPT_DIR/build-aarch64-network-tools/staging}"
X11_STAGING="${VINIX_X11_STAGING:-$SCRIPT_DIR/build-aarch64-x11/staging}"
FIREFOX_STAGING="${VINIX_FIREFOX_STAGING:-$SCRIPT_DIR/build-aarch64-firefox/staging}"
MINECRAFT_STAGING="${VINIX_MINECRAFT_STAGING:-$SCRIPT_DIR/build-aarch64-minecraft/staging}"
ASAHI_STAGING="${VINIX_ASAHI_STAGING:-$SCRIPT_DIR/build-aarch64-asahi/staging}"
HYPRLAND_STAGING="${VINIX_HYPRLAND_STAGING:-$SCRIPT_DIR/build-aarch64-hyprland/staging}"
GPU_SYSROOT="${VINIX_GPU_SYSROOT:-$SCRIPT_DIR/build-aarch64-x11/sysroot}"

merge_staging_tree() {
    local overlay="$1"
    local source relative destination

    # macOS cp follows an existing destination symlink. The Python and network
    # closures share a few libraries, so remove a destination link before the
    # later overlay replaces it instead of overwriting its target.
    while IFS= read -r -d '' source; do
        relative="${source#"$overlay/"}"
        destination="$STAGING/$relative"
        if [ -L "$destination" ]; then
            rm -f "$destination"
        fi
    done < <(find "$overlay" -mindepth 1 -print0)

    cp -a "$overlay/." "$STAGING/"
}

MAKE_INITRAMFS=1
COMPACT_INITRAMFS=0
WIFI_BUNDLE="${VINIX_WIFI_BUNDLE:-}"
for arg in "$@"; do
    case "$arg" in
        --no-initramfs) MAKE_INITRAMFS=0 ;;
        --compact-initramfs) COMPACT_INITRAMFS=1 ;;
        --wifi-bundle=*) WIFI_BUNDLE="${arg#*=}" ;;
        --help|-h)
            echo "usage: $0 [--no-initramfs] [--compact-initramfs] [--wifi-bundle=DIR]"
            echo "  --compact-initramfs stages the desktop, core developer tools and Firefox"
            echo "  --wifi-bundle stages a package.py output and loads it before the desktop"
            exit 0
            ;;
        *)
            echo "ERROR: unknown option: $arg" >&2
            exit 1
            ;;
    esac
done

if [ "$MAKE_INITRAMFS" -eq 0 ] && [ -n "$WIFI_BUNDLE" ]; then
    echo "ERROR: --wifi-bundle requires initramfs generation" >&2
    exit 1
fi

if [ -n "$WIFI_BUNDLE" ]; then
    for name in manifest.bin firmware.bin nvram.txt clm.blob txcap.blob; do
        if [ ! -f "$WIFI_BUNDLE/$name" ]; then
            echo "ERROR: Wi-Fi bundle is missing $WIFI_BUNDLE/$name" >&2
            exit 1
        fi
    done
fi

# ── The musl sysroot ──
# The aarch64 userland image carries a complete native musl toolchain; its
# headers and libraries are all a cross build needs, so they are unpacked here
# instead of rebuilding musl from source.
if [ ! -f "$SYSROOT/lib/libc.a" ]; then
    if [ ! -f "$BASE_INITRAMFS" ]; then
        echo "ERROR: $BASE_INITRAMFS not found."
        echo "Run ./build-userland-aarch64.sh first, or link the one from the main checkout."
        exit 1
    fi
    echo "==> Extracting the musl sysroot from the userland image..."
    mkdir -p "$SCRIPT_DIR/build-aarch64-musl"
    tar xf "$BASE_INITRAMFS" -C "$SCRIPT_DIR/build-aarch64-musl" \
        ./aarch64-linux-musl-native/include ./aarch64-linux-musl-native/lib
fi

# ── ui2 ──
# The desktop is built on ui2's declarative element tree. It is not vendored;
# check it out beside the sources and point V's module path at it.
if [ ! -f "$SCRIPT_DIR/third_party/ui2/v.mod" ]; then
    echo "ERROR: ui2 not found at third_party/ui2. Clone it there:"
    echo "    git clone https://github.com/vlang/ui2 third_party/ui2"
    exit 1
fi

# Native app processes use QmlApp to build declarative trees for the compositor.
# A checkout without it fails deep inside the V build with an error about an
# unknown type, which says nothing about the real problem.
if [ ! -f "$SCRIPT_DIR/third_party/ui2/ui/qml_embed.v" ]; then
    echo "ERROR: this ui2 checkout has no QmlApp (ui/qml_embed.v)."
    echo "The desktop hosts ui2 applications through it. Update the checkout:"
    echo "    git -C third_party/ui2 pull"
    exit 1
fi

if [ ! -x "$LLVM_BIN/clang" ]; then
    echo "ERROR: Homebrew LLVM not found at $LLVM_BIN (brew install llvm)"
    exit 1
fi

mkdir -p "$BUILD_DIR"

# ── Stage the sources ──
# Native ui2 applications exec this multicall binary under per-app names, and
# an application's model is V code that has to be compiled in. The staging
# step takes each example's source straight from the ui2 checkout — everything
# but its `fn main()`, which only opens a platform window — so what runs is the
# example itself.
echo "==> Staging sources..."
APP_SRC="$BUILD_DIR/app-src"
python3 "$SCRIPT_DIR/desktop/tools/stage_app.py" "$APP_SRC" "$SCRIPT_DIR/desktop" \
    "$SCRIPT_DIR/third_party/ui2/examples/calculator"

# Build the test application as a normal Apple AArch64 Mach-O. A macOS host
# records standard Cocoa dylib imports; ld64.lld records flat imports elsewhere.
# The Vinix image contains no Apple framework binaries: its V runtime resolves
# the narrow AppKit/Objective-C surface used by this application.
echo "==> Building Cocoa compatibility fixture..."
"$SCRIPT_DIR/compat/macos/apps/Calculator/build.sh" "$BUILD_DIR/Calculator.app"

# ── V -> C ──
# -gc none because Vinix has no Boehm GC, and -d ui2_headless so importing ui2
# brings in its declarative core without its gg/Sokol backend.
echo "==> Translating V to C..."
# The build stamp the taskbar shows beside the clock. Deploying to real
# hardware and rebooting looks the same whether the new image landed or not,
# so the desktop says when it was built.
BUILD_STAMP="${VINIX_BUILD_STAMP:-$(date '+%m-%d %H:%M')}"
echo "    build stamp: $BUILD_STAMP"
"$V" -os linux -gc none -manualfree -enable-globals -prod \
    -d ui2_headless \
    -d "vinix_build_stamp=$BUILD_STAMP" \
    -path "@vlib|@vmodules|$SCRIPT_DIR|$SCRIPT_DIR/third_party" \
    -o "$BUILD_DIR/desktop.c" "$APP_SRC"

# ── C -> aarch64 static binary ──
echo "==> Compiling for aarch64-linux-musl..."
"$LLVM_BIN/clang" --target=aarch64-linux-musl -static -nostdinc -nostdlib \
    -isystem "$CC_SHIM" \
    -isystem "$GCCLIB/include" -isystem "$SYSROOT/include" \
    -I "$APP_SRC" \
    -O2 -fno-stack-protector -w \
    "$SYSROOT/lib/crt1.o" "$SYSROOT/lib/crti.o" "$GCCLIB/crtbegin.o" \
    "$BUILD_DIR/desktop.c" \
    -L"$SYSROOT/lib" -L"$GCCLIB" -lc -lgcc -lm \
    "$GCCLIB/crtend.o" "$SYSROOT/lib/crtn.o" \
    -fuse-ld=lld -B"$LLVM_BIN" \
    -o "$BUILD_DIR/vinix-desktop"

"$LLVM_BIN/llvm-strip" "$BUILD_DIR/vinix-desktop"
echo "    $BUILD_DIR/vinix-desktop ($(stat -f%z "$BUILD_DIR/vinix-desktop") bytes)"

# Mesa is a dynamic runtime, so keep the always-bootable static desktop and
# build a second executable only when the exact Asahi userspace is available.
# desktop-init selects this executable when the M1 render node exists. The UI
# is still rasterized into its Canvas on the CPU; EGL/GLES moves scaling and
# presentation to AGX before the unavoidable firmware-framebuffer readback.
GPU_DESKTOP_BUILT=0
if [ -f "$ASAHI_STAGING/usr/lib/libEGL.so" ] &&
   [ -f "$ASAHI_STAGING/usr/lib/libGLESv2.so" ] &&
   [ -f "$ASAHI_STAGING/usr/include/EGL/egl.h" ] &&
   [ -f "$GPU_SYSROOT/usr/lib/Scrt1.o" ]; then
    echo "==> Translating the GPU-enabled desktop to C..."
    "$V" -os linux -gc none -manualfree -enable-globals -prod \
        -d ui2_headless -d vinix_gpu_present \
        -d "vinix_build_stamp=$BUILD_STAMP" \
        -path "@vlib|@vmodules|$SCRIPT_DIR|$SCRIPT_DIR/third_party" \
        -o "$BUILD_DIR/desktop-gpu.c" "$APP_SRC"

    echo "==> Compiling the GPU-enabled desktop for aarch64-linux-musl..."
    "$LLVM_BIN/clang" --target=aarch64-linux-musl \
        --sysroot="$GPU_SYSROOT" --gcc-toolchain="$SYSROOT" -static-libgcc \
        -isystem "$CC_SHIM" \
        -I "$APP_SRC" -I "$ASAHI_STAGING/usr/include" \
        -O2 -fPIE -pie -fno-stack-protector -w \
        "$BUILD_DIR/desktop-gpu.c" "$SCRIPT_DIR/desktop/gpu_present_egl.c" \
        -L"$ASAHI_STAGING/usr/lib" \
        -Wl,-rpath-link,"$ASAHI_STAGING/usr/lib" \
        -Wl,-dynamic-linker,/lib/ld-musl-aarch64.so.1 \
        -lEGL -lGLESv2 -ldl -lpthread -lm \
        -fuse-ld=lld -B"$LLVM_BIN" \
        -o "$BUILD_DIR/vinix-desktop-gpu"
    "$LLVM_BIN/llvm-strip" "$BUILD_DIR/vinix-desktop-gpu"
    echo "    $BUILD_DIR/vinix-desktop-gpu ($(stat -f%z "$BUILD_DIR/vinix-desktop-gpu") bytes)"
    GPU_DESKTOP_BUILT=1
    if [ ! -f "$ASAHI_STAGING/usr/share/vinix/mesa-x11-egl" ] &&
       [ ! -f "$ASAHI_STAGING/usr/share/vinix/asahi-x11-egl" ]; then
        echo "    NOTE: this Mesa staging predates X11/GBM support; rebuild it for Firefox acceleration"
    fi
else
    echo "==> Asahi EGL staging not found; keeping the static software desktop only"
fi

if [ "$MAKE_INITRAMFS" -eq 0 ]; then
    exit 0
fi

# ── Stage an initramfs that boots into the desktop ──
# Appending an overlay tar would leave duplicate paths that the kernel's
# initramfs unpacker rejects, so stage before repacking it. A full userland is
# useful for development but can exceed an M1 EFI partition. Compact mode keeps
# the native GCC toolchain plus the packaged Python, network-tool and Firefox
# closures, while leaving out unrelated large runtimes.
if [ ! -f "$BASE_INITRAMFS" ]; then
    echo "ERROR: $BASE_INITRAMFS not found; it is the desktop's base userland."
    exit 1
fi
if [ ! -x "$X11_STAGING/usr/bin/vinix-xinput" ]; then
    echo "ERROR: desktop needs $X11_STAGING/usr/bin/vinix-xinput" >&2
    echo "Run ./build-x11-aarch64.sh first." >&2
    exit 1
fi
if [ ! -x "$NETWORK_TOOLS_STAGING/usr/bin/pkg" ] ||
   [ ! -x "$NETWORK_TOOLS_STAGING/sbin/apk" ] ||
   [ ! -s "$NETWORK_TOOLS_STAGING/etc/vinix-pkg/base-world" ]; then
    echo "ERROR: desktop needs the package layer in $NETWORK_TOOLS_STAGING" >&2
    echo "Run ./build-network-tools-aarch64.sh first." >&2
    exit 1
fi
if [ "$COMPACT_INITRAMFS" -eq 1 ]; then
    if [ ! -x "$PYTHON_STAGING/usr/bin/python3" ]; then
        echo "ERROR: compact desktop needs $PYTHON_STAGING/usr/bin/python3" >&2
        echo "Run ./build-python-aarch64.sh first." >&2
        exit 1
    fi
    if [ ! -x "$NETWORK_TOOLS_STAGING/usr/bin/git" ]; then
        echo "ERROR: compact desktop needs $NETWORK_TOOLS_STAGING/usr/bin/git" >&2
        echo "Run ./build-network-tools-aarch64.sh first." >&2
        exit 1
    fi
    if [ ! -x "$FIREFOX_STAGING/usr/bin/run-firefox" ]; then
        echo "ERROR: compact desktop needs $FIREFOX_STAGING/usr/bin/run-firefox" >&2
        echo "Run ./build-x11-aarch64.sh and ./build-firefox-aarch64.sh first." >&2
        exit 1
    fi
    if [ ! -x "$X11_STAGING/usr/bin/Xorg" ] ||
        [ ! -x "$X11_STAGING/usr/bin/startx" ] ||
        [ ! -x "$X11_STAGING/usr/bin/vinix-xinput" ]; then
        echo "ERROR: compact desktop needs Xorg, startx and vinix-xinput in $X11_STAGING" >&2
        echo "Run ./build-x11-aarch64.sh first." >&2
        exit 1
    fi
fi

# `package.py` produces the only supported bundle format. Its manifest binds
# the opaque vendor files to identity captured from the target, and wifi-ctl
# repeats that identity check on the M1 before uploading a byte.
echo "==> Building wifi-ctl for aarch64-linux-musl..."
"$LLVM_BIN/clang" --target=aarch64-linux-musl -static -nostdinc -nostdlib \
    -isystem "$CC_SHIM" \
    -isystem "$GCCLIB/include" -isystem "$SYSROOT/include" \
    -iquote "$SCRIPT_DIR/kernel/c" \
    -std=c11 -O2 -fno-stack-protector -Wall -Wextra -Werror \
    "$SYSROOT/lib/crt1.o" "$SYSROOT/lib/crti.o" "$GCCLIB/crtbegin.o" \
    "$SCRIPT_DIR/tools/m1-wifi/wifi-ctl.c" \
    -L"$SYSROOT/lib" -L"$GCCLIB" -lc -lgcc \
    "$GCCLIB/crtend.o" "$SYSROOT/lib/crtn.o" \
    -fuse-ld=lld -B"$LLVM_BIN" \
    -o "$BUILD_DIR/wifi-ctl"
"$LLVM_BIN/llvm-strip" "$BUILD_DIR/wifi-ctl"
echo "    $BUILD_DIR/wifi-ctl ($(stat -f%z "$BUILD_DIR/wifi-ctl") bytes)"

echo "==> Building the desktop init..."
INIT_DEFINES=()
if [ -n "$WIFI_BUNDLE" ]; then
    INIT_DEFINES=(-DVINIX_WIFI_BUNDLE=1)
fi
"$LLVM_BIN/clang" --target=aarch64-linux-none -nostdlib -ffreestanding -O2 -c \
    "${INIT_DEFINES[@]}" \
    -o "$BUILD_DIR/desktop-init.o" \
    "$SCRIPT_DIR/build-support/init-aarch64/desktop-init.c"
# lld is installed as a separate formula, so it is on PATH rather than in
# the llvm keg the other tools come from.
"${LD_LLD:-ld.lld}" -m aarch64elf --nostdlib -static \
    -o "$BUILD_DIR/desktop-init" "$BUILD_DIR/desktop-init.o"

echo "==> Staging the desktop initramfs..."
STAGING="$BUILD_DIR/initramfs-root"
rm -rf "$STAGING"
mkdir -p "$STAGING"
if [ "$COMPACT_INITRAMFS" -eq 1 ]; then
    echo "    compact image: staging BusyBox, Python, Git, GCC and Firefox"
    tar xf "$BASE_INITRAMFS" -C "$STAGING" \
        ./bin/busybox ./aarch64-linux-musl-native
    merge_staging_tree "$X11_STAGING"
    merge_staging_tree "$FIREFOX_STAGING"
    merge_staging_tree "$NETWORK_TOOLS_STAGING"
    merge_staging_tree "$PYTHON_STAGING"

    # Scripts in the Firefox/X11/package closure use ordinary command names. The
    # compact image carries BusyBox but not the full userland's applet links,
    # so provide the small set needed by pkg, run-firefox and Vinix's startx.
    for applet in sh cat chmod dirname id ln mkdir rm sed sleep; do
        ln -sf busybox "$STAGING/bin/$applet"
    done
    # This stripped toolchain intentionally carries static libc and libgcc.
    # Its stock driver still prefers libgcc_s for an ordinary link, so wrap it
    # with the matching static-libgcc default. Callers can otherwise use GCC as
    # normal, and `cc` already resolves through the gcc symlink.
    mv "$STAGING/aarch64-linux-musl-native/bin/gcc" \
        "$STAGING/aarch64-linux-musl-native/bin/gcc.bin"
    printf '%s\n' '#!/bin/busybox sh' \
        'exec /aarch64-linux-musl-native/bin/gcc.bin -static-libgcc "$@"' \
        > "$STAGING/aarch64-linux-musl-native/bin/gcc"
    chmod +x "$STAGING/aarch64-linux-musl-native/bin/gcc"
else
    tar xf "$BASE_INITRAMFS" -C "$STAGING"
    # The base archive may predate package support. Always refresh this small
    # layer so the terminal gets pkg/apk without rebuilding the full userland.
    merge_staging_tree "$NETWORK_TOOLS_STAGING"
fi

# Keep the game optional like Firefox, but pick up a newly built layer even
# when the base userland archive predates it.
if [ -x "$MINECRAFT_STAGING/usr/bin/minecraft" ]; then
    echo "==> Staging C++ Minecraft runtime"
    merge_staging_tree "$MINECRAFT_STAGING"
fi

# Hyprland is an optional build layer because its patched Aquamarine library
# is produced in the native ARM64 build VM. When present, desktop-init starts
# it first and retains the native Vinix desktop as a recovery fallback.
if [ -x "$HYPRLAND_STAGING/usr/bin/start-hyprland-vinix" ]; then
    echo "==> Staging Hyprland and the Vinix Aquamarine backend"
    merge_staging_tree "$HYPRLAND_STAGING"
fi

# Overlay Mesa last so Xorg, Firefox and native EGL applications all use the
# exact userspace built for Vinix's Asahi kernel UAPI rather than Alpine's
# unrelated Mesa build.
if [ "$GPU_DESKTOP_BUILT" -eq 1 ]; then
    merge_staging_tree "$ASAHI_STAGING"
fi
# Hyprland edge uses libstdc++ formatting entry points newer than the base and
# Mesa 25 layers. Keep its backward-compatible C++ runtime as the final copy;
# use regular files because Vinix's musl loader opens DT_NEEDED objects with
# O_NOFOLLOW.
if [ -x "$HYPRLAND_STAGING/usr/bin/start-hyprland-vinix" ]; then
    for runtime in libstdc++.so.6 libgcc_s.so.1; do
        if [ -f "$HYPRLAND_STAGING/usr/lib/$runtime" ]; then
            rm -f "$STAGING/usr/lib/$runtime"
            cp -L "$HYPRLAND_STAGING/usr/lib/$runtime" "$STAGING/usr/lib/$runtime"
        fi
    done
fi
mkdir -p "$STAGING/sbin" "$STAGING/usr/bin" "$STAGING/usr/share/vinix" \
    "$STAGING/root" "$STAGING/dev" "$STAGING/proc" "$STAGING/sys" "$STAGING/tmp"
chmod 1777 "$STAGING/tmp"

# Keep the display handoff pieces in sync with the desktop source even when the
# full base userland predates them. The bridge is a cross-compiled executable;
# package/Firefox launchers and policy files can be installed directly from
# source.
install -m755 "$SCRIPT_DIR/build-support/vinix-pkg" "$STAGING/usr/bin/pkg"
install -m755 "$SCRIPT_DIR/build-support/xorg-server/startx" "$STAGING/usr/bin/startx"
install -m755 "$X11_STAGING/usr/bin/vinix-xinput" "$STAGING/usr/bin/vinix-xinput"
install -m755 "$SCRIPT_DIR/build-support/firefox/run-firefox" "$STAGING/usr/bin/run-firefox"
install -m644 "$SCRIPT_DIR/tests/firefox/smoke.html" "$STAGING/root/firefox-smoke.html"
mkdir -p "$STAGING/etc/firefox/policies"
install -m644 "$SCRIPT_DIR/build-support/firefox/policies.json" \
    "$STAGING/etc/firefox/policies/policies.json"

firefox_app_found=0
for firefox_app_dir in "$STAGING/usr/lib/firefox" "$STAGING/usr/lib/firefox-esr"; do
    if [ -d "$firefox_app_dir" ]; then
        firefox_app_found=1
        mkdir -p "$firefox_app_dir/defaults/pref" "$firefox_app_dir/distribution"
        install -m644 "$SCRIPT_DIR/build-support/firefox/vinix.js" \
            "$firefox_app_dir/defaults/pref/vinix.js"
        install -m644 "$SCRIPT_DIR/build-support/firefox/policies.json" \
            "$firefox_app_dir/distribution/policies.json"
    fi
done

if [ ! -x "$STAGING/bin/busybox" ]; then
    echo "ERROR: base userland has no executable /bin/busybox" >&2
    exit 1
fi
if [ ! -x "$STAGING/usr/bin/pkg" ] || [ ! -x "$STAGING/sbin/apk" ]; then
    echo "ERROR: desktop image is missing pkg or apk" >&2
    exit 1
fi
for runtime_path in usr/bin/Xorg usr/bin/startx usr/bin/vinix-xinput usr/bin/run-firefox; do
    if [ ! -x "$STAGING/$runtime_path" ]; then
        echo "ERROR: desktop Firefox runtime is missing /$runtime_path" >&2
        echo "Run ./build-x11-aarch64.sh and ./build-firefox-aarch64.sh, then rebuild the userland." >&2
        exit 1
    fi
done
if [ "$firefox_app_found" -ne 1 ]; then
    echo "ERROR: desktop image has no Firefox application directory" >&2
    echo "Run ./build-firefox-aarch64.sh and ./build-userland-aarch64.sh first." >&2
    exit 1
fi
if ! { [ -x "$STAGING/usr/lib/firefox-esr/firefox-esr" ] &&
       [ -x "$STAGING/usr/bin/firefox-esr" ]; } &&
   ! { [ -x "$STAGING/usr/lib/firefox/firefox" ] &&
       [ -x "$STAGING/usr/bin/firefox" ]; }; then
    echo "ERROR: desktop image has no complete Firefox executable pair" >&2
    echo "Run ./build-firefox-aarch64.sh and ./build-userland-aarch64.sh first." >&2
    exit 1
fi
if [ "$COMPACT_INITRAMFS" -eq 1 ]; then
    for command_path in bin/sh bin/id bin/sed bin/mkdir bin/sleep usr/bin/pkg sbin/apk usr/bin/python3 usr/bin/git usr/bin/Xorg usr/bin/startx usr/bin/vinix-xinput usr/bin/run-firefox aarch64-linux-musl-native/bin/gcc; do
        if [ ! -x "$STAGING/$command_path" ]; then
            echo "ERROR: compact desktop is missing /$command_path" >&2
            exit 1
        fi
    done
fi

if [ -x "$HYPRLAND_STAGING/usr/bin/start-hyprland-vinix" ]; then
    for runtime_path in usr/bin/Hyprland usr/bin/start-hyprland-vinix usr/bin/foot usr/lib/libaquamarine.so.11 root/.config/hypr/hyprland.conf; do
        if [ ! -e "$STAGING/$runtime_path" ]; then
            echo "ERROR: staged Hyprland runtime is missing /$runtime_path" >&2
            exit 1
        fi
    done
fi

cp "$BUILD_DIR/desktop-init" "$STAGING/sbin/init"
cp "$BUILD_DIR/vinix-desktop" "$STAGING/usr/bin/vinix-desktop"
if [ "$GPU_DESKTOP_BUILT" -eq 1 ]; then
    cp "$BUILD_DIR/vinix-desktop-gpu" "$STAGING/usr/bin/vinix-desktop-gpu"
    chmod +x "$STAGING/usr/bin/vinix-desktop-gpu"
fi
cp "$BUILD_DIR/wifi-ctl" "$STAGING/usr/bin/wifi-ctl"
chmod +x "$STAGING/sbin/init" "$STAGING/usr/bin/vinix-desktop" \
    "$STAGING/usr/bin/wifi-ctl"

# One immutable multicall image, one exec name and process per application.
# Vinix records the path passed to execve, so these relative symlinks produce
# distinct names and truthful per-app accounting without storing a copy of the
# same static executable for every native application in the initramfs.
for app_name in vinix-files vinix-calculator vinix-terminal vinix-settings \
    vinix-activity vinix-editor vinix-calendar vinix-clock vinix-cocoa-calculator; do
    ln -sf vinix-desktop "$STAGING/usr/bin/$app_name"
done

mkdir -p "$STAGING/Applications/Calculator.app/Contents/MacOS"
install -m644 "$BUILD_DIR/Calculator.app/Contents/Info.plist" \
    "$STAGING/Applications/Calculator.app/Contents/Info.plist"
install -m755 "$BUILD_DIR/Calculator.app/Contents/MacOS/Calculator" \
    "$STAGING/Applications/Calculator.app/Contents/MacOS/Calculator"

if [ -n "$WIFI_BUNDLE" ]; then
    echo "==> Staging the selected Wi-Fi firmware bundle..."
    mkdir -p "$STAGING/usr/share/vinix/wifi"
    for name in manifest.bin firmware.bin nvram.txt clm.blob txcap.blob; do
        cp "$WIFI_BUNDLE/$name" "$STAGING/usr/share/vinix/wifi/$name"
    done
    if [ -f "$WIFI_BUNDLE/provenance.json" ]; then
        cp "$WIFI_BUNDLE/provenance.json" "$STAGING/usr/share/vinix/wifi/provenance.json"
    fi
fi

# ── Wallpapers ──
# Vinix has no JPEG decoder, so the photographs are downloaded and decoded here
# and shipped as raw pixels. Downloads are cached, so this costs nothing after
# the first build; with neither network nor cache it writes none and the
# desktop offers only its colours.
echo "==> Wallpapers..."
python3 "$SCRIPT_DIR/desktop/tools/fetch_wallpapers.py" "$BUILD_DIR/wallpapers" \
    --cache "$BUILD_DIR/wallpapers-cache" || true

mkdir -p "$STAGING/usr/share/vinix/wallpapers"
if [ -d "$BUILD_DIR/wallpapers" ]; then
    cp "$BUILD_DIR/wallpapers"/*.vwp "$BUILD_DIR/wallpapers"/index.txt \
        "$BUILD_DIR/wallpapers"/SOURCES.txt "$STAGING/usr/share/vinix/wallpapers/" 2>/dev/null || true
fi

# The desktop's own source travels with the image, so the file browser has
# something real to show and so the machine carries the code it is running.
mkdir -p "$STAGING/root/desktop"
cp "$SCRIPT_DIR/desktop"/*.v "$SCRIPT_DIR/desktop"/*.c "$SCRIPT_DIR/desktop"/*.h \
    "$SCRIPT_DIR/desktop/README.md" \
    "$STAGING/root/desktop/"

# COPYFILE_DISABLE keeps macOS from adding ._ resource-fork members that the
# kernel's tar reader would try to unpack as real files.
# The deploy script may start rsync as soon as this build exits. Publish the
# completed image in one rename so parallel pushes never read a partial tar.
DESKTOP_INITRAMFS_TMP="$(mktemp "$(dirname "$DESKTOP_INITRAMFS")/.initramfs-desktop.tar.XXXXXX")"
if ! COPYFILE_DISABLE=1 tar --format=ustar -cf "$DESKTOP_INITRAMFS_TMP" -C "$STAGING" .; then
    rm -f "$DESKTOP_INITRAMFS_TMP"
    exit 1
fi
mv -f "$DESKTOP_INITRAMFS_TMP" "$DESKTOP_INITRAMFS"
echo "    $DESKTOP_INITRAMFS ($(stat -f%z "$DESKTOP_INITRAMFS") bytes)"
