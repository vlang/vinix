#!/bin/bash
# Cross-compile the Vinix desktop environment for aarch64 and stage it into an
# initramfs that boots straight into it.
#
# Usage: ./scripts/build-desktop-aarch64.sh [--no-initramfs] [--compact-initramfs]
#        [--without-firefox] [--with-libreoffice] [--with-minecraft] [--with-opengothic] [--with-dota2] [--with-asahi-gpu] [--with-x86-translation] [--with-roblox] [--wifi-bundle=DIR]
# Set V or VINIX_V_COMPILER to a V executable or checkout directory to select
# a compiler explicitly (for example V=~/code/v/v).
#
# V translates the program to C; clang compiles that C against the static musl
# sysroot extracted from the userland image. The result is a freestanding
# static binary. The bootable desktop image is the full userland with that
# binary and its desktop init overlaid, so opening a terminal exposes the same
# preinstalled commands as booting the userland directly.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$SCRIPT_DIR/build-support/find-v.sh"

if [ -n "${VINIX_UI2_SOURCE:-}" ]; then
    UI2_SOURCE="$VINIX_UI2_SOURCE"
elif [ -f "$SCRIPT_DIR/../ui2/v.mod" ]; then
    UI2_SOURCE="$SCRIPT_DIR/../ui2"
else
    UI2_SOURCE="$SCRIPT_DIR/third_party/ui2"
fi

BUILD_DIR="$SCRIPT_DIR/build"
# Keep the completed compositor outside the disposable build/ workspace.
# Its builder retains content fingerprints and only replaces the artifact when
# its inputs change. Override this for CI or isolated builds.
APP_CACHE_DIR="${VINIX_AARCH64_APP_CACHE:-$SCRIPT_DIR/build-aarch64-desktop-apps}"
USERLAND_BUILD_DIR="${VINIX_AARCH64_USERLAND_BUILD_DIR:-$SCRIPT_DIR/build-aarch64-userland}"
SYSROOT="${VINIX_AARCH64_SYSROOT:-$USERLAND_BUILD_DIR/staging}"
DEVTOOLS_ARCHIVE="${VINIX_AARCH64_DEVTOOLS_ARCHIVE:-$USERLAND_BUILD_DIR/alpine-devtools.tar}"
LLVM_BIN="${LLVM_BIN:-/opt/homebrew/opt/llvm/bin}"
if [ ! -x "$LLVM_BIN/clang" ]; then
    LLVM_CLANG="$(command -v clang || true)"
    if [ -n "$LLVM_CLANG" ]; then
        LLVM_BIN="$(dirname "$LLVM_CLANG")"
    fi
fi
# <stdatomic.h> has to be ours. See build-support/aarch64-cc-shim/stdatomic.h:
# -nostdinc leaves GCC 11's on the path, whose atomics clang rejects on the
# _Atomic pointers V generates, and clang's own header forwards straight back
# to it. This only started to matter when the desktop began importing os and
# time, which pull in sync.stdatomic.
CC_SHIM="$SCRIPT_DIR/build-support/aarch64-cc-shim"
BASE_INITRAMFS="$SCRIPT_DIR/build-support/init-aarch64/initramfs.tar"
# Overridable so a test can build an image of its own without replacing the one
# the deployment scripts and the QEMU desktop runner boot.
DESKTOP_INITRAMFS="${VINIX_DESKTOP_INITRAMFS:-$SCRIPT_DIR/build-support/init-aarch64/initramfs-desktop.tar}"
DESKTOP_INITRAMFS_GZ="$DESKTOP_INITRAMFS.gz"
PYTHON_STAGING="${VINIX_PYTHON_STAGING:-$SCRIPT_DIR/build-aarch64-python/staging}"
NETWORK_TOOLS_STAGING="${VINIX_NETWORK_TOOLS_STAGING:-$SCRIPT_DIR/build-aarch64-network-tools/staging}"
VLANG_STAGING="${VINIX_VLANG_STAGING:-$SCRIPT_DIR/build-aarch64-v/staging}"
X11_STAGING="${VINIX_X11_STAGING:-$SCRIPT_DIR/build-aarch64-x11/staging}"
FIREFOX_STAGING="${VINIX_FIREFOX_STAGING:-$SCRIPT_DIR/build-aarch64-firefox/staging}"
CHROMIUM_STAGING="${VINIX_CHROMIUM_STAGING:-$SCRIPT_DIR/build-aarch64-chromium/staging}"
LIBREOFFICE_STAGING="${VINIX_LIBREOFFICE_STAGING:-$SCRIPT_DIR/build-aarch64-libreoffice/staging}"
MINECRAFT_STAGING="${VINIX_MINECRAFT_STAGING:-$SCRIPT_DIR/build-aarch64-minecraft/staging}"
DOOM_STAGING="${VINIX_DOOM_STAGING:-$SCRIPT_DIR/build-aarch64-doom/staging}"
OPENGOTHIC_STAGING="${VINIX_OPENGOTHIC_STAGING:-$SCRIPT_DIR/build/opengothic/staging}"
ASAHI_STAGING="${VINIX_ASAHI_STAGING:-$SCRIPT_DIR/build-aarch64-asahi/staging}"
HYPRLAND_STAGING="${VINIX_HYPRLAND_STAGING:-$SCRIPT_DIR/build-aarch64-hyprland/staging}"
BLENDER_NATIVE_STAGING="${VINIX_BLENDER_NATIVE_STAGING:-$SCRIPT_DIR/build-aarch64-blender-native/staging}"
X86_TRANSLATION_STAGING="${VINIX_X86_TRANSLATION_STAGING:-$SCRIPT_DIR/build-aarch64-x86-translation/staging}"
STEAM_STAGING="${VINIX_STEAM_STAGING:-$SCRIPT_DIR/build-aarch64-steam/staging}"
DOTA2_STAGING="${VINIX_DOTA2_STAGING:-$SCRIPT_DIR/build/dota2-runtime/staging}"
QEMU_SYSTEM_STAGING="${VINIX_QEMU_SYSTEM_STAGING:-$SCRIPT_DIR/build-aarch64-qemu-system/staging}"
IOS_STAGING="${VINIX_IOS_STAGING:-$SCRIPT_DIR/build/ios/staging}"
ANDROID_STAGING="${VINIX_ANDROID_STAGING:-$SCRIPT_DIR/build-aarch64-android/aarch64/staging}"
ROBLOX_STAGING="${VINIX_ROBLOX_STAGING:-$SCRIPT_DIR/build-aarch64-roblox/aarch64/staging}"
GPU_SYSROOT="${VINIX_GPU_SYSROOT:-$SCRIPT_DIR/build-aarch64-x11/sysroot}"

file_size() {
    if stat -f%z "$1" >/dev/null 2>&1; then
        stat -f%z "$1"
    else
        stat -c%s "$1"
    fi
}

# Most layer builders replace their staging root when rebuilt, so inode/mtime
# is enough to notice a new generation without hashing gigabytes of Blender,
# Minecraft, Wine or Mesa contents. scripts/build-x11-aarch64.sh intentionally updates
# its staging and sysroot trees in place, as does the Doom builder. Use a
# metadata-only tree fingerprint for those inputs so a nested library or WAD
# update cannot leave this cache stale. Metadata mode never reads file contents.
path_generation() {
    local path="$1"
    local value

    if [ ! -e "$path" ] && [ ! -L "$path" ]; then
        printf 'missing'
        return 0
    fi
    if [ "$path" = "$X11_STAGING" ] || [ "$path" = "$GPU_SYSROOT" ] ||
       [ "$path" = "$DOOM_STAGING" ] || [ "$path" = "$OPENGOTHIC_STAGING" ] || [ "$path" = "$STEAM_STAGING" ] || [ "$path" = "$DOTA2_STAGING" ]; then
        python3 "$SCRIPT_DIR/build-support/content-key.py" --metadata "$path"
        return 0
    fi
    if value="$(stat -f '%d:%i:%m:%z' "$path" 2>/dev/null)"; then
        printf '%s' "$value"
    else
        stat -c '%d:%i:%Y:%s' "$path"
    fi
}

write_staging_cache_manifest() {
    local input

    # Change this when the immutable-layer assembly logic changes. Desktop
    # source and launcher edits are refreshed below without restaging 6+ GiB.
    printf 'version=8\n'
    printf 'compact=%s\n' "$COMPACT_INITRAMFS"
    printf 'without_firefox=%s\n' "$WITHOUT_FIREFOX"
    printf 'chromium=%s\n' "$WITH_CHROMIUM"
    printf 'libreoffice=%s\n' "$WITH_LIBREOFFICE"
    printf 'minecraft=%s\n' "$WITH_MINECRAFT"
    printf 'opengothic=%s\n' "$WITH_OPENGOTHIC"
    printf 'asahi=%s\n' "$WITH_ASAHI_GPU"
    printf 'x86=%s\n' "$WITH_X86_TRANSLATION"
    printf 'steam=%s\n' "$WITH_STEAM"
    printf 'dota2=%s\n' "$WITH_DOTA2"
    printf 'qemu_system=%s\n' "$WITH_QEMU_SYSTEM"
    printf 'android=%s\n' "$WITH_ANDROID"
    printf 'roblox=%s\n' "$WITH_ROBLOX"
    for input in \
        "$BASE_INITRAMFS" "$DEVTOOLS_ARCHIVE" "$SYSROOT" \
        "$PYTHON_STAGING" "$NETWORK_TOOLS_STAGING" "$X11_STAGING" \
        "$VLANG_STAGING" \
        "$FIREFOX_STAGING" "$CHROMIUM_STAGING" "$LIBREOFFICE_STAGING" \
        "$MINECRAFT_STAGING" "$ASAHI_STAGING" "$HYPRLAND_STAGING" \
        "$DOOM_STAGING" "$OPENGOTHIC_STAGING" \
        "$BLENDER_NATIVE_STAGING" "$X86_TRANSLATION_STAGING" "$STEAM_STAGING" "$DOTA2_STAGING" \
        "$QEMU_SYSTEM_STAGING" "$ANDROID_STAGING" "$ROBLOX_STAGING" \
        "$GPU_SYSROOT"; do
        printf '%s=%s\n' "$input" "$(path_generation "$input")"
    done
}

merge_staging_tree() {
    local overlay="$1"
    local source relative destination

    # macOS cp follows an existing destination symlink and cannot replace a
    # read-only regular file in place. Package closures share both kinds (the
    # JDK legal files are deliberately 0444), so unlink non-directory entries
    # before the later overlay recreates them with its own mode and contents.
    while IFS= read -r -d '' source; do
        relative="${source#"$overlay/"}"
        destination="$STAGING/$relative"
        if [ ! -d "$source" ] && { [ -e "$destination" ] || [ -L "$destination" ]; }; then
            rm -f "$destination"
        fi
    done < <(find "$overlay" -mindepth 1 -print0)

    cp -a "$overlay/." "$STAGING/"
}

MAKE_INITRAMFS=1
COMPACT_INITRAMFS=0
WITH_X86_TRANSLATION=0
WITH_STEAM=0
WITH_DOTA2=0
WITH_QEMU_SYSTEM=0
WITH_ANDROID=0
WITH_ROBLOX=0
WITH_CHROMIUM=0
WITH_LIBREOFFICE=0
WITH_MINECRAFT=0
WITH_OPENGOTHIC=0
WITHOUT_FIREFOX=0
REFRESH_STAGING="${VINIX_REFRESH_DESKTOP_STAGING:-0}"
# The Apple GPU userspace is only correct on Apple hardware; see the overlay
# below for why its mere presence on disk must not select it.
WITH_ASAHI_GPU="${VINIX_WITH_ASAHI_GPU:-0}"
WIFI_BUNDLE="${VINIX_WIFI_BUNDLE:-}"
for arg in "$@"; do
    case "$arg" in
        --no-initramfs) MAKE_INITRAMFS=0 ;;
        --compact-initramfs) COMPACT_INITRAMFS=1 ;;
        --with-x86-translation) WITH_X86_TRANSLATION=1 ;;
        --with-steam) WITH_STEAM=1 ;;
        --with-dota2) WITH_DOTA2=1 ;;
        --with-qemu-system) WITH_QEMU_SYSTEM=1 ;;
        --with-android) WITH_ANDROID=1 ;;
        --with-roblox) WITH_ROBLOX=1; WITH_ANDROID=1 ;;
        --with-chromium) WITH_CHROMIUM=1 ;;
        --with-libreoffice) WITH_LIBREOFFICE=1 ;;
        --with-minecraft) WITH_MINECRAFT=1 ;;
        --with-opengothic) WITH_OPENGOTHIC=1 ;;
        --without-firefox) WITHOUT_FIREFOX=1 ;;
        --with-asahi-gpu) WITH_ASAHI_GPU=1 ;;
        --wifi-bundle=*) WIFI_BUNDLE="${arg#*=}" ;;
        --help|-h)
            echo "usage: $0 [--no-initramfs] [--compact-initramfs] [--without-firefox] [--with-chromium] [--with-libreoffice] [--with-minecraft] [--with-opengothic] [--with-dota2] [--with-asahi-gpu] [--with-x86-translation] [--with-steam] [--with-qemu-system] [--with-android] [--with-roblox] [--wifi-bundle=DIR]"
            echo "  --compact-initramfs stages the desktop, core developer tools and Firefox"
            echo "  --without-firefox leaves the browser out of a compact image, keeping its"
            echo "      GTK/media runtime; the first-run app page offers it through pkg"
            echo "  --with-chromium adds a previously staged Chromium; otherwise it is a pkg install"
            echo "  --with-libreoffice adds a previously staged LibreOffice; otherwise it is a pkg install"
            echo "  --with-minecraft adds a previously staged Minecraft; otherwise it is a pkg install"
            echo "  --with-opengothic adds a previously staged OpenGothic and its game data to a compact image"
            echo "  --with-asahi-gpu overlays the Apple GPU Mesa; only correct for an M1 image"
            echo "  --with-x86-translation adds a previously built x86/Wine runtime"
            echo "  --with-steam adds a previously staged Steam client and its x86 glibc runtime"
            echo "  --with-dota2 adds the Linux Dota 2 runtime; game files are installed separately"
            echo "  --with-qemu-system adds native QEMU and UEFI firmware for nested Vinix"
            echo "  --with-android adds Android Translation Layer and any staged APKs"
            echo "  --with-roblox adds native ATL/ART and the Roblox launchers; supply your own ARM64 APK"
            echo "  --wifi-bundle stages a package.py output and loads it before the desktop"
            echo "  VINIX_REFRESH_DESKTOP_STAGING=1 discards the cached assembled layers"
            echo "  VINIX_AARCH64_APP_CACHE changes the persistent desktop binary cache"
            exit 0
            ;;
        *)
            echo "ERROR: unknown option: $arg" >&2
            exit 1
            ;;
    esac
