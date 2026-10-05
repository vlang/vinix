#!/bin/bash
# Prepare the required desktop layers on a fresh checkout. Optional language
# runtimes and applications remain the responsibility of their own builders.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
USERLAND_BUILD_DIR="${VINIX_AARCH64_USERLAND_BUILD_DIR:-$SCRIPT_DIR/build-aarch64-userland}"
SYSROOT="${VINIX_AARCH64_SYSROOT:-$USERLAND_BUILD_DIR/staging}"
BASE_INITRAMFS="$SCRIPT_DIR/build-support/init-aarch64/initramfs.tar"
NETWORK_STAGING="${VINIX_NETWORK_TOOLS_STAGING:-$SCRIPT_DIR/build-aarch64-network-tools/staging}"
X11_STAGING="${VINIX_X11_STAGING:-$SCRIPT_DIR/build-aarch64-x11/staging}"
FIREFOX_STAGING="${VINIX_FIREFOX_STAGING:-$SCRIPT_DIR/build-aarch64-firefox/staging}"

has_executables() {
    local directory="$1" path
    shift
    for path in "$@"; do
        [ -x "$directory/$path" ] || return 1
    done
}

archive_has() {
    [ -s "$BASE_INITRAMFS" ] &&
        tar tf "$BASE_INITRAMFS" "$@" >/dev/null 2>&1
}

