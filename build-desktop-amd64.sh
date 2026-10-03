#!/bin/bash
# Build the native Vinix desktop for amd64 and assemble a dedicated boot ISO.
#
# The desktop uses the base image's optimized musl allocator; normal commands
# and GCC come from official Alpine packages.
#
# The image carries the same package layers as the arm64 desktop; build them
# first with ./build-x11-amd64.sh, ./build-firefox-amd64.sh,
# ./build-network-tools-amd64.sh, ./build-python-amd64.sh and
# ./build-v-amd64.sh.
#
# Usage: ./build-desktop-amd64.sh [--no-iso]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${VINIX_AMD64_DESKTOP_BUILD_DIR:-$SCRIPT_DIR/build-amd64-desktop}"
USERLAND_DIR="${VINIX_AMD64_USERLAND_BUILD_DIR:-$SCRIPT_DIR/build-amd64-userland}"
SYSROOT="${VINIX_AMD64_SYSROOT:-$USERLAND_DIR/staging}"
KERNEL_BUILD_DIR="${VINIX_AMD64_BUILD_DIR:-$SCRIPT_DIR/build-amd64-kernel}"
OUTPUT_ISO="${VINIX_AMD64_DESKTOP_ISO:-$SCRIPT_DIR/vinix-desktop-amd64.iso}"
MAKE_ISO=1

for arg in "$@"; do
    case "$arg" in
        --no-iso) MAKE_ISO=0 ;;
        --help|-h)
            sed -n '2,/^set -/s/^# \{0,1\}//p' "$0"
            exit 0
            ;;
        *)
            echo "ERROR: unknown option: $arg" >&2
            exit 1
            ;;
    esac
done

V="${V:-}"
. "$SCRIPT_DIR/build-support/find-v.sh"

if [ -n "${VINIX_UI2_SOURCE:-}" ]; then
    UI2_SOURCE="$VINIX_UI2_SOURCE"
elif [ -f "$SCRIPT_DIR/../ui2/v.mod" ]; then
    # A sibling development checkout is the source requested by local Vinix
    # work; packaged/CI builds retain the conventional third_party fallback.
    UI2_SOURCE="$SCRIPT_DIR/../ui2"
else
    UI2_SOURCE="$SCRIPT_DIR/third_party/ui2"
fi

# X.org with Mesa and LLVM; GTK with its fonts and media codecs, which come
# from the Firefox layer without Firefox itself (the first-run app page offers
# the browser through pkg); pkg with apk, curl and git; Python; V with TCC.
X11_STAGING="${VINIX_AMD64_X11_STAGING:-$SCRIPT_DIR/build-amd64-x11/staging}"
FIREFOX_STAGING="${VINIX_AMD64_FIREFOX_STAGING:-$SCRIPT_DIR/build-amd64-firefox/staging}"
NETWORK_TOOLS_STAGING="${VINIX_AMD64_NETWORK_TOOLS_STAGING:-$SCRIPT_DIR/build-amd64-network-tools/staging}"
PYTHON_STAGING="${VINIX_AMD64_PYTHON_STAGING:-$SCRIPT_DIR/build-amd64-python/staging}"
VLANG_STAGING="${VINIX_AMD64_VLANG_STAGING:-$SCRIPT_DIR/build-amd64-v/staging}"
for layer in "$X11_STAGING:build-x11-amd64.sh" "$FIREFOX_STAGING:build-firefox-amd64.sh" \
    "$NETWORK_TOOLS_STAGING:build-network-tools-amd64.sh" \
    "$PYTHON_STAGING:build-python-amd64.sh" "$VLANG_STAGING:build-v-amd64.sh"; do
    if [ ! -d "${layer%%:*}/usr" ]; then
        echo "ERROR: missing package layer ${layer%%:*}; run ./${layer##*:} first" >&2
        exit 1
    fi
done

case "$BUILD_DIR" in
    ''|/|"$SCRIPT_DIR")
        echo "ERROR: refusing unsafe desktop build directory: $BUILD_DIR" >&2
        exit 1
        ;;
esac

CLANG="${VINIX_AMD64_CLANG:-}"
LLVM_STRIP="${VINIX_AMD64_STRIP:-}"
for llvm_prefix in /opt/homebrew/opt/llvm/bin /usr/local/opt/llvm/bin; do
    if [ -z "$CLANG" ] && [ -x "$llvm_prefix/clang" ]; then
        CLANG="$llvm_prefix/clang"
    fi
    if [ -z "$LLVM_STRIP" ] && [ -x "$llvm_prefix/llvm-strip" ]; then
        LLVM_STRIP="$llvm_prefix/llvm-strip"
    fi