done

if [ "$WITHOUT_FIREFOX" -eq 1 ] && [ "$COMPACT_INITRAMFS" -ne 1 ]; then
    echo "ERROR: --without-firefox applies to --compact-initramfs images" >&2
    exit 1
fi

case "$REFRESH_STAGING" in
    0|1) ;;
    *)
        echo "ERROR: VINIX_REFRESH_DESKTOP_STAGING must be 0 or 1" >&2
        exit 1
        ;;
esac

if [ "$MAKE_INITRAMFS" -eq 0 ] &&
   { [ -n "$WIFI_BUNDLE" ] || [ "$WITH_X86_TRANSLATION" -eq 1 ] || [ "$WITH_STEAM" -eq 1 ] || [ "$WITH_DOTA2" -eq 1 ] || [ "$WITH_QEMU_SYSTEM" -eq 1 ] || [ "$WITH_ANDROID" -eq 1 ] || [ "$WITH_ROBLOX" -eq 1 ]; }; then
    echo "ERROR: --wifi-bundle, --with-x86-translation, --with-steam, --with-dota2, --with-qemu-system, --with-android and --with-roblox require initramfs generation" >&2
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

# Every desktop variant uses the same generated C, compiled binaries, assembled
# root and (unless explicitly overridden) output archive. In particular, the
# QEMU runner builds a full generic-Mesa image while the M1 deployment path
# builds a compact Asahi image. Letting those run together means either build
# can remove build/initramfs-root while the other is overlaying or validating
# it; the loser then reports apparently impossible missing base executables.
# Serialize the complete pipeline, not just the final tar rename, because the
# compiler outputs and staging tree are shared too.
DESKTOP_BUILD_LOCK="$BUILD_DIR/.build-desktop-aarch64.lock"
desktop_build_lock_owner() {
    if [ -L "$DESKTOP_BUILD_LOCK" ]; then
        readlink "$DESKTOP_BUILD_LOCK" 2>/dev/null || true
    elif [ -f "$DESKTOP_BUILD_LOCK/pid" ]; then
        # Compatibility with a build which started while this change was being
        # installed and had already acquired the directory-form lock.
        cat "$DESKTOP_BUILD_LOCK/pid" 2>/dev/null || true
    fi
}

release_desktop_build_lock() {
    local owner

    owner="$(desktop_build_lock_owner)"
    if [ "$owner" = "$$" ]; then
        if [ -L "$DESKTOP_BUILD_LOCK" ]; then
            rm -f "$DESKTOP_BUILD_LOCK"
        else
            rm -rf "$DESKTOP_BUILD_LOCK"
        fi
    fi
}

mkdir -p "$BUILD_DIR"

build_lock_wait_reported=0
while ! ln -s "$$" "$DESKTOP_BUILD_LOCK" 2>/dev/null; do
    build_lock_owner="$(desktop_build_lock_owner)"
    if [ -n "$build_lock_owner" ] && ! kill -0 "$build_lock_owner" 2>/dev/null; then
        if [ -L "$DESKTOP_BUILD_LOCK" ]; then
            rm -f "$DESKTOP_BUILD_LOCK"
        else
            rm -rf "$DESKTOP_BUILD_LOCK"
        fi
        continue
    fi
    if [ "$build_lock_wait_reported" -eq 0 ]; then
        if [ -n "$build_lock_owner" ]; then
            echo "==> Another desktop build (PID $build_lock_owner) is active; waiting..."
        else
            echo "==> Another desktop build is starting; waiting..."
        fi
        build_lock_wait_reported=1
    fi
    sleep 1
done
trap release_desktop_build_lock EXIT

archive_has_member() {
    local archive="$1"
    local member="$2"
    [ -f "$archive" ] && tar tf "$archive" "$member" >/dev/null 2>&1
}

# The desktop runner normally reuses the assembled userland because rebuilding
# every language and application layer is much slower than iterating on ui2.
# Refresh it once when a checkout adds a new required base package, rather than
# failing late after the desktop binaries have already been compiled. Compact
# images obtain Vim from the development-tools archive; full images obtain it
# from the complete base archive.
if [ "$MAKE_INITRAMFS" -eq 1 ]; then
    VIM_ARCHIVE="$BASE_INITRAMFS"
    if [ "$COMPACT_INITRAMFS" -eq 1 ]; then
        VIM_ARCHIVE="$DEVTOOLS_ARCHIVE"
    fi
    if ! archive_has_member "$VIM_ARCHIVE" ./usr/bin/vim; then
        echo "==> AArch64 userland predates the required Vim package; rebuilding it..."
        VINIX_AARCH64_USERLAND_BUILD_DIR="$USERLAND_BUILD_DIR" \
        VINIX_AARCH64_INITRAMFS="$BASE_INITRAMFS" \
            "$SCRIPT_DIR/scripts/build-userland-aarch64.sh"
        if ! archive_has_member "$VIM_ARCHIVE" ./usr/bin/vim; then
            echo "ERROR: rebuilt AArch64 userland still has no executable /usr/bin/vim" >&2
            exit 1
        fi
    fi
fi

if [ "$MAKE_INITRAMFS" -eq 1 ] && [ ! -x "$VLANG_STAGING/usr/lib/vlang/v" ]; then
    if [ -n "${VINIX_VLANG_STAGING:-}" ]; then
        echo "ERROR: custom V staging is incomplete: $VLANG_STAGING" >&2
        exit 1
    fi
    echo "==> Native V compiler is missing; building it..."
    V="$V" \
    VINIX_AARCH64_USERLAND_BUILD_DIR="$USERLAND_BUILD_DIR" \
    VINIX_AARCH64_SYSROOT="$SYSROOT" \
        "$SCRIPT_DIR/scripts/build-v-aarch64.sh"
    if [ ! -x "$VLANG_STAGING/usr/lib/vlang/v" ]; then
        echo "ERROR: V compiler build did not publish $VLANG_STAGING" >&2
        exit 1
    fi
fi

# ── The Alpine musl sysroot ──
# The desktop is static, so its build sysroot needs the same allocator as apps.
python3 "$SCRIPT_DIR/build-support/musl/stage.py" --arch aarch64 --staging "$SYSROOT"

if [ ! -f "$SYSROOT/usr/lib/libc.a" ] || [ ! -d "$SYSROOT/usr/include" ]; then
    echo "ERROR: Alpine development sysroot is incomplete: $SYSROOT"
    echo "Run ./scripts/build-userland-aarch64.sh first."
    exit 1
fi
GCCLIB="$(find "$SYSROOT/usr/lib/gcc/aarch64-alpine-linux-musl" \
    -mindepth 1 -maxdepth 1 -type d 2>/dev/null | LC_ALL=C sort | tail -n1)"
if [ -z "$GCCLIB" ] || [ ! -f "$GCCLIB/libgcc.a" ]; then
    echo "ERROR: Alpine GCC runtime not found below $SYSROOT/usr/lib/gcc"
    exit 1
fi

# ── ui2 ──
# The desktop is built on ui2's declarative element tree. It is not vendored;
# check it out beside the sources and point V's module path at it.
if [ ! -f "$UI2_SOURCE/v.mod" ]; then
    echo "ERROR: ui2 not found at $UI2_SOURCE. Clone it at third_party/ui2:"
    echo "    git clone https://github.com/vlang/ui2 third_party/ui2"
    exit 1
fi

# Calculator uses the v3 compiler's direct `$vml` lowering. Check the renamed
# API explicitly so an old QML checkout fails before the compiler does.
if [ ! -f "$UI2_SOURCE/ui/vml_compiled.v" ] || \
   [ ! -f "$UI2_SOURCE/examples/calculator/calculator.vml" ]; then
    echo "ERROR: this ui2 checkout has no compile-time VML support."
    echo "Update the checkout:"
    echo "    git -C third_party/ui2 pull"
    exit 1
fi

if [ ! -x "$LLVM_BIN/clang" ] || [ ! -x "$LLVM_BIN/llvm-strip" ]; then
    echo "ERROR: LLVM clang and llvm-strip not found in $LLVM_BIN"
    exit 1
fi

mkdir -p "$BUILD_DIR"

# `$vml` starts from ui2.bounds(), while a Linux-headless module deliberately
# has no platform window. Build against a disposable module overlay that adds
# Vinix's bounds bridge without modifying the upstream checkout.
UI2_MODULES="$BUILD_DIR/vmodules"
python3 "$SCRIPT_DIR/desktop/tools/stage_ui2.py" \
    "$UI2_MODULES/ui2" "$UI2_SOURCE" \
    "$SCRIPT_DIR/desktop/tools/ui2_headless_bounds.v"

# ── Stage the sources ──
# Native ui2 applications exec this multicall binary under per-app names, and
# an application's model is V code that has to be compiled in. The staging
# step takes each example's source straight from the ui2 checkout — everything
# but its `fn main()`, which only opens a platform window — so what runs is the
# example itself.
echo "==> Staging sources..."
APP_SRC="$BUILD_DIR/app-src"
python3 "$SCRIPT_DIR/desktop/tools/stage_app.py" "$APP_SRC" "$SCRIPT_DIR/desktop" \
    "$UI2_SOURCE/examples/calculator"

# The development image carries generated artifacts alongside their V source.
python3 "$SCRIPT_DIR/build-support/compile-v-module.py" \
    "$SCRIPT_DIR/desktop/execinfocore" "$BUILD_DIR/execinfo.c" --arch arm64 \
    --header "$BUILD_DIR/execinfo_compat.h"
rm -f "$APP_SRC/gpu_present.h"
python3 "$SCRIPT_DIR/build-support/compile-v-module.py" \
    "$SCRIPT_DIR/desktop/gpucore" "$BUILD_DIR/gpu-present-soft.c" --arch arm64 \
    --header "$APP_SRC/gpu_present.h"

# Keep the compositor executable outside build/, just like the standalone
# applications. A direct desktop build can then reuse it even after build/
# has been cleaned. Bump the command version when its V or C flags change.
DESKTOP_CACHE_DIR="$APP_CACHE_DIR/desktop"
mkdir -p "$DESKTOP_CACHE_DIR"
V_REAL="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$V")"
LLD_FOR_CACHE="$(command -v "${LD_LLD:-ld.lld}" || true)"
DESKTOP_CACHE_ARGS=(
    --state "$DESKTOP_CACHE_DIR/.build-key" --staging "$DESKTOP_CACHE_DIR"
    --value desktop-aarch64-command-v2
    --source "$APP_SRC" --source "$UI2_MODULES/ui2"
    --source "$V_REAL" --vlib "$(dirname "$V_REAL")/vlib"
    --source "$CC_SHIM"
    --source "$SCRIPT_DIR/desktop/execinfocore" --source "$SCRIPT_DIR/desktop/gpucore"
    --source "$SCRIPT_DIR/build-support/compile-v-module.py"
    --metadata "$LLVM_BIN/clang" --metadata "$LLVM_BIN/llvm-strip"
    --metadata "$SYSROOT/usr/include" --metadata "$GCCLIB/include"
    --metadata "$SYSROOT/usr/lib/crt1.o" --metadata "$SYSROOT/usr/lib/crti.o"
    --metadata "$SYSROOT/usr/lib/crtn.o" --metadata "$SYSROOT/usr/lib/libc.a"
    --metadata "$SYSROOT/usr/lib/libm.a" --metadata "$GCCLIB/crtbeginT.o"
    --metadata "$GCCLIB/crtend.o" --metadata "$GCCLIB/libgcc.a"
    --metadata "$GCCLIB/libgcc_eh.a"
    --executable vinix-desktop
)
if [ -n "$LLD_FOR_CACHE" ]; then
    DESKTOP_CACHE_ARGS+=(--metadata "$LLD_FOR_CACHE")
fi
GPU_CACHE_AVAILABLE=0
if [ -f "$ASAHI_STAGING/usr/lib/libEGL.so" ] &&
   [ -f "$ASAHI_STAGING/usr/lib/libGLESv2.so" ] &&
   [ -f "$ASAHI_STAGING/usr/include/EGL/egl.h" ] &&
   [ -f "$GPU_SYSROOT/usr/lib/Scrt1.o" ]; then
    GPU_CACHE_AVAILABLE=1
    DESKTOP_CACHE_ARGS+=(
        --value gpu-enabled --executable vinix-desktop-gpu
        --source "$SCRIPT_DIR/desktop/gpucore"
        --metadata "$ASAHI_STAGING/usr/lib" --metadata "$ASAHI_STAGING/usr/include"
        --metadata "$GPU_SYSROOT/usr/lib" --metadata "$GPU_SYSROOT/usr/include"
    )
