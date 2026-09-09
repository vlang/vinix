#!/bin/sh
# Build a Finder-launchable native ui2 app. The normal distributable is a small
# network installer; an explicit option can bundle a payload for offline use.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SCRIPT_DIR="$ROOT/installer/macos"
BUILD_DIR=${VINIX_INSTALLER_BUILD_DIR:-"$ROOT/build/vinix-installer"}
APP="$BUILD_DIR/Vinix Installer.app"
PAYLOAD_DIR=${VINIX_INSTALLER_PAYLOAD_DIR:-}
BUNDLE_PAYLOAD=0

case "${1:-}" in
    '') ;;
    --with-payload) BUNDLE_PAYLOAD=1 ;;
    --thin) ;;
    --help|-h)
        echo "usage: $0 [--with-payload]"
        echo "  --with-payload  bundle the current boot payload for an offline installer"
        exit 0
        ;;
    *) echo "error: unknown option: $1" >&2; exit 1 ;;
esac

V=${V:-}
. "$ROOT/build-support/find-v.sh"
[ -f "$ROOT/third_party/ui2/v.mod" ] || {
    echo "ERROR: ui2 not found. Clone https://github.com/vlang/ui2 into third_party/ui2." >&2
    exit 1
}

if [ "$BUNDLE_PAYLOAD" -eq 1 ]; then
    if [ -n "$PAYLOAD_DIR" ]; then
        BOOT_EFI="$PAYLOAD_DIR/BOOTAA64.EFI"
        LIMINE_CONF="$PAYLOAD_DIR/limine.conf"
        VINIX_KERNEL="$PAYLOAD_DIR/vinix"
        INITRAMFS="$PAYLOAD_DIR/initramfs.tar"
    else
        BOOT_EFI="$ROOT/boot-image/limine-bin/BOOTAA64.EFI"
        LIMINE_CONF="$ROOT/build-support/limine.conf"
        VINIX_KERNEL="$ROOT/kernel/bin/vinix"
        INITRAMFS="$ROOT/build-support/init-aarch64/initramfs-desktop.tar"
    fi

    for payload_file in "$BOOT_EFI" "$LIMINE_CONF" "$VINIX_KERNEL" "$INITRAMFS"; do
        [ -f "$payload_file" ] || {
            echo "ERROR: missing installer payload file: $payload_file" >&2
            echo "Build Limine and the compact ARM64 desktop, or set VINIX_INSTALLER_PAYLOAD_DIR." >&2
            exit 1
        }
    done
fi

case "$APP" in "$BUILD_DIR"/*.app) /bin/rm -rf -- "$APP" ;; *) exit 1 ;; esac
/bin/mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
/bin/cp "$SCRIPT_DIR/Info.plist" "$APP/Contents/Info.plist"
/bin/cp "$SCRIPT_DIR/install-vinix.sh" "$SCRIPT_DIR/fetch-vinix-payload.sh" \
    "$SCRIPT_DIR/vinix_auto.py" "$APP/Contents/Resources/"
/bin/chmod 755 "$APP/Contents/Resources/install-vinix.sh" \
    "$APP/Contents/Resources/fetch-vinix-payload.sh"

echo "==> Compiling native ui2 installer"
"$V" -prod -path "@vlib|@vmodules|$ROOT/third_party" \
    -d "vinix_source_root=$ROOT" \
    -o "$APP/Contents/MacOS/vinix-installer" "$SCRIPT_DIR"

if [ "$BUNDLE_PAYLOAD" -eq 1 ]; then
    echo "==> Bundling Vinix desktop payload"
    /bin/mkdir -p "$APP/Contents/Resources/payload"
    /bin/cp "$BOOT_EFI" "$APP/Contents/Resources/payload/BOOTAA64.EFI"
    /bin/cp "$LIMINE_CONF" "$APP/Contents/Resources/payload/limine.conf"
    /bin/cp "$VINIX_KERNEL" "$APP/Contents/Resources/payload/vinix"
    /bin/cp "$INITRAMFS" "$APP/Contents/Resources/payload/initramfs.tar"
fi

/usr/bin/codesign --force --deep --sign - "$APP" >/dev/null
echo "==> Built $APP"