done
CLANG="${CLANG:-$(command -v clang || true)}"
LLVM_STRIP="${LLVM_STRIP:-$(command -v llvm-strip || command -v strip || true)}"
if [ -z "$CLANG" ] || [ -z "$LLVM_STRIP" ] || ! command -v ld.lld >/dev/null 2>&1; then
    echo "ERROR: clang, ld.lld, and llvm-strip (or strip) are required." >&2
    exit 1
fi
if [ ! -f "$UI2_SOURCE/v.mod" ]; then
    echo "ERROR: ui2 not found at $UI2_SOURCE. Clone it at third_party/ui2:" >&2
    echo "    git clone https://github.com/vlang/ui2 third_party/ui2" >&2
    exit 1
fi
if [ ! -f "$UI2_SOURCE/ui/vml_compiled.v" ] || \
   [ ! -f "$UI2_SOURCE/examples/calculator/calculator.vml" ]; then
    echo "ERROR: this ui2 checkout has no compile-time VML support; update it." >&2
    exit 1
fi

echo "==> Staging Alpine's prebuilt amd64 userland and toolchain..."
VINIX_AMD64_USERLAND_BUILD_DIR="$USERLAND_DIR" VINIX_ALPINE_DEVTOOLS=1 \
    "$SCRIPT_DIR/build-userland-amd64.sh"
# Existing/custom sysroots must use the optimized allocator for the static desktop.
python3 "$SCRIPT_DIR/build-support/musl/stage.py" --arch x86_64 --staging "$SYSROOT"
if [ ! -f "$SYSROOT/usr/lib/libc.a" ] || [ ! -d "$SYSROOT/usr/include" ]; then
    echo "ERROR: Alpine development sysroot is incomplete: $SYSROOT" >&2
    exit 1
fi
GCCLIB="$(find "$SYSROOT/usr/lib/gcc/x86_64-alpine-linux-musl" \
    -mindepth 1 -maxdepth 1 -type d 2>/dev/null | LC_ALL=C sort | tail -n1)"
if [ -z "$GCCLIB" ] || [ ! -f "$GCCLIB/libgcc.a" ]; then
    echo "ERROR: Alpine GCC runtime not found below $SYSROOT/usr/lib/gcc" >&2
    exit 1
fi

mkdir -p "$BUILD_DIR"
UI2_MODULES="$BUILD_DIR/vmodules"
python3 "$SCRIPT_DIR/desktop/tools/stage_ui2.py" \
    "$UI2_MODULES/ui2" "$UI2_SOURCE" \
    "$SCRIPT_DIR/desktop/tools/ui2_headless_bounds.v"

echo "==> Staging desktop sources..."
APP_SRC="$BUILD_DIR/app-src"
python3 "$SCRIPT_DIR/desktop/tools/stage_app.py" "$APP_SRC" "$SCRIPT_DIR/desktop" \
    "$UI2_SOURCE/examples/calculator"

echo "==> Translating the amd64 desktop to C..."
BUILD_STAMP="${VINIX_BUILD_STAMP:-$(date '+%m-%d %H:%M')}"
"$V" -new-compiler -os linux -arch x64 \
    -gc none -d glibc -manualfree -enable-globals -prod \
    -d ui2_headless \
    -d "vinix_build_stamp=$BUILD_STAMP" \
    -path "@vlib|$UI2_MODULES|@vmodules|$SCRIPT_DIR|$SCRIPT_DIR/third_party" \
    -o "$BUILD_DIR/desktop.c" "$APP_SRC"

echo "==> Compiling for x86_64-linux-musl..."
"$CLANG" --target=x86_64-linux-musl -static -nostdinc -nostdlib \
    -isystem "$GCCLIB/include" -isystem "$SYSROOT/usr/include" \
    -I "$APP_SRC" \
    -O2 -fno-stack-protector -w \
    "$SYSROOT/usr/lib/crt1.o" "$SYSROOT/usr/lib/crti.o" "$GCCLIB/crtbeginT.o" \
    "$BUILD_DIR/desktop.c" "$SCRIPT_DIR/desktop/execinfo_compat.c" \
    -L"$SYSROOT/usr/lib" -L"$GCCLIB" -lgcc_eh -lc -lgcc -lm \
    "$GCCLIB/crtend.o" "$SYSROOT/usr/lib/crtn.o" \
    -fuse-ld=lld -o "$BUILD_DIR/vinix-desktop"
"$LLVM_STRIP" "$BUILD_DIR/vinix-desktop"

echo "==> Staging the amd64 desktop initramfs..."
STAGING="$BUILD_DIR/initramfs-root"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -a "$SYSROOT/." "$STAGING/"

