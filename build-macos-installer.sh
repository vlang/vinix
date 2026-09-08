#!/bin/sh
# Build a Finder-launchable native ui2 app and optionally bundle the current
# Vinix desktop boot payload for transfer to another original-M1 Mac.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SCRIPT_DIR="$ROOT/installer/macos"
BUILD_DIR=${VINIX_INSTALLER_BUILD_DIR:-"$ROOT/build/vinix-installer"}
APP="$BUILD_DIR/Vinix Installer.app"
THIN=0

case "${1:-}" in
    '') ;;
    --thin) THIN=1 ;;
    --help|-h)
        echo "usage: $0 [--thin]"
        echo "  --thin  refer to this checkout instead of copying the boot payload"
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

PAYLOAD_FILES="
boot-image/limine-bin/BOOTAA64.EFI
build-support/limine.conf
kernel/bin/vinix
build-support/init-aarch64/initramfs-desktop.tar
"
for relative in $PAYLOAD_FILES; do
    [ -f "$ROOT/$relative" ] || {
        echo "ERROR: missing $relative" >&2
        echo "Build Limine and the compact ARM64 desktop before packaging the installer." >&2
        exit 1
    }
done

case "$APP" in "$BUILD_DIR"/*.app) /bin/rm -rf -- "$APP" ;; *) exit 1 ;; esac
/bin/mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
/bin/cp "$SCRIPT_DIR/Info.plist" "$APP/Contents/Info.plist"
/bin/cp "$SCRIPT_DIR/install-vinix.sh" "$SCRIPT_DIR/vinix_auto.py" "$APP/Contents/Resources/"
/bin/chmod 755 "$APP/Contents/Resources/install-vinix.sh"

echo "==> Compiling native ui2 installer"
"$V" -prod -path "@vlib|@vmodules|$ROOT/third_party" \
    -d "vinix_source_root=$ROOT" \
    -o "$APP/Contents/MacOS/vinix-installer" "$SCRIPT_DIR"

if [ "$THIN" -eq 0 ]; then
    echo "==> Bundling Vinix desktop payload"
    /bin/mkdir -p "$APP/Contents/Resources/payload"
    /bin/cp "$ROOT/boot-image/limine-bin/BOOTAA64.EFI" "$APP/Contents/Resources/payload/"
    /bin/cp "$ROOT/build-support/limine.conf" "$APP/Contents/Resources/payload/"
    /bin/cp "$ROOT/kernel/bin/vinix" "$APP/Contents/Resources/payload/"
    /bin/cp "$ROOT/build-support/init-aarch64/initramfs-desktop.tar" \
        "$APP/Contents/Resources/payload/initramfs.tar"
fi

/usr/bin/codesign --force --deep --sign - "$APP" >/dev/null
echo "==> Built $APP"