else
    DESKTOP_CACHE_ARGS+=(--value gpu-unavailable)
fi
DESKTOP_CACHE_HIT=0
if python3 "$SCRIPT_DIR/build-support/staging-cache.py" check "${DESKTOP_CACHE_ARGS[@]}"; then
    DESKTOP_CACHE_HIT=1
    cp -a "$DESKTOP_CACHE_DIR/vinix-desktop" "$BUILD_DIR/vinix-desktop"
    if [ "$GPU_CACHE_AVAILABLE" -eq 1 ]; then
        cp -a "$DESKTOP_CACHE_DIR/vinix-desktop-gpu" "$BUILD_DIR/vinix-desktop-gpu"
    fi
    echo "==> Reusing cached AArch64 desktop executable"
fi

# ── V -> C ──
# -gc none because Vinix has no Boehm GC, and -d ui2_headless so importing ui2
# brings in its declarative core without its gg/Sokol backend.
if [ "$DESKTOP_CACHE_HIT" -eq 0 ]; then
    echo "==> Translating V to C..."
    # The generated ui2/VML program is large enough to cross V3's general-purpose
    # 10176 MiB watchdog while it is still making forward declarations. This is a
    # host-side release build, so let the machine's own memory limit govern it.
    "$V" -new-compiler -no-memory-limit -os linux -arch arm64 -gc none -manualfree -enable-globals -prod \
        -d glibc \
        -d ui2_headless \
        -path "@vlib|$UI2_MODULES|@vmodules|$SCRIPT_DIR|$SCRIPT_DIR/third_party" \
        -o "$BUILD_DIR/desktop.c" "$APP_SRC"

    # ── C -> aarch64 static binary ──
    echo "==> Compiling for aarch64-linux-musl..."
    "$LLVM_BIN/clang" --target=aarch64-linux-musl -static -nostdinc -nostdlib \
        -isystem "$CC_SHIM" \
        -isystem "$GCCLIB/include" -isystem "$SYSROOT/usr/include" \
        -I "$APP_SRC" \
        -D_GNU_SOURCE -O2 -fno-stack-protector -w \
        "$SYSROOT/usr/lib/crt1.o" "$SYSROOT/usr/lib/crti.o" "$GCCLIB/crtbeginT.o" \
        "$BUILD_DIR/desktop.c" "$BUILD_DIR/execinfo.c" "$BUILD_DIR/gpu-present-soft.c" \
        -L"$SYSROOT/usr/lib" -L"$GCCLIB" -lgcc_eh -lc -lgcc -lm \
        "$GCCLIB/crtend.o" "$SYSROOT/usr/lib/crtn.o" \
        -fuse-ld=lld -B"$LLVM_BIN" \
        -o "$BUILD_DIR/vinix-desktop"

    "$LLVM_BIN/llvm-strip" "$BUILD_DIR/vinix-desktop"
    echo "    $BUILD_DIR/vinix-desktop ($(file_size "$BUILD_DIR/vinix-desktop") bytes)"
fi

# Mesa is a dynamic runtime, so keep the always-bootable static desktop and
# build a second executable only when the exact Asahi userspace is available.
# Both binaries use the same generated compositor. Separate V presenter modules
# provide the software stubs and the optional EGL implementation. The UI is
# still rasterized into its Canvas on the CPU; EGL/GLES moves scaling and
# presentation to AGX before the unavoidable firmware-framebuffer readback.
GPU_DESKTOP_BUILT=0
if [ "$GPU_CACHE_AVAILABLE" -eq 1 ]; then
    if [ "$DESKTOP_CACHE_HIT" -eq 1 ]; then
        echo "==> Reusing cached GPU-enabled desktop executable"
        GPU_DESKTOP_BUILT=1
    else
        python3 "$SCRIPT_DIR/build-support/compile-v-module.py" \
            "$SCRIPT_DIR/desktop/gpucore" "$BUILD_DIR/gpu-present.c" --arch arm64 \
            -d gpu_presenter_enabled
        echo "==> Compiling the GPU-enabled desktop for aarch64-linux-musl..."
        # Keep the large generated compositor at a fixed address. Building it as
        # PIE creates more than 8,000 relative relocations which musl has to write
        # before main(), needlessly exercising thousands of VM faults on the
        # native multi-core boot path. Mesa and EGL remain ordinary shared
        # libraries; only the executable itself is non-PIE.
        "$LLVM_BIN/clang" --target=aarch64-linux-musl \
            --sysroot="$GPU_SYSROOT" --gcc-install-dir="$GCCLIB" -static-libgcc \
            -isystem "$CC_SHIM" \
            -I "$APP_SRC" -I "$ASAHI_STAGING/usr/include" \
            -D_GNU_SOURCE -O2 -fno-pie -no-pie -fno-stack-protector -w \
            "$BUILD_DIR/desktop.c" "$BUILD_DIR/execinfo.c" \
            "$BUILD_DIR/gpu-present.c" \
            -L"$ASAHI_STAGING/usr/lib" \
            -Wl,-rpath-link,"$ASAHI_STAGING/usr/lib" \
            -Wl,-dynamic-linker,/lib/ld-musl-aarch64.so.1 \
            -lEGL -lGLESv2 -ldl -lpthread -lgcc_eh -lm \
            -fuse-ld=lld -B"$LLVM_BIN" \
            -o "$BUILD_DIR/vinix-desktop-gpu"
        "$LLVM_BIN/llvm-strip" "$BUILD_DIR/vinix-desktop-gpu"
        GPU_DESKTOP_ELF_TYPE="$("$LLVM_BIN/llvm-readelf" -h \
            "$BUILD_DIR/vinix-desktop-gpu" | awk '$1 == "Type:" { print $2; exit }')"
        if [ "$GPU_DESKTOP_ELF_TYPE" != "EXEC" ]; then
            echo "ERROR: GPU desktop must be a fixed-address ELF executable; got $GPU_DESKTOP_ELF_TYPE" >&2
            exit 1
        fi
        echo "    $BUILD_DIR/vinix-desktop-gpu ($(file_size "$BUILD_DIR/vinix-desktop-gpu") bytes)"
        GPU_DESKTOP_BUILT=1
        if [ ! -f "$ASAHI_STAGING/usr/share/vinix/mesa-x11-egl" ] &&
           [ ! -f "$ASAHI_STAGING/usr/share/vinix/asahi-x11-egl" ]; then
            echo "    NOTE: this Mesa staging predates X11/GBM support; rebuild it for Firefox acceleration"
        fi
    fi
else
    echo "==> Asahi EGL staging not found; keeping the static software desktop only"
fi

if [ "$DESKTOP_CACHE_HIT" -eq 0 ]; then
    cp -a "$BUILD_DIR/vinix-desktop" "$DESKTOP_CACHE_DIR/vinix-desktop.tmp"
    mv -f "$DESKTOP_CACHE_DIR/vinix-desktop.tmp" "$DESKTOP_CACHE_DIR/vinix-desktop"
    if [ "$GPU_DESKTOP_BUILT" -eq 1 ]; then
        cp -a "$BUILD_DIR/vinix-desktop-gpu" "$DESKTOP_CACHE_DIR/vinix-desktop-gpu.tmp"
        mv -f "$DESKTOP_CACHE_DIR/vinix-desktop-gpu.tmp" "$DESKTOP_CACHE_DIR/vinix-desktop-gpu"
    fi
    python3 "$SCRIPT_DIR/build-support/staging-cache.py" record "${DESKTOP_CACHE_ARGS[@]}"
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
if [ ! -x "$X11_STAGING/usr/bin/vinix-xinput" ] ||
   [ ! -x "$X11_STAGING/usr/bin/vinix-wine-host" ] ||
   [ ! -x "$X11_STAGING/usr/bin/Xvfb" ]; then
    echo "ERROR: desktop needs Xvfb and the Vinix X11 input bridges in $X11_STAGING" >&2
    echo "Run ./scripts/build-x11-aarch64.sh first." >&2
    exit 1
fi
sh "$SCRIPT_DIR/build-support/xorg-server/build-wine-host.sh" aarch64 \
    "$X11_STAGING" "$SYSROOT"
if [ ! -x "$NETWORK_TOOLS_STAGING/usr/bin/pkg" ] ||
   [ ! -x "$NETWORK_TOOLS_STAGING/sbin/apk" ] ||
   [ ! -s "$NETWORK_TOOLS_STAGING/etc/vinix-pkg/base-world" ]; then
    echo "ERROR: desktop needs the package layer in $NETWORK_TOOLS_STAGING" >&2
    echo "Run ./scripts/build-network-tools-aarch64.sh first." >&2
    exit 1
fi
if [ "$COMPACT_INITRAMFS" -eq 1 ]; then
    if [ ! -x "$PYTHON_STAGING/usr/bin/python3" ]; then
        echo "ERROR: compact desktop needs $PYTHON_STAGING/usr/bin/python3" >&2
        echo "Run ./scripts/build-python-aarch64.sh first." >&2
        exit 1
    fi
    if [ ! -x "$NETWORK_TOOLS_STAGING/usr/bin/git" ]; then
        echo "ERROR: compact desktop needs $NETWORK_TOOLS_STAGING/usr/bin/git" >&2
        echo "Run ./scripts/build-network-tools-aarch64.sh first." >&2
        exit 1
    fi
    if [ ! -x "$FIREFOX_STAGING/usr/bin/run-firefox" ]; then
        echo "ERROR: compact desktop needs $FIREFOX_STAGING/usr/bin/run-firefox" >&2
        echo "Run ./scripts/build-x11-aarch64.sh and ./scripts/build-firefox-aarch64.sh first." >&2
        exit 1
    fi
    if [ ! -x "$X11_STAGING/usr/bin/Xorg" ] ||
        [ ! -x "$X11_STAGING/usr/bin/Xvfb" ] ||
        [ ! -x "$X11_STAGING/usr/bin/startx" ] ||
        [ ! -x "$X11_STAGING/usr/bin/vinix-xinput" ] ||
        [ ! -x "$X11_STAGING/usr/bin/vinix-wine-host" ]; then
        echo "ERROR: compact desktop needs Xorg, Xvfb, startx and the input bridges in $X11_STAGING" >&2
        echo "Run ./scripts/build-x11-aarch64.sh first." >&2
        exit 1
    fi
fi
if [ "$WITH_CHROMIUM" -eq 1 ] &&
   [ ! -x "$CHROMIUM_STAGING/usr/lib/chromium/chrome" ]; then
    echo "ERROR: --with-chromium needs $CHROMIUM_STAGING/usr/lib/chromium/chrome" >&2
    echo "Run ./scripts/build-chromium-aarch64.sh first." >&2
    exit 1
fi
if [ "$WITH_LIBREOFFICE" -eq 1 ] &&
   [ ! -x "$LIBREOFFICE_STAGING/usr/lib/libreoffice/program/soffice.bin" ]; then
    echo "ERROR: --with-libreoffice needs $LIBREOFFICE_STAGING/usr/lib/libreoffice/program/soffice.bin" >&2
    echo "Run ./scripts/build-libreoffice-aarch64.sh first." >&2
    exit 1
fi
if [ "$WITH_MINECRAFT" -eq 1 ] &&
   [ ! -x "$MINECRAFT_STAGING/usr/bin/minecraft" ]; then
    echo "ERROR: --with-minecraft needs $MINECRAFT_STAGING/usr/bin/minecraft" >&2
    echo "Run ./scripts/build-minecraft-aarch64.sh first." >&2
    exit 1
fi
if [ "$WITH_OPENGOTHIC" -eq 1 ] &&
   [ ! -x "$OPENGOTHIC_STAGING/opt/opengothic/Gothic2Notr" ]; then
    echo "ERROR: --with-opengothic needs $OPENGOTHIC_STAGING/opt/opengothic/Gothic2Notr" >&2
    echo "Run ./scripts/build-opengothic-aarch64.sh first." >&2
    exit 1
fi
if [ "$WITH_X86_TRANSLATION" -eq 1 ] &&
   [ ! -x "$X86_TRANSLATION_STAGING/usr/bin/qemu-x86_64" ]; then
    echo "ERROR: --with-x86-translation needs $X86_TRANSLATION_STAGING/usr/bin/qemu-x86_64" >&2
    echo "Run ./scripts/build-x86-translation-aarch64.sh first." >&2
    exit 1