# macOS cp follows an existing destination symlink and cannot replace a
# read-only file in place, so unlink what a layer is about to replace.
merge_staging_tree() {
    local overlay="$1" source relative destination
    while IFS= read -r -d '' source; do
        relative="${source#"$overlay/"}"
        destination="$STAGING/$relative"
        if [ ! -d "$source" ] && { [ -e "$destination" ] || [ -L "$destination" ]; }; then
            rm -f "$destination"
        fi
    done < <(find "$overlay" -mindepth 1 -print0)
    cp -a "$overlay/." "$STAGING/"
}
for layer in "$X11_STAGING" "$FIREFOX_STAGING" "$NETWORK_TOOLS_STAGING" \
    "$PYTHON_STAGING" "$VLANG_STAGING"; do
    echo "    merging $layer"
    merge_staging_tree "$layer"
done
rm -rf "$STAGING/usr/lib/firefox-esr" "$STAGING/usr/lib/firefox" \
    "$STAGING/usr/bin/firefox-esr" "$STAGING/usr/bin/firefox" \
    "$STAGING"/usr/share/applications/firefox*.desktop \
    "$STAGING"/usr/share/icons/hicolor/*/apps/firefox* \
    "$STAGING"/usr/share/metainfo/*firefox*
rm -f "$STAGING/.PKGINFO" "$STAGING/.INSTALL" "$STAGING"/.SIGN.* \
    "$STAGING"/.pre-* "$STAGING"/.post-* "$STAGING"/.trigger*
mkdir -p "$STAGING/usr/bin" "$STAGING/usr/share/vinix/wallpapers" \
    "$STAGING/usr/share/vinix/icons" "$STAGING/root/desktop" "$STAGING/run"
install -m755 "$BUILD_DIR/vinix-desktop" "$STAGING/usr/bin/vinix-desktop"
rm -f "$STAGING/usr/bin"/vinix-ui2-*
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
install -m755 "$SCRIPT_DIR/build-support/vinix-desktop-reload" \
    "$STAGING/usr/bin/vinix-desktop-reload"
# The launchers and settings the desktop's X11 apps and pkg expect, as on arm64.
# Refresh security utilities when using an existing or custom userland root.
python3 "$SCRIPT_DIR/build-support/security-tools/stage.py" --arch x86_64 --staging "$STAGING"
install -m755 "$SCRIPT_DIR/build-support/vinix-pkg" "$STAGING/usr/bin/pkg"
install -m755 "$SCRIPT_DIR/build-support/xorg-server/startx" "$STAGING/usr/bin/startx"
install -m755 "$SCRIPT_DIR/build-support/firefox/run-firefox" "$STAGING/usr/bin/run-firefox"
install -m755 "$SCRIPT_DIR/build-support/chromium/run-chromium" "$STAGING/usr/bin/run-chromium"
install -m755 "$SCRIPT_DIR/build-support/gimp/run-gimp" "$STAGING/usr/bin/run-gimp"
install -m755 "$SCRIPT_DIR/build-support/libreoffice/run-libreoffice" \
    "$STAGING/usr/bin/run-libreoffice"
mkdir -p "$STAGING/etc/firefox/policies" "$STAGING/usr/share/vinix/firefox" \
    "$STAGING/etc/chromium/policies/managed" "$STAGING/etc/gimp/2.0" \
    "$STAGING/etc/libreoffice"
install -m644 "$SCRIPT_DIR/build-support/firefox/policies.json" \
    "$STAGING/etc/firefox/policies/policies.json"
install -m644 "$SCRIPT_DIR/build-support/firefox/vinix.js" \
    "$STAGING/usr/share/vinix/firefox/vinix.js"
install -m644 "$SCRIPT_DIR/build-support/chromium/policies.json" \
    "$STAGING/etc/chromium/policies/managed/vinix.json"
install -m644 "$SCRIPT_DIR/build-support/gimp/vinix-gimprc" \
    "$STAGING/etc/gimp/2.0/vinix-gimprc"
install -m644 "$SCRIPT_DIR/build-support/gimp/vinix-sessionrc" \
    "$STAGING/etc/gimp/2.0/vinix-sessionrc"
install -m644 "$SCRIPT_DIR/build-support/libreoffice/vinix-registrymodifications.xcu" \
    "$STAGING/etc/libreoffice/vinix-registrymodifications.xcu"
install -m644 "$SCRIPT_DIR/build-support/libreoffice/welcome.fodt" \
    "$STAGING/usr/share/vinix/libreoffice-welcome.fodt"
install -m644 "$SCRIPT_DIR/tests/browsers/firefox-smoke.html" \
    "$STAGING/usr/share/vinix/firefox-smoke.html"
install -m644 "$SCRIPT_DIR/tests/browsers/chromium-smoke.html" \
    "$STAGING/usr/share/vinix/chromium-smoke.html"
install -m755 "$SCRIPT_DIR/tests/packages/x-window-check.py" \
    "$STAGING/usr/share/vinix/x-window-check.py"
rm -f "$STAGING/sbin/init"
install -m755 "$SCRIPT_DIR/build-support/init-amd64/desktop-init" "$STAGING/sbin/init"
# The release this image is, for the desktop to compare with the newest one
# vinix-os.org names (build-support/vinix-version-check). deploy-iso.sh sets
# VINIX_RELEASE; any other build is a development image and does not ask.
mkdir -p "$STAGING/usr/libexec"
install -m755 "$SCRIPT_DIR/build-support/vinix-version-check" \
    "$STAGING/usr/libexec/vinix-version-check"
if [ -n "${VINIX_RELEASE:-}" ]; then
    printf '%s\n' "$VINIX_RELEASE" > "$STAGING/etc/vinix-release"
fi
# Restore the default loader after Alpine package layers have been merged.
echo "==> Installing Vinix's optimized musl allocator..."
python3 "$SCRIPT_DIR/build-support/musl/stage.py" --arch x86_64 --staging "$STAGING"

for command_path in bin/zsh usr/bin/python3 usr/bin/v usr/bin/tcc usr/bin/pkg sbin/apk \
    usr/bin/curl usr/bin/git usr/bin/Xorg usr/bin/Xvfb usr/bin/Xvfb-glx \
    usr/bin/vinix-wine-host usr/bin/vinix-xinput usr/bin/run-firefox; do
    if [ ! -x "$STAGING/$command_path" ]; then
        echo "ERROR: desktop image has no executable /$command_path" >&2
        exit 1
    fi
done
for runtime_path in usr/lib/libgtk-3.so.0 usr/lib/libavcodec.so.60 \
    usr/lib/xorg/modules/dri/swrast_dri.so usr/share/fonts; do
    if [ ! -e "$STAGING/$runtime_path" ]; then
        echo "ERROR: desktop image is missing /$runtime_path" >&2
        exit 1
    fi
done

# One immutable multicall image, with the same per-application process names as
# the aarch64 desktop image.
for app_name in vinix-files vinix-calculator vinix-terminal vinix-settings \
    vinix-activity vinix-editor vinix-calendar vinix-clock \
    vinix-disk-usage \
    vinix-firefox vinix-chromium vinix-gimp vinix-libreoffice \
    vinix-minecraft vinix-wine-calculator vinix-wine-notepad vinix-wine-word2010 \
    vinix-capture; do
    ln -sf vinix-desktop "$STAGING/usr/bin/$app_name"
done

echo "==> Wallpapers..."
python3 "$SCRIPT_DIR/desktop/tools/fetch_wallpapers.py" "$BUILD_DIR/wallpapers" \
    --cache "$BUILD_DIR/wallpapers-cache" || true
if [ -d "$BUILD_DIR/wallpapers" ]; then
    cp "$BUILD_DIR/wallpapers"/*.vwp "$BUILD_DIR/wallpapers"/index.txt \
        "$BUILD_DIR/wallpapers"/SOURCES.txt \
        "$STAGING/usr/share/vinix/wallpapers/" 2>/dev/null || true
fi
cp "$SCRIPT_DIR/desktop"/*.v "$SCRIPT_DIR/desktop"/*.c "$SCRIPT_DIR/desktop"/*.h \
    "$SCRIPT_DIR/desktop/README.md" "$STAGING/root/desktop/"

INITRAMFS="$BUILD_DIR/initramfs-desktop.tar"
INITRAMFS_TMP="$(mktemp "$BUILD_DIR/.initramfs-desktop.tar.XXXXXX")"
trap 'rm -f "$INITRAMFS_TMP"' EXIT
tar --format=ustar -cf "$INITRAMFS_TMP" -C "$STAGING" .
mv -f "$INITRAMFS_TMP" "$INITRAMFS"
trap - EXIT
echo "    $INITRAMFS ($(wc -c < "$INITRAMFS" | tr -d ' ') bytes)"

if [ "$MAKE_ISO" -eq 0 ]; then
    exit 0
fi
VINIX_AMD64_BUILD_DIR="$KERNEL_BUILD_DIR" \
    "$SCRIPT_DIR/build-amd64.sh" --no-userland --no-iso
VINIX_AMD64_KERNEL="$KERNEL_BUILD_DIR/bin/vinix" \
VINIX_AMD64_INITRAMFS="$INITRAMFS" \
VINIX_AMD64_ISO="$OUTPUT_ISO" \
VINIX_AMD64_ISO_BUILD_DIR="$BUILD_DIR/iso" \
    "$SCRIPT_DIR/build-support/build-amd64-iso.sh"
