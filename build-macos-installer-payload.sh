#!/bin/sh
# Package the current Apple M1 boot files as the image fetched by the small
# macOS installer. Rebuild the app after changing the checksum printed here.
set -eu
TZ=UTC
export TZ

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
OUTPUT_DIR=${VINIX_INSTALLER_RELEASE_DIR:-"$ROOT/build/vinix-installer-release"}
ARCHIVE="$OUTPUT_DIR/Vinix-M1-Payload.zip"
CHECKSUM="$ARCHIVE.sha256"
STAGING=$(mktemp -d "${TMPDIR:-/tmp}/vinix-payload.XXXXXX")

cleanup() {
    case "$STAGING" in
        "${TMPDIR:-/tmp}"/vinix-payload.*) /bin/rm -rf -- "$STAGING" ;;
    esac
}
trap cleanup EXIT HUP INT TERM

copy_payload_file() {
    source=$1
    destination=$2
    [ -f "$source" ] || {
        echo "ERROR: missing installer payload file: $source" >&2
        echo "Build Limine and the compact ARM64 desktop first." >&2
        exit 1
    }
    COPYFILE_DISABLE=1 /bin/cp -p "$source" "$STAGING/$destination"
}

copy_payload_file "$ROOT/boot-image/limine-bin/BOOTAA64.EFI" BOOTAA64.EFI
copy_payload_file "$ROOT/build-support/limine.conf" limine.conf
copy_payload_file "$ROOT/kernel/bin/vinix" vinix
copy_payload_file "$ROOT/build-support/init-aarch64/initramfs-desktop.tar" initramfs.tar

/bin/mkdir -p "$OUTPUT_DIR"
case "$ARCHIVE" in "$OUTPUT_DIR"/Vinix-M1-Payload.zip) /bin/rm -f -- "$ARCHIVE" "$CHECKSUM" ;; esac

echo "==> Compressing Vinix M1 payload"
(cd "$STAGING" && /usr/bin/zip -X -9 -q "$ARCHIVE" \
    BOOTAA64.EFI limine.conf vinix initramfs.tar)
(cd "$OUTPUT_DIR" && /usr/bin/unzip -tq Vinix-M1-Payload.zip)
[ "$(stat -f %z "$ARCHIVE")" -lt 2147483648 ] || {
    echo "ERROR: payload exceeds GitHub's 2 GiB release-asset limit" >&2
    exit 1
}
(cd "$OUTPUT_DIR" && /usr/bin/shasum -a 256 Vinix-M1-Payload.zip \
    > Vinix-M1-Payload.zip.sha256)

echo "==> Built $ARCHIVE"
/bin/cat "$CHECKSUM"
echo "Update PAYLOAD_SHA256 in installer/macos/fetch-vinix-payload.sh before publishing a changed payload."