fi
if [ "$WITH_DOTA2" -eq 1 ]; then
    DOTA2_REQUIRED_PATHS=(
        usr/bin/qemu-x86_64
        usr/bin/run-dota2
        usr/libexec/vinix-dota2/root/lib64/ld-linux-x86-64.so.2
        usr/libexec/vinix-dota2/root/usr/lib/x86_64-linux-gnu/libvulkan.so.1
        usr/libexec/vinix-dota2/root/usr/lib/x86_64-linux-gnu/libvinix-steam-robust.so
        usr/libexec/vinix-dota2/root/usr/lib/x86_64-linux-gnu/libvinix-dota2-mmap32.so
        usr/libexec/vinix-dota2/root/usr/lib/x86_64-linux-gnu/libmpg123.so.0
        usr/libexec/vinix-dota2/root/usr/lib/x86_64-linux-gnu/libfreetype.so.6
        usr/libexec/vinix-dota2/root/usr/lib/x86_64-linux-gnu/libvinix-dota2-steam-loader.so
        usr/libexec/vinix-dota2/root/usr/share/vulkan/icd.d/lvp_icd.x86_64.json
    )
    for required in "${DOTA2_REQUIRED_PATHS[@]}"; do
        if [ ! -e "$DOTA2_STAGING/$required" ]; then
            echo "ERROR: --with-dota2 needs $DOTA2_STAGING/$required" >&2
            echo "Run ./scripts/build-dota2-aarch64.sh first." >&2
            exit 1
        fi
    done
    for command_path in usr/bin/qemu-x86_64 usr/bin/run-dota2; do
        if [ ! -x "$DOTA2_STAGING/$command_path" ]; then
            echo "ERROR: --with-dota2 needs $DOTA2_STAGING/$command_path" >&2
            echo "Run ./scripts/build-dota2-aarch64.sh first." >&2
            exit 1
        fi
    done
fi
if [ "$WITH_STEAM" -eq 1 ] &&
   { [ ! -x "$STEAM_STAGING/usr/bin/steam" ] ||
     [ ! -x "$STEAM_STAGING/usr/libexec/vinix-steam/root/usr/bin/bash" ]; }; then
    echo "ERROR: --with-steam needs $STEAM_STAGING/usr/bin/steam and its x86 glibc root" >&2
    echo "Run ./scripts/build-steam-aarch64.sh first." >&2
    exit 1
fi
if [ "$WITH_STEAM" -eq 1 ] &&
   { [ ! -x "$X86_TRANSLATION_STAGING/usr/bin/qemu-i386" ] ||
     [ ! -x "$X86_TRANSLATION_STAGING/usr/bin/qemu-x86_64" ]; }; then
    echo "ERROR: --with-steam needs both x86 translators in $X86_TRANSLATION_STAGING" >&2
    echo "Run ./scripts/build-x86-translation-aarch64.sh --translator-only first." >&2
    exit 1
fi
if [ "$WITH_QEMU_SYSTEM" -eq 1 ] &&
   { [ ! -x "$QEMU_SYSTEM_STAGING/usr/bin/qemu-system-aarch64" ] ||
     [ ! -x "$QEMU_SYSTEM_STAGING/usr/bin/vinix-qemu" ] ||
     [ ! -f "$QEMU_SYSTEM_STAGING/usr/share/qemu/edk2-aarch64-code.fd" ]; }; then
    echo "ERROR: --with-qemu-system needs $QEMU_SYSTEM_STAGING" >&2
    echo "Run ./scripts/build-qemu-system-aarch64.sh first." >&2
    exit 1
fi

if [ "$WITH_ANDROID" -eq 1 ] &&
   { [ ! -x "$ANDROID_STAGING/usr/bin/run-android" ] ||
     [ ! -x "$ANDROID_STAGING/opt/vinix-android-aarch64/lib/ld-musl-aarch64.so.1" ] ||
     [ ! -f "$ANDROID_STAGING/opt/vinix-android-aarch64/art-runtime-manifest.json" ] ||
     [ ! -f "$ANDROID_STAGING/opt/vinix-android-aarch64/bionic-runtime-manifest.json" ] ||
     [ ! -f "$ANDROID_STAGING/opt/vinix-android-aarch64/atl-runtime-manifest.json" ] ||
     [ ! -f "$ANDROID_STAGING/opt/vinix-android-aarch64/usr/lib/libvinix-android-compat.so" ] ||
     [ ! -x "$ANDROID_STAGING/opt/vinix-android-aarch64/usr/bin/android-translation-layer" ]; }; then
    echo "ERROR: --with-android needs $ANDROID_STAGING" >&2
    echo "Run ./scripts/build-android-aarch64.sh --with-calculator first." >&2
    exit 1
fi

if [ "$WITH_ANDROID" -eq 1 ]; then
    python3 - "$SCRIPT_DIR/build-support/android" "$ANDROID_STAGING" <<'PY'
import importlib.util
import json
from pathlib import Path
import sys

support, staging = map(Path, sys.argv[1:])
spec = importlib.util.spec_from_file_location("vinix_art_runtime", support / "art-runtime.py")
assert spec and spec.loader
art = importlib.util.module_from_spec(spec)
spec.loader.exec_module(art)
spec = importlib.util.spec_from_file_location("vinix_android_musl", support / "musl-runtime.py")
assert spec and spec.loader
musl = importlib.util.module_from_spec(spec)
spec.loader.exec_module(musl)
runtime = staging / "opt/vinix-android-aarch64"
verified = art.read_manifest(runtime)
bionic = art.read_bionic_manifest(runtime)
atl = art.read_atl_manifest(runtime)
libc = musl.read_manifest(runtime)
art.validate_atl_art_pair(verified, atl)
manifest = json.loads((runtime / "runtime-manifest.json").read_text())
if (manifest.get("architecture") != "aarch64" or manifest.get("execution") != "native"
        or manifest.get("page_size") != 16384 or manifest.get("art") != verified
        or not verified.get("bootclasspath") or manifest.get("bionic") != bionic
        or manifest.get("atl") != atl or manifest.get("musl") != libc):
    raise SystemExit("--with-android requires the verified native ARM64 Android runtime")
PY
fi

if [ "$WITH_ROBLOX" -eq 1 ]; then
    python3 - "$SCRIPT_DIR/build-support/roblox/build.py" "$ROBLOX_STAGING" "$ANDROID_STAGING" <<'PYROBLOX'
import importlib.util
from pathlib import Path
import sys

builder, staging, android = map(Path, sys.argv[1:])
spec = importlib.util.spec_from_file_location("vinix_roblox_builder", builder)
assert spec and spec.loader
roblox = importlib.util.module_from_spec(spec)
spec.loader.exec_module(roblox)
try:
    roblox.validate_stage(staging, android)
except (OSError, ValueError, RuntimeError) as error:
    raise SystemExit(f"--with-roblox requires a verified ATL launcher stage: {error}\n"
                     "Run ./scripts/build-roblox-aarch64.sh first.")
PYROBLOX
fi

# `package.py` produces the only supported bundle format. Its manifest binds
# the opaque vendor files to identity captured from the target, and wifi-ctl
# repeats that identity check on the M1 before uploading a byte.
echo "==> Building wifi-ctl for aarch64-linux-musl..."
python3 "$SCRIPT_DIR/tools/m1-wifi/compile-v.py" "$BUILD_DIR/wifi-ctl-v.c" --arch arm64
"$LLVM_BIN/clang" --target=aarch64-linux-musl -static -nostdinc -nostdlib \
    -isystem "$CC_SHIM" \
    -isystem "$GCCLIB/include" -isystem "$SYSROOT/usr/include" \
    -iquote "$SCRIPT_DIR/kernel/c" \
    -std=c11 -O2 -fno-stack-protector -Wall -Wextra -Werror \
    "$SYSROOT/usr/lib/crt1.o" "$SYSROOT/usr/lib/crti.o" "$GCCLIB/crtbeginT.o" \
    "$BUILD_DIR/wifi-ctl-v.c" -I"$SCRIPT_DIR/tools/m1-wifi" -fwrapv -fno-strict-aliasing \
    -L"$SYSROOT/usr/lib" -L"$GCCLIB" -lc -lgcc \
    "$GCCLIB/crtend.o" "$SYSROOT/usr/lib/crtn.o" \
    -fuse-ld=lld -B"$LLVM_BIN" \
    -o "$BUILD_DIR/wifi-ctl"
"$LLVM_BIN/llvm-strip" "$BUILD_DIR/wifi-ctl"
echo "    $BUILD_DIR/wifi-ctl ($(file_size "$BUILD_DIR/wifi-ctl") bytes)"

echo "==> Building the desktop init..."
INIT_DEFINES=()
if [ -n "$WIFI_BUNDLE" ]; then
    INIT_DEFINES=(-DVINIX_WIFI_BUNDLE=1)
fi
python3 "$SCRIPT_DIR/build-support/init-aarch64/compile-v.py" desktop "$BUILD_DIR/desktop-init-v.c"
"$LLVM_BIN/clang" --target=aarch64-linux-none -nostdlib -ffreestanding -O2 \
    -fno-stack-protector -fno-builtin -ffunction-sections -fdata-sections -c \
    "${INIT_DEFINES[@]}" -I"$SCRIPT_DIR/build-support/init-aarch64" \
    -o "$BUILD_DIR/desktop-init.o" "$BUILD_DIR/desktop-init-v.c"
# lld is installed as a separate formula, so it is on PATH rather than in
# the llvm keg the other tools come from.
"${LD_LLD:-ld.lld}" -m aarch64elf --nostdlib -static --gc-sections \
    -o "$BUILD_DIR/desktop-init" "$BUILD_DIR/desktop-init.o"

echo "==> Staging the desktop initramfs..."
STAGING="$BUILD_DIR/initramfs-root"
STAGING_CACHE="$BUILD_DIR/initramfs-root.layers"
CONTENT_KEY="$BUILD_DIR/initramfs-root.content-key"
STAGING_CACHE_EXPECTED="$(mktemp "$BUILD_DIR/.initramfs-root.layers.XXXXXX")"
CONTENT_KEY_EXPECTED=""
# An interrupted archive step would otherwise leave a multi-gigabyte partial
# tar in the checkout, where the QEMU host source share picks it up.
DESKTOP_INITRAMFS_TMP=""
DESKTOP_INITRAMFS_GZ_TMP=""
cleanup_desktop_cache_temps() {
    rm -f "$STAGING_CACHE_EXPECTED"
    if [ -n "$CONTENT_KEY_EXPECTED" ]; then
        rm -f "$CONTENT_KEY_EXPECTED"
    fi
    if [ -n "$DESKTOP_INITRAMFS_TMP" ]; then
        rm -f "$DESKTOP_INITRAMFS_TMP"
    fi
    if [ -n "$DESKTOP_INITRAMFS_GZ_TMP" ]; then
        rm -f "$DESKTOP_INITRAMFS_GZ_TMP"
    fi
    release_desktop_build_lock
}
trap cleanup_desktop_cache_temps EXIT
write_staging_cache_manifest > "$STAGING_CACHE_EXPECTED"
REUSE_STAGING=0
if [ "$REFRESH_STAGING" -eq 0 ] &&
   [ -d "$STAGING" ] && [ -f "$STAGING_CACHE" ] &&
   cmp -s "$STAGING_CACHE_EXPECTED" "$STAGING_CACHE" &&
   [ -x "$STAGING/bin/busybox" ] && [ -x "$STAGING/usr/bin/vim" ]; then
    REUSE_STAGING=1
    echo "    reusing staged base/application layers"
else
    rm -f "$STAGING_CACHE" "$CONTENT_KEY"
    rm -rf "$STAGING"
    mkdir -p "$STAGING"
fi