sysroot_ready() {
    local runtime
    [ -s "$SYSROOT/usr/lib/libc.a" ] && [ -d "$SYSROOT/usr/include" ] || return 1
    for runtime in "$SYSROOT"/usr/lib/gcc/aarch64-alpine-linux-musl/*/libgcc.a; do
        [ -s "$runtime" ] && return 0
    done
    return 1
}

network_ready() {
    has_executables "$NETWORK_STAGING" usr/bin/pkg sbin/apk &&
        [ -s "$NETWORK_STAGING/etc/vinix-pkg/base-world" ]
}

x11_ready() {
    has_executables "$X11_STAGING" usr/bin/Xorg usr/bin/Xvfb usr/bin/startx \
        usr/bin/vinix-xinput usr/bin/vinix-wine-host
}

firefox_ready() {
    has_executables "$FIREFOX_STAGING" usr/bin/run-firefox &&
        { has_executables "$FIREFOX_STAGING" usr/lib/firefox-esr/firefox-esr usr/bin/firefox-esr ||
          has_executables "$FIREFOX_STAGING" usr/lib/firefox/firefox usr/bin/firefox; }
}

base_has_firefox() {
    archive_has ./usr/lib/firefox-esr/firefox-esr ./usr/bin/firefox-esr ||
        archive_has ./usr/lib/firefox/firefox ./usr/bin/firefox
}

require_default_staging() {
    local label="$1" actual="$2" expected="$3"
    if [ "$actual" != "$expected" ]; then
        echo "ERROR: custom $label staging is incomplete: $actual" >&2
        echo "Build that staging tree before running the desktop." >&2
        exit 1
    fi
}

require_matching_build_directory() {
    local label="$1" actual="$2" expected="$3"
    if [ "$actual" != "$expected" ]; then
        echo "ERROR: $label build directory does not publish the required staging: $actual" >&2
        echo "Build it first and select its staging with VINIX_${label}_STAGING." >&2
        exit 1
    fi
}

# Validate caller-owned inputs before downloading or rebuilding anything.
NEED_USERLAND=0
if ! sysroot_ready; then
    require_default_staging "AArch64 sysroot" "$SYSROOT" "$USERLAND_BUILD_DIR/staging"
    NEED_USERLAND=1
fi
if ! archive_has ./usr/bin/vim; then
    NEED_USERLAND=1
fi
NEED_NETWORK=0
if ! network_ready; then
    require_default_staging "network tools" "$NETWORK_STAGING" "$SCRIPT_DIR/build-aarch64-network-tools/staging"
    require_matching_build_directory NETWORK_TOOLS \
        "${VINIX_NETWORK_TOOLS_BUILD_DIR:-$SCRIPT_DIR/build-aarch64-network-tools}" \
        "$SCRIPT_DIR/build-aarch64-network-tools"
    NEED_NETWORK=1
fi
NEED_X11=0
if ! x11_ready; then
    require_default_staging X11 "$X11_STAGING" "$SCRIPT_DIR/build-aarch64-x11/staging"
    require_matching_build_directory X11 \
        "${VINIX_X11_BUILD_DIR:-$SCRIPT_DIR/build-aarch64-x11}" \
        "$SCRIPT_DIR/build-aarch64-x11"
    NEED_X11=1
fi
NEED_FIREFOX=0
if ! firefox_ready; then
    if [ "$FIREFOX_STAGING" != "$SCRIPT_DIR/build-aarch64-firefox/staging" ]; then
        require_default_staging Firefox "$FIREFOX_STAGING" "$SCRIPT_DIR/build-aarch64-firefox/staging"
    fi
    # Rebuilding userland replaces the archive. Firefox preserved only in an
    # older base would otherwise disappear when another layer is prepared.
    if [ "$NEED_USERLAND" -eq 1 ] || [ "$NEED_NETWORK" -eq 1 ] ||
       [ "$NEED_X11" -eq 1 ] ||
       ! archive_has ./usr/bin/Xorg ./usr/bin/Xvfb ./usr/bin/startx ||
       ! base_has_firefox; then
        require_matching_build_directory FIREFOX \
            "${VINIX_FIREFOX_BUILD_DIR:-$SCRIPT_DIR/build-aarch64-firefox}" \
            "$SCRIPT_DIR/build-aarch64-firefox"
        NEED_FIREFOX=1
    fi
fi

if [ -n "${VINIX_UI2_SOURCE:-}" ]; then
    UI2_SOURCE="$VINIX_UI2_SOURCE"
elif [ -f "$SCRIPT_DIR/../ui2/v.mod" ]; then
    UI2_SOURCE="$SCRIPT_DIR/../ui2"
else
    UI2_SOURCE="$SCRIPT_DIR/third_party/ui2"
    if [ ! -f "$UI2_SOURCE/v.mod" ]; then
        if [ -e "$UI2_SOURCE" ]; then
            echo "ERROR: ui2 directory is incomplete: $UI2_SOURCE" >&2
            exit 1
        fi
        echo "==> Fetching ui2 for the desktop..."
        mkdir -p "$SCRIPT_DIR/third_party"
        git clone --depth 1 https://github.com/vlang/ui2 "$UI2_SOURCE"
    fi
fi
if [ ! -f "$UI2_SOURCE/v.mod" ] || [ ! -f "$UI2_SOURCE/ui/vml_compiled.v" ] ||
   [ ! -f "$UI2_SOURCE/examples/calculator/calculator.vml" ]; then
    echo "ERROR: ui2 checkout needs current compile-time VML support: $UI2_SOURCE" >&2
    echo "Update that checkout before running the desktop." >&2
    exit 1
fi

build_userland() {
    VINIX_AARCH64_USERLAND_BUILD_DIR="$USERLAND_BUILD_DIR" \
    VINIX_AARCH64_INITRAMFS="$BASE_INITRAMFS" \
    VINIX_ALPINE_BASE_ONLY="$1" "$SCRIPT_DIR/scripts/build-userland-aarch64.sh"
}

if [ "$NEED_USERLAND" -eq 1 ]; then
    echo "==> Preparing the AArch64 base userland..."
    build_userland 1
    if ! sysroot_ready || ! archive_has ./usr/bin/vim; then
        echo "ERROR: AArch64 userland builder did not publish a complete base and sysroot" >&2
        exit 1
    fi
fi
if [ "$NEED_NETWORK" -eq 1 ]; then
    echo "==> Preparing the desktop package tools..."
    VINIX_ARCH=aarch64 "$SCRIPT_DIR/scripts/build-network-tools-aarch64.sh"
    network_ready || { echo "ERROR: network tools builder left incomplete staging" >&2; exit 1; }
fi
if [ "$NEED_X11" -eq 1 ]; then
    echo "==> Preparing the desktop X11 runtime..."
    VINIX_ARCH=aarch64 VINIX_USERLAND_STAGING="$SYSROOT" "$SCRIPT_DIR/scripts/build-x11-aarch64.sh"
    x11_ready || { echo "ERROR: X11 builder left incomplete staging" >&2; exit 1; }
fi
if [ "$NEED_FIREFOX" -eq 1 ]; then
    echo "==> Preparing the desktop Firefox runtime..."
    VINIX_ARCH=aarch64 "$SCRIPT_DIR/scripts/build-firefox-aarch64.sh"
    firefox_ready || { echo "ERROR: Firefox builder left incomplete staging" >&2; exit 1; }
fi

# X11 is incorporated into the base by the userland builder. Reassemble after
# preparing layers, or when a pre-existing base predates X11 integration.
if [ "$NEED_USERLAND" -eq 1 ] || [ "$NEED_NETWORK" -eq 1 ] ||
   [ "$NEED_X11" -eq 1 ] || [ "$NEED_FIREFOX" -eq 1 ] ||
   ! archive_has ./usr/bin/Xorg ./usr/bin/Xvfb ./usr/bin/startx; then
    echo "==> Assembling the desktop base userland..."
    build_userland 0
    if ! archive_has ./usr/bin/vim ./usr/bin/Xorg ./usr/bin/Xvfb ./usr/bin/startx; then
        echo "ERROR: rebuilt userland lacks the required desktop X11 runtime" >&2
        exit 1
    fi
fi