# The large package closures below are immutable build outputs. Once their
# generation manifest matches, preserve the assembled tree and only refresh
# the desktop-owned files later in this script. This turns Blender, Minecraft,
# Wine/x86, Hyprland and the base userland from per-launch copies into one-time
# staging work until one of those layer builders runs again.
if [ "$REUSE_STAGING" -eq 0 ]; then
    # Chromium is a 690 MiB closure the image does not need: `pkg install chromium`
    # fetches the same Alpine build onto a running system. Stage it only when a
    # bootable image has to carry the browser already installed, and stage it first
    # because its dependency closure repeats much of the X11 and GTK stack that the
    # layers below are the qualified copy of.
    if [ "$WITH_CHROMIUM" -eq 1 ]; then
        echo "    staging Chromium"
        merge_staging_tree "$CHROMIUM_STAGING"
    fi
    # LibreOffice is a 900 MiB closure for the same reason, and it repeats the same
    # GTK, X11 and font stack. Stage it before them, so the layers below stay the
    # qualified copy of everything the suite shares with the browsers.
    if [ "$WITH_LIBREOFFICE" -eq 1 ]; then
        echo "    staging LibreOffice"
        merge_staging_tree "$LIBREOFFICE_STAGING"
    fi
    if [ "$COMPACT_INITRAMFS" -eq 1 ]; then
        echo "    compact image: staging BusyBox, Python, Git, GCC and Firefox"
        if [ ! -f "$DEVTOOLS_ARCHIVE" ]; then
            echo "ERROR: compact desktop needs $DEVTOOLS_ARCHIVE" >&2
            echo "Run ./scripts/build-userland-aarch64.sh first." >&2
            exit 1
        fi
        tar xf "$BASE_INITRAMFS" -C "$STAGING" ./bin/busybox
        tar xf "$DEVTOOLS_ARCHIVE" -C "$STAGING"

        # The terminal runs zsh, which the developer-tools archive does not carry.
        # Take the shell, its modules and its configuration straight out of the
        # sysroot the desktop was compiled against; the base archive stores the
        # command as a hard link to a versioned name, which cannot be extracted on
        # its own. libcap is zsh's own NEEDED library and is in neither archive,
        # so without it the terminal only ever printed a loader error. V probes
        # `ldd --version` to select its musl builtins; keep that tiny helper too,
        # otherwise ordinary debug builds incorrectly emit glibc backtrace calls.
        for zsh_path in bin/zsh bin/zsh-* etc/zsh usr/lib/zsh usr/share/zsh \
            usr/lib/libcap.so.2 usr/lib/libcap.so.2.* \
            usr/bin/ldd \
            root/.zshrc root/.oh-my-zsh; do
            for zsh_source in "$SYSROOT"/$zsh_path; do
                [ -e "$zsh_source" ] || continue
                zsh_relative="${zsh_source#"$SYSROOT/"}"
                mkdir -p "$STAGING/$(dirname "$zsh_relative")"
                rm -rf "${STAGING:?}/$zsh_relative"
                cp -a "$zsh_source" "$STAGING/$zsh_relative"
            done
        done
        merge_staging_tree "$X11_STAGING"
        merge_staging_tree "$FIREFOX_STAGING"
        if [ "$WITHOUT_FIREFOX" -eq 1 ]; then
            # The browser's own files: 220 MiB of a release ISO. Its runtime --
            # GTK, the media codecs, fonts and the TLS bundle -- stays for the
            # other GTK applications, and the first-run app page offers the
            # browser itself through pkg.
            echo "    leaving Firefox itself out (--without-firefox)"
            rm -rf "$STAGING/usr/lib/firefox-esr" "$STAGING/usr/lib/firefox" \
                "$STAGING/usr/bin/firefox-esr" "$STAGING/usr/bin/firefox" \
                "$STAGING"/usr/share/applications/firefox*.desktop \
                "$STAGING"/usr/share/icons/hicolor/*/apps/firefox* \
                "$STAGING"/usr/share/metainfo/*firefox*
        fi
        merge_staging_tree "$NETWORK_TOOLS_STAGING"
        merge_staging_tree "$PYTHON_STAGING"

        # GCC's lto-dump is a standalone compiler-internals inspection utility,
        # not part of compiling or linking programs. Keeping its second 32 MiB
        # copy of the LTO frontend can push a Word-enabled compact initramfs above
        # FAT32's 4 GiB per-file limit, so omit it from the bootable image.
        rm -f "$STAGING/usr/bin/lto-dump"

        # The compact image promises a native C toolchain for rebuilding V
        # programs in the guest. C++ and link-time optimisation are separate
        # compiler frontends and together cost about 70 MiB before compression.
        # Neither is used by vinix-desktop-build, so leave them in full images
        # while keeping the ESP-bound image small enough to deploy atomically.
        rm -f \
            "$STAGING/usr/bin/g++" \
            "$STAGING/usr/bin/c++" \
            "$STAGING/usr/bin/aarch64-alpine-linux-musl-g++" \
            "$STAGING/usr/bin/aarch64-alpine-linux-musl-c++"
        rm -f \
            "$STAGING"/usr/libexec/gcc/*/*/cc1plus \
            "$STAGING"/usr/libexec/gcc/*/*/lto1 \
            "$STAGING"/usr/libexec/gcc/*/*/lto-wrapper

        # The full userland has GNU coreutils, which replaces some of Alpine's
        # BusyBox links.  Compact images omit that package, so make its complete
        # everyday BusyBox command set available explicitly instead of exposing
        # only the few helpers needed by the desktop launchers.  This keeps df,
        # ls, du, find-like shell tooling, archive tools, and process/filesystem
        # inspection commands preinstalled without bringing the GNU package in.
        for applet in \
            ash awk basename cat chgrp chmod chown cmp comm cp cut date dd df dirname \
            dmesg du echo env expr false find grep head hostname id kill ln ls mkdir \
            mknod mktemp mount mv ping printf ps pwd readlink rm rmdir sed seq sh \
            sleep sort stat sync tail tar tee touch tr true uname uniq wc which \
            whoami xargs; do
            ln -sf busybox "$STAGING/bin/$applet"
        done

        # The power commands live in /sbin on a full userland, which compact images
        # do not stage. BusyBox dispatches on the name it is called by, so a link
        # under either directory is the same applet.
        mkdir -p "$STAGING/sbin"
        for applet in halt poweroff reboot; do
            ln -sf /bin/busybox "$STAGING/sbin/$applet"
        done

    else
        tar xf "$BASE_INITRAMFS" -C "$STAGING"
        # A base userland built with VINIX_ALPINE_DEVTOOLS=0 deliberately
        # omits GCC, but the desktop still promises an in-guest development
        # environment. The separately published developer-tools layer is the
        # authoritative fallback and is already part of this staging cache's
        # generation key. Avoid overlaying it when the base already carries
        # GCC, since that keeps the usual full-image path byte-for-byte stable.
        if [ ! -x "$STAGING/usr/bin/gcc" ]; then
            if [ ! -f "$DEVTOOLS_ARCHIVE" ]; then
                echo "ERROR: desktop needs GCC, but neither the base userland nor $DEVTOOLS_ARCHIVE provides it" >&2
                echo "Run ./scripts/build-userland-aarch64.sh first." >&2
                exit 1
            fi
            echo "    base image omits GCC; staging the developer-tools layer"
            tar xf "$DEVTOOLS_ARCHIVE" -C "$STAGING"
        fi
        # Firefox is another independently published closure. A base image
        # made before (or without) that optional integration is still a valid
        # userland input, so recover from the dedicated layer before applying
        # the newer network/runtime overlays below.
        if ! { [ -x "$STAGING/usr/lib/firefox-esr/firefox-esr" ] &&
               [ -x "$STAGING/usr/bin/firefox-esr" ]; } &&
           ! { [ -x "$STAGING/usr/lib/firefox/firefox" ] &&
               [ -x "$STAGING/usr/bin/firefox" ]; }; then
            if ! { [ -x "$FIREFOX_STAGING/usr/lib/firefox-esr/firefox-esr" ] &&
                   [ -x "$FIREFOX_STAGING/usr/bin/firefox-esr" ]; } &&
               ! { [ -x "$FIREFOX_STAGING/usr/lib/firefox/firefox" ] &&
                   [ -x "$FIREFOX_STAGING/usr/bin/firefox" ]; }; then
                echo "ERROR: desktop base omits Firefox and its staging layer is incomplete: $FIREFOX_STAGING" >&2
                echo "Run ./scripts/build-firefox-aarch64.sh first." >&2
                exit 1
            fi
            echo "    base image omits Firefox; staging the Firefox layer"
            merge_staging_tree "$FIREFOX_STAGING"
        fi
        # The base archive may predate package support. Always refresh this small
        # layer so the terminal gets pkg/apk without rebuilding the full userland.
        merge_staging_tree "$NETWORK_TOOLS_STAGING"
    fi

    # Always take V from its own pinned layer. The base userland may have been
    # assembled before that layer was rebuilt, while a compact image never
    # extracts the full base tree at all.
    echo "    staging the native V compiler"
    merge_staging_tree "$VLANG_STAGING"

    if [ "$COMPACT_INITRAMFS" -eq 0 ] &&
       [ -x "$BLENDER_NATIVE_STAGING/usr/libexec/vinix-blender-native" ]; then
        echo "==> Staging native Blender GHOST executable"
        merge_staging_tree "$BLENDER_NATIVE_STAGING"
    fi

    # Full images pick up locally built optional application layers even when the
    # base archive predates them. Compact images deliberately stop at the GPU,
    # desktop and Firefox qualification closure unless one optional layer is
    # explicitly requested.
    if { [ "$COMPACT_INITRAMFS" -eq 0 ] || [ "$WITH_MINECRAFT" -eq 1 ]; } &&
       [ -x "$MINECRAFT_STAGING/usr/bin/minecraft" ]; then
        echo "==> Staging Minecraft runtime"
        merge_staging_tree "$MINECRAFT_STAGING"
    fi

    if [ -x "$DOOM_STAGING/usr/bin/chocolate-doom" ]; then
        echo "==> Staging Chocolate Doom"
        merge_staging_tree "$DOOM_STAGING"
    fi

    # The engine's private Mesa and LLVM, and whatever game data was staged
    # with it: hundreds of megabytes a compact image has to ask for.
    if { [ "$COMPACT_INITRAMFS" -eq 0 ] || [ "$WITH_OPENGOTHIC" -eq 1 ]; } &&
       [ -x "$OPENGOTHIC_STAGING/opt/opengothic/Gothic2Notr" ]; then
        echo "==> Staging OpenGothic"
        merge_staging_tree "$OPENGOTHIC_STAGING"
    fi

    # The translator is architecture-isolated: its x86-64 libraries live below
    # /usr/libexec, so they cannot replace native ARM64 libraries.
    if { [ "$COMPACT_INITRAMFS" -eq 0 ] || [ "$WITH_X86_TRANSLATION" -eq 1 ] || [ "$WITH_STEAM" -eq 1 ]; } &&
       [ -x "$X86_TRANSLATION_STAGING/usr/bin/qemu-x86_64" ]; then
        echo "==> Staging x86-64 translation layer"
        merge_staging_tree "$X86_TRANSLATION_STAGING"

        # Wine's desktop integration invokes the native shared-mime-info updater.
        # Wine may add its private x86 library directory to the child environment,
        # which makes the AArch64 loader try to relocate guest GLib libraries.
        # Keep the real helper behind the same environment-sanitizing trampoline
        # used for ntlm_auth.
        if [ -x "$STAGING/usr/bin/update-mime-database" ]; then
            mkdir -p "$STAGING/usr/libexec/vinix-native-helpers"
            mv "$STAGING/usr/bin/update-mime-database" \
                "$STAGING/usr/libexec/vinix-native-helpers/update-mime-database"
            install -m755 \
                "$SCRIPT_DIR/build-support/x86-translation/run-native-ntlm-auth" \
                "$STAGING/usr/bin/update-mime-database"
        fi

        # Office populates this disposable cache with generated names that can
        # exceed ustar's pathname limit after the prefix is exercised. It is not
        # application state and Word recreates it when needed, so keep it out of
        # the boot image without modifying the source prefix.
        office_web_cache="$STAGING/root/.wine-word2013-x86_64/drive_c/users/root/AppData/Local/Microsoft/Office/15.0/WebServiceCache"
        if [ -d "$office_web_cache" ]; then
            rm -rf "$office_web_cache"
        fi
        office_vsta_metadata="$STAGING/root/.wine-word2013-x86_64/drive_c/Program Files (x86)/Common Files/Microsoft Shared/VSTA/AppInfoDocument/Microsoft.VisualStudio.Tools.Office.AppInfoDocument/Microsoft.VisualStudio.Tools.Office.AppInfoDocument.v9.0.dll"
        if [ -f "$office_vsta_metadata" ]; then
            rm -f "$office_vsta_metadata"
        fi
    fi

    # Steam is Valve's x86 glibc client on the same translators, with its own
    # Debian root below /usr/libexec; nothing of it replaces a native file.
    if [ "$WITH_STEAM" -eq 1 ]; then
        echo "==> Staging Steam"
        merge_staging_tree "$STEAM_STAGING"
        # Valve's runtime scripts start with #!/bin/bash. An image without a
        # bash of its own gets one that runs the Debian bash through the
        # translator; an installed native bash is left alone.
        if [ ! -e "$STAGING/bin/bash" ] && [ ! -e "$STAGING/usr/bin/bash" ]; then
            install -m755 "$STEAM_STAGING/usr/libexec/vinix-steam/bash" \
                "$STAGING/bin/bash"
        fi
    fi

    if [ "$WITH_QEMU_SYSTEM" -eq 1 ]; then
        echo "==> Staging native QEMU system emulator"
        merge_staging_tree "$QEMU_SYSTEM_STAGING"
    fi
    if [ "$WITH_ANDROID" -eq 1 ]; then
        echo "==> Staging Android Translation Layer"
        merge_staging_tree "$ANDROID_STAGING"
        # ART initializes java.lang.System through libc's getpwuid_r. Compact
        # images otherwise omit the account database, which aborts Java before
        # the APK starts. Preserve any accounts already supplied by the image.
        mkdir -p "$STAGING/etc"
        for account_file in passwd group; do
            if [ ! -e "$STAGING/etc/$account_file" ]; then
                if [ -f "$SYSROOT/etc/$account_file" ]; then
                    install -m644 "$SYSROOT/etc/$account_file" "$STAGING/etc/$account_file"
                elif [ "$account_file" = passwd ]; then
                    printf '%s\n' 'root:x:0:0:root:/root:/bin/sh' > "$STAGING/etc/passwd"
                else
                    printf '%s\n' 'root:x:0:' > "$STAGING/etc/group"
                fi
            fi
        done
    fi

    if [ "$WITH_ROBLOX" -eq 1 ]; then
        echo "==> Staging Roblox ATL launchers"
        merge_staging_tree "$ROBLOX_STAGING"
    fi

    if [ "$WITH_DOTA2" -eq 1 ]; then
        # This self-contained layer supplies the patched native translator at
        # the kernel's standard helper path and its private glibc game root.
        # Apply it after other layers that also supply the x86-64 translator.
        echo "==> Staging the Linux Dota 2 runtime"
        merge_staging_tree "$DOTA2_STAGING"
    fi

    # Hyprland is an optional build layer because its patched Aquamarine library
    # is produced in the native ARM64 build VM. Its dedicated launcher selects it
    # at boot; simply having the layer installed leaves the native desktop first.
    if [ "$COMPACT_INITRAMFS" -eq 0 ] && [ -x "$HYPRLAND_STAGING/usr/bin/start-hyprland-vinix" ]; then
        echo "==> Staging Hyprland and the Vinix Aquamarine backend"
        merge_staging_tree "$HYPRLAND_STAGING"
    fi

    # Overlay Mesa last so Xorg, Firefox and native EGL applications all use the
    # exact userspace built for Vinix's Asahi kernel UAPI rather than Alpine's
    # unrelated Mesa build.
    #
    # Only when this image is actually for Apple hardware. That Mesa is built for a
    # real GPU and carries no llvmpipe at all -- its only software rasteriser is
    # softpipe, which stops at OpenGL 3.3. Overlaying it on a QEMU image therefore
    # replaces a 4.5-capable software renderer with a 3.3-capable one, and anything
    # needing more than 3.3 stops working: native Blender asks for a 4.3 core
    # context and gets EGL_BAD_MATCH, having rendered fine before. Selecting it
    # from the mere presence of the staging directory is what made that happen
    # silently, with no commit to point at.
    if [ "$GPU_DESKTOP_BUILT" -eq 1 ] && [ "$WITH_ASAHI_GPU" -eq 1 ]; then
        merge_staging_tree "$ASAHI_STAGING"

        # The X11 layer supplies a generic LLVM-backed Mesa closure for QEMU.
        # The hardware image replaces it with the qualified Asahi build above,
        # which has its own Gallium and no LLVM dependency. Keeping both copies
        # wastes more than 190 MiB and makes the compressed image too large for
        # the M1's 500 MiB ESP. Remove only the generic rendering artifacts; the
        # X server and the Asahi /usr/lib/dri driver remain intact.
        rm -rf "${STAGING:?}/usr/lib/xorg/modules/dri"
        rm -f \
            "$STAGING"/usr/lib/libLLVM-*.so* \
            "$STAGING"/usr/lib/libOSMesa.so* \
            "$STAGING"/usr/lib/libxatracker.so* \
            "$STAGING"/usr/lib/libGLU.so*
    elif [ -d "$X11_STAGING/usr/lib/xorg/modules/dri" ]; then
        # Nothing else fills /usr/lib/dri: the Apple overlay was the only thing
        # putting drivers there, so skipping it leaves Mesa with none at all. The
        # X11 layer already stages the generic Alpine set, and that one does carry
        # llvmpipe, so software OpenGL reaches 4.5 rather than softpipe's 3.3.
        echo "==> Staging the generic Mesa DRI drivers"
        mkdir -p "$STAGING/usr/lib/dri"
        # Only the software entries. That directory is 49 names for one 27 MiB
        # object, 48 of them links, and the pass below turns every link into a real
        # file -- copying all of them would add 1.3 GiB of the same driver. A
        # machine with no GPU needs exactly these.
        cp -a "$X11_STAGING/usr/lib/xorg/modules/dri/libgallium_dri.so" \
            "$STAGING/usr/lib/dri/"
        for software_driver in swrast_dri.so kms_swrast_dri.so; do
            cp -a "$X11_STAGING/usr/lib/xorg/modules/dri/$software_driver" \
                "$STAGING/usr/lib/dri/" 2>/dev/null || true
        done
        # libEGL names its Gallium by version in DT_NEEDED, and the Apple overlay
        # was the only thing supplying one. Take the X11 sysroot's, which is the
        # build these drivers belong to.
        for gallium in "$GPU_SYSROOT"/usr/lib/libgallium-*.so; do
            [ -f "$gallium" ] || continue
            cp -a "$gallium" "$STAGING/usr/lib/"
        done
        # llvmpipe is a JIT, so that Gallium names libLLVM in DT_NEEDED. The Apple
        # build has no llvmpipe and so never needed it, which is why a compact
        # image carries no LLVM at all. It is 144 MiB and it is what buys OpenGL
        # 4.5 instead of softpipe's 3.3.
        for llvm in "$SYSROOT"/usr/lib/libLLVM.so.*; do
            [ -f "$llvm" ] || continue
            cp -a "$llvm" "$STAGING/usr/lib/"
        done
    fi
    # Hyprland edge uses libstdc++ formatting entry points newer than the base and
    # Mesa 25 layers. Keep its backward-compatible C++ runtime as the final copy;
    # use regular files because Vinix's musl loader opens DT_NEEDED objects with
    # O_NOFOLLOW.
    if [ "$COMPACT_INITRAMFS" -eq 0 ] && [ -x "$HYPRLAND_STAGING/usr/bin/start-hyprland-vinix" ]; then
        for runtime in libstdc++.so.6 libgcc_s.so.1; do
            if [ -f "$HYPRLAND_STAGING/usr/lib/$runtime" ]; then
                rm -f "$STAGING/usr/lib/$runtime"
                cp -L "$HYPRLAND_STAGING/usr/lib/$runtime" "$STAGING/usr/lib/$runtime"
            fi
        done
    fi

    if [ "$WITH_CHROMIUM" -eq 1 ]; then
        # Firefox comes from a newer Alpine branch than Chromium and therefore
        # owns the image-wide GTK/GLib/NSS stack. Chromium 136 crashes before
        # mapping a window when that mixed closure is loaded underneath it, so
        # retain the shared libraries from Chromium's resolved package set in
        # a private directory selected only by run-chromium.
        chromium_runtime="$STAGING/usr/lib/chromium/vinix-runtime"
        rm -rf "$chromium_runtime"
        mkdir -p "$chromium_runtime"
        cp -a "$CHROMIUM_STAGING"/usr/lib/*.so* "$chromium_runtime/"
        install -m755 "$CHROMIUM_STAGING/lib/ld-musl-aarch64.so.1" \
            "$STAGING/lib/ld-chromium.so.1"
        python3 "$SCRIPT_DIR/build-support/patch-elf-interpreter.py" \
            "$STAGING/usr/lib/chromium/chrome" \
            /lib/ld-musl-aarch64.so.1 /lib/ld-chromium.so.1
        touch "$chromium_runtime/.complete"
    fi
fi

# These files are owned by this checkout, not by a compiled staging layer, so
# refresh them even when the expensive tree above is reused.
if [ "$COMPACT_INITRAMFS" -eq 0 ] && [ -x "$HYPRLAND_STAGING/usr/bin/start-hyprland-vinix" ]; then
    install -m755 "$SCRIPT_DIR/build-support/hyprland/start-hyprland-vinix" \
        "$STAGING/usr/bin/start-hyprland-vinix"
    install -m644 "$SCRIPT_DIR/build-support/hyprland/foot.ini" \
        "$STAGING/root/.config/foot/foot.ini"
fi
if [ "$GPU_DESKTOP_BUILT" -eq 1 ] && [ "$WITH_ASAHI_GPU" -eq 1 ]; then
    # The Mesa layer carries the compiled test and a convenience copy of its
    # source, but that layer can legitimately predate this checkout.  Keep the
    # source used by --rebuild beside the current smoke launcher so hardware
    # tests never rebuild an older test program after a cached image build.
    mkdir -p "$STAGING/usr/share/examples/gl-triangle"
    install -m755 "$SCRIPT_DIR/gl-triangle/run-m1-agx-smoke" \
        "$STAGING/usr/bin/run-m1-agx-smoke"
    python3 "$SCRIPT_DIR/gl-triangle/stage.py" \
        "$STAGING/usr/share/examples/gl-triangle" --arch arm64
fi
mkdir -p "$STAGING/sbin" "$STAGING/usr/bin" "$STAGING/usr/share/vinix" \
    "$STAGING/root" "$STAGING/dev" "$STAGING/proc" "$STAGING/sys" "$STAGING/tmp" \
    "$STAGING/run"
# The iOS compatibility layer is staged by ./scripts/build-ios-aarch64.sh.
if [ -x "$IOS_STAGING/usr/bin/run-ios" ]; then
    install -m755 "$IOS_STAGING/usr/bin/run-ios" "$STAGING/usr/bin/run-ios"
    ln -sf run-ios "$STAGING/usr/bin/vinix-ios-calculator"
    mkdir -p "$STAGING/usr/share/vinix/ios"
    cp -R "$IOS_STAGING/usr/share/vinix/ios/Calculator.app" "$STAGING/usr/share/vinix/ios/"
    if [ -f "$IOS_STAGING/usr/share/vinix/ios/NumberTileGame.app/NumberTileGame" ]; then
        cp -R "$IOS_STAGING/usr/share/vinix/ios/NumberTileGame.app" "$STAGING/usr/share/vinix/ios/"
        ln -sf run-ios "$STAGING/usr/bin/vinix-ios-2048"
    fi
fi
mkdir -p "$STAGING/root/.config/GIMP/2.10" "$STAGING/root/.cache"
# Package layers unpacked from .apk files can leave the package's own control
# files at the root of the image.
rm -f "$STAGING/.PKGINFO" "$STAGING/.INSTALL" "$STAGING"/.SIGN.* \
    "$STAGING"/.pre-* "$STAGING"/.post-* "$STAGING"/.trigger*
chmod 1777 "$STAGING/tmp"

# The compositor loads its own app artwork rather than depending on whichever
# icon theme happens to accompany an optional application package.
mkdir -p "$STAGING/usr/share/vinix/icons"
install -m644 "$SCRIPT_DIR/desktop/assets/chromium.qoi" \
    "$STAGING/usr/share/vinix/icons/chromium.qoi"
install -m644 "$SCRIPT_DIR/desktop/assets/firefox.qoi" \
    "$STAGING/usr/share/vinix/icons/firefox.qoi"
install -m644 "$SCRIPT_DIR/desktop/assets/blender.qoi" \
    "$STAGING/usr/share/vinix/icons/blender.qoi"
install -m644 "$SCRIPT_DIR/desktop/assets/minecraft.qoi" \
    "$STAGING/usr/share/vinix/icons/minecraft.qoi"

for app_icon in terminal settings activity calculator disk_usage editor files clock calendar capture doom steam; do
    install -m644 "$SCRIPT_DIR/desktop/assets/${app_icon}.qoi" \
        "$STAGING/usr/share/vinix/icons/${app_icon}.qoi"
done
# Keep the display handoff pieces in sync with the desktop source even when the
# full base userland predates them. The bridge is a cross-compiled executable;
# package/Firefox launchers and policy files can be installed directly from
# source.
# Refresh security utilities even with cached staging or a compact root.
python3 "$SCRIPT_DIR/build-support/security-tools/stage.py" --arch aarch64 --staging "$STAGING"
"$SCRIPT_DIR/build-support/stage-uname.sh" "$STAGING"
install -m755 "$SCRIPT_DIR/build-support/vinix-pkg" "$STAGING/usr/bin/pkg"
mkdir -p "$STAGING/usr/libexec/vinix-minecraft"
for minecraft_support in \
    fetch-minecraft.py run-minecraft minecraft-login minecraft-xinitrc; do
    install -m755 "$SCRIPT_DIR/build-support/minecraft/$minecraft_support" \
        "$STAGING/usr/libexec/vinix-minecraft/$minecraft_support"
done
install -m755 "$SCRIPT_DIR/build-support/java-cacerts.py" \
    "$STAGING/usr/libexec/vinix-minecraft/java-cacerts.py"
install -m755 "$SCRIPT_DIR/build-support/xorg-server/startx" "$STAGING/usr/bin/startx"
install -m755 "$X11_STAGING/usr/bin/vinix-xinput" "$STAGING/usr/bin/vinix-xinput"
install -m755 "$X11_STAGING/usr/bin/vinix-wine-host" "$STAGING/usr/bin/vinix-wine-host"
# Xvfb-glx needs the X11 layer's legacy GLX Mesa, while OBS creates its video
# context through that layer's EGL Mesa on the same display. The full desktop
# also carries native Mesa. Keep the X11 clients on the tested software stack.
# install follows staging symlinks for Vinix's O_NOFOLLOW loader.
x11_gl_runtime="$STAGING/usr/lib/vinix-x11-software"
rm -rf "$x11_gl_runtime"
if [ "$WITH_ASAHI_GPU" -eq 0 ] &&
   [ -f "$X11_STAGING/usr/lib/libGL.so.1" ] &&
   [ -f "$X11_STAGING/usr/lib/libglapi.so.0" ] &&
   [ -f "$X11_STAGING/usr/lib/libEGL.so.1" ] &&
   [ -f "$X11_STAGING/usr/lib/libgbm.so.1" ]; then
    mkdir -p "$x11_gl_runtime/egl"
    install -m755 "$X11_STAGING/usr/lib/libGL.so.1" "$x11_gl_runtime/libGL.so.1"
    install -m755 "$X11_STAGING/usr/lib/libglapi.so.0" "$x11_gl_runtime/libglapi.so.0"
    install -m755 "$X11_STAGING/usr/lib/libEGL.so.1" "$x11_gl_runtime/egl/libEGL.so.1"
    install -m755 "$X11_STAGING/usr/lib/libgbm.so.1" "$x11_gl_runtime/egl/libgbm.so.1"
fi
install -m755 "$SCRIPT_DIR/build-support/firefox/run-firefox" "$STAGING/usr/bin/run-firefox"
install -m755 "$SCRIPT_DIR/build-support/gimp/run-gimp" "$STAGING/usr/bin/run-gimp"
install -m755 "$SCRIPT_DIR/build-support/obs/run-obs" "$STAGING/usr/bin/run-obs"
"$LLVM_BIN/clang" --target=aarch64-linux-musl -shared -fPIC -nostdlib \
    -fuse-ld=lld "$SCRIPT_DIR/build-support/obs/compat.S" \
    -o "$STAGING/usr/lib/vinix-obs-compat.so"
install -m755 "$SCRIPT_DIR/build-support/doom/run-doom" "$STAGING/usr/bin/run-doom"
install -m755 "$SCRIPT_DIR/build-support/libreoffice/run-libreoffice" \
    "$STAGING/usr/bin/run-libreoffice"
mkdir -p "$STAGING/etc/libreoffice"
install -m644 "$SCRIPT_DIR/build-support/libreoffice/vinix-registrymodifications.xcu" \
    "$STAGING/etc/libreoffice/vinix-registrymodifications.xcu"
install -m644 "$SCRIPT_DIR/build-support/libreoffice/welcome.fodt" \
    "$STAGING/usr/share/vinix/libreoffice-welcome.fodt"
install -m644 "$SCRIPT_DIR/build-support/libreoffice/welcome.fodt" \
    "$STAGING/root/libreoffice-welcome.fodt"
mkdir -p "$STAGING/etc/gimp/2.0"
install -m644 "$SCRIPT_DIR/build-support/gimp/vinix-gimprc" \
    "$STAGING/etc/gimp/2.0/vinix-gimprc"
install -m644 "$SCRIPT_DIR/build-support/gimp/vinix-sessionrc" \
    "$STAGING/etc/gimp/2.0/vinix-sessionrc"
install -m644 "$SCRIPT_DIR/tests/browsers/firefox-smoke.html" \
    "$STAGING/usr/share/vinix/firefox-smoke.html"
install -m644 "$SCRIPT_DIR/tests/browsers/firefox-smoke.html" "$STAGING/root/firefox-smoke.html"
mkdir -p "$STAGING/etc/firefox/policies"
install -m644 "$SCRIPT_DIR/build-support/firefox/policies.json" \
    "$STAGING/etc/firefox/policies/policies.json"
# `pkg install firefox` gives an apk-installed browser the same defaults.
mkdir -p "$STAGING/usr/share/vinix/firefox"
install -m644 "$SCRIPT_DIR/build-support/firefox/vinix.js" \
    "$STAGING/usr/share/vinix/firefox/vinix.js"
install -m755 "$SCRIPT_DIR/build-support/chromium/run-chromium" "$STAGING/usr/bin/run-chromium"
# Keep the small launcher current even when the cached native V layer is reused.
install -m755 "$SCRIPT_DIR/build-support/v-command" "$STAGING/usr/bin/v"
install -m755 "$SCRIPT_DIR/build-support/vinix-desktop-build" \
    "$STAGING/usr/bin/vinix-desktop-build"
install -m755 "$SCRIPT_DIR/build-support/vinix-desktop-reload" \
    "$STAGING/usr/bin/vinix-desktop-reload"
install -m755 "$SCRIPT_DIR/build-support/vinix-host-sync" \
    "$STAGING/usr/bin/vinix-host-sync"
# The release this image is, for the desktop to compare with the newest one
# vinix-os.org names (build-support/vinix-version-check). scripts/deploy-iso.sh sets
# VINIX_RELEASE; any other build is a development image and does not ask.
mkdir -p "$STAGING/usr/libexec"
install -m755 "$SCRIPT_DIR/build-support/vinix-version-check" \
    "$STAGING/usr/libexec/vinix-version-check"
if [ -n "${VINIX_RELEASE:-}" ]; then
    printf '%s\n' "$VINIX_RELEASE" > "$STAGING/etc/vinix-release"
else
    rm -f "$STAGING/etc/vinix-release"
fi
install -m644 "$SCRIPT_DIR/tests/browsers/chromium-smoke.html" \
    "$STAGING/usr/share/vinix/chromium-smoke.html"
install -m755 "$SCRIPT_DIR/tests/packages/x-window-check.py" \
    "$STAGING/usr/share/vinix/x-window-check.py"
install -m644 "$SCRIPT_DIR/tests/browsers/chromium-smoke.html" "$STAGING/root/chromium-smoke.html"
mkdir -p "$STAGING/etc/chromium/policies/managed"
install -m644 "$SCRIPT_DIR/build-support/chromium/policies.json" \
    "$STAGING/etc/chromium/policies/managed/vinix.json"

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

if [ ! -x "$STAGING/bin/busybox" ] || [ ! -x "$STAGING/usr/bin/vim" ]; then
    echo "ERROR: base userland has no executable /bin/busybox or /usr/bin/vim" >&2
    exit 1
fi
if [ ! -x "$STAGING/bin/zsh" ]; then
    echo "ERROR: desktop image has no executable /bin/zsh" >&2
    exit 1
fi
# Package overlays carry Alpine loaders; restore the optimized default after them.
echo "==> Installing Vinix's optimized musl allocator..."
python3 "$SCRIPT_DIR/build-support/musl/stage.py" --arch aarch64 --staging "$STAGING"

# A staged command whose NEEDED library was left behind still looks correct
# here: it is present and executable, and only fails in the guest, as a loader
# error in whatever window started it. Resolve zsh's own dependencies against
# the tree about to be packed instead.
if [ -x "$LLVM_BIN/llvm-readelf" ]; then
    for needed in $("$LLVM_BIN/llvm-readelf" -d "$STAGING/bin/zsh" 2>/dev/null |
        sed -n 's/.*Shared library: \[\(.*\)\]/\1/p'); do
        if [ ! -e "$STAGING/usr/lib/$needed" ] && [ ! -e "$STAGING/lib/$needed" ]; then
            echo "ERROR: desktop image has no $needed, which /bin/zsh needs" >&2
            exit 1
        fi
    done
fi
if [ ! -x "$STAGING/usr/bin/pkg" ] || [ ! -x "$STAGING/sbin/apk" ]; then
    echo "ERROR: desktop image is missing pkg or apk" >&2
    exit 1
fi
for development_path in \
    usr/bin/v usr/lib/vlang/v usr/bin/gcc usr/bin/tcc \
    usr/bin/vinix-desktop-build usr/bin/vinix-desktop-reload \
    usr/bin/vinix-host-sync; do
    if [ ! -x "$STAGING/$development_path" ]; then
        echo "ERROR: desktop development environment is missing /$development_path" >&2
        exit 1
    fi
done
for development_file in usr/lib/vlang/cmd/v/v.v usr/lib/libtcc.so; do
    if [ ! -f "$STAGING/$development_file" ]; then
        echo "ERROR: desktop development environment is missing /$development_file" >&2
        exit 1
    fi
done
for runtime_path in usr/bin/Xorg usr/bin/Xvfb usr/bin/startx usr/bin/vinix-xinput usr/bin/vinix-wine-host usr/bin/run-firefox usr/bin/run-gimp usr/bin/run-obs usr/bin/run-chromium usr/bin/run-libreoffice; do
    if [ ! -x "$STAGING/$runtime_path" ]; then
        echo "ERROR: desktop hosted-X11 runtime is missing /$runtime_path" >&2
        echo "Run ./scripts/build-x11-aarch64.sh and ./scripts/build-firefox-aarch64.sh, then rebuild the desktop." >&2
        exit 1
    fi
done
if [ ! -f "$STAGING/usr/lib/vinix-obs-compat.so" ]; then
    echo "ERROR: OBS compatibility library is missing" >&2
    exit 1
fi
if [ "$WITHOUT_FIREFOX" -eq 1 ]; then
    if [ "$firefox_app_found" -ne 0 ]; then
        echo "ERROR: --without-firefox image still has a Firefox application directory" >&2
        exit 1
    fi
elif [ "$firefox_app_found" -ne 1 ]; then
    echo "ERROR: desktop image has no Firefox application directory" >&2
    echo "Run ./scripts/build-firefox-aarch64.sh and ./scripts/build-userland-aarch64.sh first." >&2
    exit 1
fi
if [ "$WITHOUT_FIREFOX" -eq 0 ] &&
   ! { [ -x "$STAGING/usr/lib/firefox-esr/firefox-esr" ] &&
       [ -x "$STAGING/usr/bin/firefox-esr" ]; } &&
   ! { [ -x "$STAGING/usr/lib/firefox/firefox" ] &&
       [ -x "$STAGING/usr/bin/firefox" ]; }; then
    echo "ERROR: desktop image has no complete Firefox executable pair" >&2
    echo "Run ./scripts/build-firefox-aarch64.sh and ./scripts/build-userland-aarch64.sh first." >&2
    exit 1
fi
if [ "$COMPACT_INITRAMFS" -eq 1 ]; then
    for command_path in bin/sh bin/zsh bin/id bin/sed bin/mkdir bin/sleep bin/df bin/du bin/ls bin/tar usr/bin/pkg sbin/apk usr/bin/vim usr/bin/python3 usr/bin/git usr/bin/Xorg usr/bin/Xvfb usr/bin/startx usr/bin/vinix-xinput usr/bin/vinix-wine-host usr/bin/run-firefox usr/bin/run-gimp usr/bin/run-obs usr/bin/run-chromium usr/bin/run-libreoffice usr/libexec/vinix-minecraft/fetch-minecraft.py usr/bin/gcc usr/bin/tcc usr/bin/ldd usr/bin/v usr/bin/vinix-desktop-build usr/bin/vinix-desktop-reload usr/bin/vinix-host-sync; do
        if [ ! -x "$STAGING/$command_path" ]; then
            echo "ERROR: compact desktop is missing /$command_path" >&2
            exit 1
        fi
    done
fi
if [ "$WITH_CHROMIUM" -eq 1 ]; then
    for command_path in usr/lib/chromium/chrome usr/bin/run-chromium; do
        if [ ! -x "$STAGING/$command_path" ]; then
            echo "ERROR: Chromium desktop is missing /$command_path" >&2
            exit 1
        fi
    done
fi
if [ "$WITH_X86_TRANSLATION" -eq 1 ]; then
    for command_path in usr/bin/qemu-x86_64 usr/bin/run-x86-64 usr/bin/wine64; do
        if [ ! -x "$STAGING/$command_path" ]; then
            echo "ERROR: x86 translation desktop is missing /$command_path" >&2
            exit 1
        fi
    done
fi
if [ "$WITH_ROBLOX" -eq 1 ]; then
    for command_path in usr/bin/run-roblox usr/bin/run-roblox-client usr/bin/run-android \
        opt/vinix-android-aarch64/lib/ld-musl-aarch64.so.1 \
        opt/vinix-android-aarch64/usr/bin/android-translation-layer; do
        if [ ! -x "$STAGING/$command_path" ]; then
            echo "ERROR: Roblox desktop is missing /$command_path" >&2
            exit 1
        fi
    done
fi
if [ "$WITH_STEAM" -eq 1 ]; then
    for command_path in usr/bin/qemu-i386 usr/bin/qemu-x86_64 usr/bin/steam \
        usr/bin/steam-smoke usr/libexec/vinix-steam/root/usr/bin/bash \
        usr/libexec/vinix-steam/root/lib/ld-linux.so.2 bin/bash; do
        if [ ! -e "$STAGING/$command_path" ]; then
            echo "ERROR: Steam desktop is missing /$command_path" >&2
            exit 1
        fi
    done
    if [ ! -f "$STAGING/usr/lib/steam/bootstraplinux_ubuntu12_32.tar.xz" ]; then
        echo "ERROR: Steam desktop is missing Valve's bootstrap archive" >&2
        exit 1
    fi
fi
if [ "$WITH_DOTA2" -eq 1 ]; then
    for required in "${DOTA2_REQUIRED_PATHS[@]}"; do
        if [ ! -e "$STAGING/$required" ]; then
            echo "ERROR: Dota 2 desktop is missing /$required" >&2
            exit 1
        fi
    done
    for command_path in usr/bin/qemu-x86_64 usr/bin/run-dota2; do
        if [ ! -x "$STAGING/$command_path" ]; then
            echo "ERROR: Dota 2 desktop is missing /$command_path" >&2
            exit 1
        fi
    done
fi

if [ "$COMPACT_INITRAMFS" -eq 0 ] && [ -x "$HYPRLAND_STAGING/usr/bin/start-hyprland-vinix" ]; then
    for runtime_path in usr/bin/Hyprland usr/bin/start-hyprland-vinix usr/bin/foot usr/lib/libaquamarine.so.11 root/.config/hypr/hyprland.conf; do
        if [ ! -e "$STAGING/$runtime_path" ]; then
            echo "ERROR: staged Hyprland runtime is missing /$runtime_path" >&2
            exit 1
        fi
    done
fi

mkdir -p "$STAGING/usr/libexec"
cp "$BUILD_DIR/desktop-init" "$STAGING/sbin/init"
install -m755 "$BUILD_DIR/desktop-init" \
    "$STAGING/usr/libexec/vinix-desktop-init"
rm -f "$STAGING/usr/bin"/vinix-ui2-*
cp "$BUILD_DIR/vinix-desktop" "$STAGING/usr/bin/vinix-desktop"
# Guest hot reloads replace /usr/bin/vinix-desktop so every multicall native
# application changes generation with the compositor. Keep one unreachable
# packaged inode for PID 1 to restore on the next persistent disk-root boot.
install -m755 "$BUILD_DIR/vinix-desktop" \
    "$STAGING/usr/libexec/vinix-desktop-system"
# VOffice is not part of the image; `pkg install voffice` downloads the build
# published with its releases. A staging tree reused from an older build still
# carries the copy images used to preinstall, so drop it rather than ship a
# stale suite.
rm -f "$STAGING/usr/bin/voffice-calc" "$STAGING/usr/bin/voffice-writer"
rm -rf "$STAGING/usr/bin/assets" "$STAGING/usr/bin/translations"
if [ "$GPU_DESKTOP_BUILT" -eq 1 ]; then
    cp "$BUILD_DIR/vinix-desktop-gpu" "$STAGING/usr/bin/vinix-desktop-gpu"
    chmod +x "$STAGING/usr/bin/vinix-desktop-gpu"
else
    rm -f "$STAGING/usr/bin/vinix-desktop-gpu"
fi
cp "$BUILD_DIR/wifi-ctl" "$STAGING/usr/bin/wifi-ctl"
chmod +x "$STAGING/sbin/init" "$STAGING/usr/bin/vinix-desktop" \
    "$STAGING/usr/bin/wifi-ctl"

# One immutable multicall image, one exec name and process per application.
# Vinix records the path passed to execve, so these relative symlinks produce
# distinct names and truthful per-app accounting without storing a copy of the
# same static executable for every native application in the initramfs.
for app_name in vinix-files vinix-calculator vinix-terminal vinix-settings \
    vinix-opengothic vinix-android-calculator vinix-roblox vinix-dota2 \
    vinix-activity vinix-editor vinix-calendar vinix-clock \
    vinix-disk-usage vinix-preview vinix-console vinix-system-information \
    vinix-archive vinix-disk-utility vinix-backup \
    vinix-notes vinix-reminders vinix-grapher vinix-color-meter \
    vinix-firefox vinix-chromium vinix-gimp vinix-libreoffice vinix-minecraft vinix-doom vinix-wine-calculator vinix-wine-notepad \
    vinix-wine-word2013 vinix-blender vinix-capture vinix-obs vinix-qemu-window vinix-steam; do
    ln -sf vinix-desktop "$STAGING/usr/bin/$app_name"
done

# The bundle is mutable command-line input, so do not let a previous selection
# survive a cached-layer build that no longer asks for it.
rm -rf "$STAGING/usr/share/vinix/wifi"
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

rm -rf "$STAGING/usr/share/vinix/wallpapers"
mkdir -p "$STAGING/usr/share/vinix/wallpapers"
if [ -d "$BUILD_DIR/wallpapers" ]; then
    cp "$BUILD_DIR/wallpapers"/*.vwp "$BUILD_DIR/wallpapers"/index.txt \
        "$BUILD_DIR/wallpapers"/SOURCES.txt "$STAGING/usr/share/vinix/wallpapers/" 2>/dev/null || true
fi

# Keep a system-owned development copy outside persistent /root. It lets an
# upgraded machine build even when its carried home predates /root/vmodules.
# The editable home copy is seeded from the same exact host-build sources.
DESKTOP_DEV_ROOT="$STAGING/usr/share/vinix/desktop-dev"
rm -rf "$DESKTOP_DEV_ROOT"
mkdir -p "$DESKTOP_DEV_ROOT/desktop"
cp -L "$APP_SRC"/*.v "$APP_SRC"/*.vml "$APP_SRC"/*.h \
    "$BUILD_DIR/execinfo.c" "$BUILD_DIR/gpu-present-soft.c" \
    "$SCRIPT_DIR/desktop/README.md" "$DESKTOP_DEV_ROOT/desktop/"
cp -a "$SCRIPT_DIR/desktop/execinfocore" "$SCRIPT_DIR/desktop/gpucore" "$DESKTOP_DEV_ROOT/desktop/"
mkdir -p "$DESKTOP_DEV_ROOT/vmodules/ui2"
cp -aL "$UI2_MODULES/ui2/." "$DESKTOP_DEV_ROOT/vmodules/ui2/"
if [ ! -f "$DESKTOP_DEV_ROOT/desktop/main.v" ] || \
   [ ! -f "$DESKTOP_DEV_ROOT/vmodules/ui2/v.mod" ]; then
    echo "ERROR: system desktop development tree is incomplete" >&2
    exit 1
fi
python3 "$SCRIPT_DIR/build-support/content-key.py" \
    "$DESKTOP_DEV_ROOT/desktop" "$DESKTOP_DEV_ROOT/vmodules" \
    > "$DESKTOP_DEV_ROOT/.source-version"
rm -rf "$STAGING/root/desktop" "$STAGING/root/vmodules"
cp -a "$DESKTOP_DEV_ROOT/desktop" "$STAGING/root/desktop"
cp -a "$DESKTOP_DEV_ROOT/vmodules" "$STAGING/root/vmodules"
install -m644 "$DESKTOP_DEV_ROOT/.source-version" \
    "$STAGING/root/.vinix-desktop-dev-version"

# Vinix's loader opens a shared object without following links, and current
# Mesa ships every DRI driver as a link to one libdril_dri.so. A dlopen of
# /usr/lib/dri/swrast_dri.so therefore finds nothing, EGL cannot create a
# screen, and an application that renders through it -- native Blender, whose
# GHOST backend needs a surfaceless EGL context -- dies on EGL_NOT_INITIALIZED
# with no hint that a link was the cause. scripts/build-userland-aarch64.sh resolves
# these already; a compact image builds its own tree and has to do it too.
# They all point at one 100 KiB object, so materialising them costs very little.
if [ -d "$STAGING/usr/lib/dri" ]; then
    echo "==> Materialising DRI driver links"
    find "$STAGING/usr/lib/dri" -type l -name '*.so*' | while IFS= read -r link; do
        target=$(readlink "$link")
        case "$target" in
            /*) real="$STAGING$target" ;;
            *) real="$(dirname "$link")/$target" ;;
        esac
        if [ -f "$real" ]; then
            rm "$link"
            cp "$real" "$link"
        fi
    done
    if [ -L "$STAGING/usr/lib/dri/swrast_dri.so" ] ||
       [ ! -f "$STAGING/usr/lib/dri/swrast_dri.so" ]; then
        echo "ERROR: /usr/lib/dri/swrast_dri.so is not a regular file; EGL will not start" >&2
        exit 1
    fi
fi

# A repeated build with the same immutable layer generations and the same
# desktop-owned content would produce the same useful image bytes but a fresh
# tar mtime. The QEMU system-volume identity is intentionally size+mtime, so
# rewriting that 7+ GiB tar also causes an unnecessary full reinstall. Hash
# only this comparatively small mutable set; layer changes are already covered
# by the generation manifest above.
CONTENT_KEY_EXPECTED="$(mktemp "$BUILD_DIR/.initramfs-root.content-key.XXXXXX")"
if [ "$GPU_DESKTOP_BUILT" -eq 1 ]; then
    GPU_CONTENT_KEY_INPUT="$BUILD_DIR/vinix-desktop-gpu"
else
    GPU_CONTENT_KEY_INPUT="$BUILD_DIR/.vinix-desktop-gpu-not-built"
fi
CONTENT_KEY_INPUTS=(
    "$BUILD_DIR/desktop-init"
    "$BUILD_DIR/vinix-desktop"
    "$GPU_CONTENT_KEY_INPUT"
    "$BUILD_DIR/wifi-ctl"
    "$BUILD_DIR/wallpapers"
    "$SCRIPT_DIR/desktop"
    "$SCRIPT_DIR/build-support/security-tools"
    "$SCRIPT_DIR/build-support/stage-uname.sh"
    "$SCRIPT_DIR/build-support/uname"
    "$SCRIPT_DIR/build-support/security-audit"
    "$SCRIPT_DIR/tools/security-audit"
    "$SCRIPT_DIR/tools/security-mac"
    "$SCRIPT_DIR/tools/sandbox"
    "$SCRIPT_DIR/build-support/musl/stage.py"
    "$SCRIPT_DIR/build-support/musl/malloc-retain.patch"
    "$SCRIPT_DIR/build-support/musl/alpine"
    "$SCRIPT_DIR/build-support/musl/alpine-1.2.6"
    "$STAGING/usr/share/vinix/musl-build.json"
    "$STAGING/usr/bin/run-ios"
    "$STAGING/usr/share/vinix/ios"
    "$SCRIPT_DIR/build-support/vinix-pkg"
    "$SCRIPT_DIR/build-support/v-command"
    "$SCRIPT_DIR/build-support/vinix-desktop-build"
    "$SCRIPT_DIR/build-support/vinix-desktop-reload"
    "$SCRIPT_DIR/build-support/vinix-host-sync"
    "$SCRIPT_DIR/build-support/vinix-version-check"
    "$SCRIPT_DIR/build-support/xorg-server/startx"
    "$SCRIPT_DIR/build-support/xorg-server/winehost"
    "$SCRIPT_DIR/build-support/xorg-server/wine-host-v-abi.c"
    "$SCRIPT_DIR/build-support/xorg-server/wine-host-v-abi.h"
    "$SCRIPT_DIR/build-support/xorg-server/compile-v-host.py"
    "$SCRIPT_DIR/build-support/xorg-server/xinputcore"
    "$SCRIPT_DIR/build-support/xorg-server/xinput_abi.h"
    "$SCRIPT_DIR/build-support/xorg-server/vinix-xinput.c"
    "$SCRIPT_DIR/build-support/firefox"
    "$SCRIPT_DIR/build-support/gimp"
    "$SCRIPT_DIR/build-support/obs"
    "$SCRIPT_DIR/build-support/libreoffice"
    "$SCRIPT_DIR/build-support/chromium"
    "$SCRIPT_DIR/build-support/hyprland"
    "$SCRIPT_DIR/build-support/steam"
    "$SCRIPT_DIR/gl-triangle/run-m1-agx-smoke"
    "$SCRIPT_DIR/gl-triangle/eglcore"
    "$SCRIPT_DIR/gl-triangle/glutcore"
    "$SCRIPT_DIR/gl-triangle/legacycore"
    "$SCRIPT_DIR/gl-triangle/gl_v.h"
    "$SCRIPT_DIR/gl-triangle/compile-v.py"
    "$SCRIPT_DIR/gl-triangle/stage.py"
    "$SCRIPT_DIR/tests/browsers/firefox-smoke.html"
    "$SCRIPT_DIR/tests/browsers/chromium-smoke.html"
    "$SCRIPT_DIR/tests/packages/x-window-check.py"
)
if [ -n "$WIFI_BUNDLE" ]; then
    CONTENT_KEY_INPUTS+=("$WIFI_BUNDLE")
fi
python3 "$SCRIPT_DIR/build-support/content-key.py" \
    "${CONTENT_KEY_INPUTS[@]}" > "$CONTENT_KEY_EXPECTED"
if [ "$WITH_STEAM" -eq 1 ]; then
    printf 'steam-layer=%s\n' "$(path_generation "$STEAM_STAGING")" \
        >> "$CONTENT_KEY_EXPECTED"
fi
if [ "$WITH_DOTA2" -eq 1 ]; then
    printf 'dota2-layer=%s\n' "$(path_generation "$DOTA2_STAGING")" \
        >> "$CONTENT_KEY_EXPECTED"
fi
printf 'release=%s\n' "${VINIX_RELEASE:-}" >> "$CONTENT_KEY_EXPECTED"

if [ "$REUSE_STAGING" -eq 1 ] &&
   [ -f "$CONTENT_KEY" ] && cmp -s "$CONTENT_KEY_EXPECTED" "$CONTENT_KEY" &&
   [ -s "$DESKTOP_INITRAMFS" ] &&
   { [ "$COMPACT_INITRAMFS" -eq 0 ] || [ -s "$DESKTOP_INITRAMFS_GZ" ]; }; then
    echo "==> Desktop image content unchanged; keeping existing archive"
    echo "    $DESKTOP_INITRAMFS ($(file_size "$DESKTOP_INITRAMFS") bytes)"
    rm -f "$STAGING_CACHE_EXPECTED" "$CONTENT_KEY_EXPECTED"
    release_desktop_build_lock
    trap - EXIT
    exit 0
fi

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
echo "    $DESKTOP_INITRAMFS ($(file_size "$DESKTOP_INITRAMFS") bytes)"

# Limine can transparently decompress a module whose resource path starts
# with '$'. The Asahi ESP is only 500 MiB, so the compact M1 image also needs
# a deterministic gzip representation; the uncompressed tar remains the QEMU
# input. Publish it atomically so a failed compression cannot leave a valid-
# looking partial image for scripts/deploy-m1-efi.sh.
if [ "$COMPACT_INITRAMFS" -eq 1 ]; then
    DESKTOP_INITRAMFS_GZ_TMP="$(mktemp "$(dirname "$DESKTOP_INITRAMFS_GZ")/.initramfs-desktop.tar.gz.XXXXXX")"
    # Large optional layers such as Steam make repeat VM builds expensive.
    # Keep the release default while allowing a faster local test archive.
    gzip_level="${VINIX_DESKTOP_GZIP_LEVEL:-6}"
    case "$gzip_level" in
        [1-9]) ;;
        *) echo "ERROR: VINIX_DESKTOP_GZIP_LEVEL must be 1 through 9" >&2; exit 2 ;;
    esac
    if ! gzip -n "-$gzip_level" -c "$DESKTOP_INITRAMFS" > "$DESKTOP_INITRAMFS_GZ_TMP"; then
        rm -f "$DESKTOP_INITRAMFS_GZ_TMP"
        exit 1
    fi
    if ! gzip -t "$DESKTOP_INITRAMFS_GZ_TMP"; then
        rm -f "$DESKTOP_INITRAMFS_GZ_TMP"
        echo "ERROR: compressed desktop initramfs failed verification" >&2
        exit 1
    fi
    mv -f "$DESKTOP_INITRAMFS_GZ_TMP" "$DESKTOP_INITRAMFS_GZ"
    echo "    compressed EFI image: $DESKTOP_INITRAMFS_GZ ($(file_size "$DESKTOP_INITRAMFS_GZ") bytes)"
else
    # A full rebuild makes any compressed compact image stale. Refuse to let a
    # later hardware deployment mistake it for this newly published archive.
    rm -f "$DESKTOP_INITRAMFS_GZ"
fi

# Publish cache metadata only after every requested image representation has
# succeeded. A failed tar/gzip can therefore never mark an incomplete build as
# reusable.
mv -f "$STAGING_CACHE_EXPECTED" "$STAGING_CACHE"
mv -f "$CONTENT_KEY_EXPECTED" "$CONTENT_KEY"
release_desktop_build_lock
trap - EXIT
