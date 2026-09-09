#!/bin/sh
# Prepare a Vinix-flavoured package for the pinned upstream Asahi installer,
# then let that installer exclusively own APFS, boot policy, m1n1, and firmware.
set -eu

INSTALLER_VERSION=v0.9.1
INSTALLER_SHA256=bc5bbca9d4c57cdf3a418c52b6b402a84ae6db776dd5ad55640fdb5d119ee4b0
INSTALLER_URL="https://cdn.asahilinux.org/installer/installer-${INSTALLER_VERSION}.tar.gz"
UEFI_VERSION=uefi-only-20260905-asahi-7.1.12-1
UEFI_SHA256=4a00109b6943abf5c896ebcc791ffaa294dd87c162c7f71c6b162de22de97d60
UEFI_URL="https://cdn.asahilinux.org/os/${UEFI_VERSION}.zip"
MINIMUM_GB=16
STUB_BYTES=2499805184

usage() {
    cat <<'EOF'
usage: install-vinix.sh --confirmed --disk diskN --space-gb N [--payload PATH]

This support command is normally launched by Vinix Installer.app. It downloads
and verifies the Vinix image and upstream Asahi/m1n1 components, prepares the
Vinix ESP, and then asks for administrator and Apple machine-owner authentication.

The optional payload path selects locally built files for development or an
offline installer. Normal installations download the pinned Vinix image.
EOF
}

fail() {
    echo "error: $*" >&2
    exit 1
}

sha256() {
    /usr/bin/shasum -a 256 "$1" | /usr/bin/awk '{print $1}'
}

resolve_payload() {
    if [ -f "$PAYLOAD/BOOTAA64.EFI" ]; then
        LOADER="$PAYLOAD/BOOTAA64.EFI"
        CONFIG="$PAYLOAD/limine.conf"
        KERNEL="$PAYLOAD/vinix"
        INITRAMFS="$PAYLOAD/initramfs.tar"
    else
        LOADER="$PAYLOAD/boot-image/limine-bin/BOOTAA64.EFI"
        CONFIG="$PAYLOAD/build-support/limine.conf"
        KERNEL="$PAYLOAD/kernel/bin/vinix"
        INITRAMFS="$PAYLOAD/build-support/init-aarch64/initramfs-desktop.tar"
    fi
    for required in "$LOADER" "$CONFIG" "$KERNEL" "$INITRAMFS"; do
        [ -f "$required" ] || fail "missing Vinix payload file: $required"
    done
}

if [ "${1:-}" = "--run-prepared" ]; then
    [ "$#" -eq 4 ] || fail "invalid prepared invocation"
    WORK=$2
    TARGET_DISK=$3
    SPACE_BYTES=$4
    [ "$(id -u)" -eq 0 ] || fail "prepared installer must run as root"
    [ -f "$WORK/vinix_auto.py" ] && [ -f "$WORK/installer_data.json" ] \
        || fail "prepared installer is incomplete"
    cd "$WORK"
    export LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
    export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
    export DYLD_LIBRARY_PATH="$WORK/Frameworks/Python.framework/Versions/Current/lib"
    export DYLD_FRAMEWORK_PATH="$WORK/Frameworks"
    export SSL_CERT_FILE="$WORK/Frameworks/Python.framework/Versions/Current/etc/openssl/cert.pem"
    export REPO_BASE="$WORK"
    export EXPERT=1
    export DISTRO=Vinix
    export DISTRO_DOCS=https://github.com/vlang/vinix/tree/master/installer/macos
    export VINIX_TARGET_DISK="$TARGET_DISK"
    export VINIX_SPACE_BYTES="$SPACE_BYTES"
    exec "$WORK/Frameworks/Python.framework/Versions/3.13/bin/python3.13" "$WORK/vinix_auto.py"
fi

CONFIRMED=0
TARGET_DISK=
SPACE_GB=
PAYLOAD=
while [ "$#" -gt 0 ]; do
    case "$1" in
        --confirmed) CONFIRMED=1; shift ;;
        --disk) [ "$#" -ge 2 ] || fail "--disk needs a value"; TARGET_DISK=$2; shift 2 ;;
        --space-gb) [ "$#" -ge 2 ] || fail "--space-gb needs a value"; SPACE_GB=$2; shift 2 ;;
        --payload) [ "$#" -ge 2 ] || fail "--payload needs a value"; PAYLOAD=$2; shift 2 ;;
        --help|-h) usage; exit 0 ;;
        *) fail "unknown argument: $1" ;;
    esac
done

[ "$CONFIRMED" -eq 1 ] || fail "the graphical destructive-action confirmation was not recorded"
DISK_NUMBER=${TARGET_DISK#disk}
[ "disk${DISK_NUMBER}" = "$TARGET_DISK" ] || fail "invalid whole-disk identifier: $TARGET_DISK"
case "$DISK_NUMBER" in ''|*[!0-9]*) fail "invalid whole-disk identifier: $TARGET_DISK" ;; esac
case "$SPACE_GB" in ''|*[!0-9]*) fail "space must be a whole number of GB" ;; esac
[ "$SPACE_GB" -ge "$MINIMUM_GB" ] || fail "Vinix needs at least ${MINIMUM_GB} GB"
[ "$(uname -s)" = Darwin ] || fail "this installer runs only on macOS"
[ "$(uname -m)" = arm64 ] || fail "run natively on Apple Silicon, not under Rosetta"
BRAND=$(/usr/sbin/sysctl -n machdep.cpu.brand_string)
[ "$BRAND" = "Apple M1" ] || fail "Vinix currently supports Apple M1; this Mac reports $BRAND"
/usr/sbin/diskutil info "$TARGET_DISK" >/dev/null 2>&1 || fail "$TARGET_DISK is not present"
command -v curl >/dev/null 2>&1 || fail "curl is missing"
command -v zip >/dev/null 2>&1 || fail "zip is missing"
command -v unzip >/dev/null 2>&1 || fail "unzip is missing"

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/vinix-install.XXXXXX")
INSTALLER_ARCHIVE="$WORK/installer.tar.gz"
UEFI_ARCHIVE="$WORK/uefi.zip"

echo
echo "Vinix Installer"
echo "  target:     $TARGET_DISK"
echo "  allocation: ${SPACE_GB} GB"
echo

if [ -z "$PAYLOAD" ]; then
    PAYLOAD="$WORK/payload"
    "$SCRIPT_DIR/fetch-vinix-payload.sh" "$PAYLOAD"
else
    echo "Using local Vinix image: $PAYLOAD"
fi

resolve_payload
SPACE_BYTES=$((SPACE_GB * 1000000000))
EFI_BYTES=$((SPACE_BYTES - STUB_BYTES))
PAYLOAD_BYTES=$(( $(stat -f %z "$LOADER") + $(stat -f %z "$CONFIG") + $(stat -f %z "$KERNEL") + $(stat -f %z "$INITRAMFS") ))
[ "$(stat -f %z "$INITRAMFS")" -lt 4294967295 ] \
    || fail "initramfs.tar exceeds FAT32's 4 GB per-file limit"
[ "$PAYLOAD_BYTES" -lt $((EFI_BYTES - 500000000)) ] \
    || fail "the ${SPACE_GB} GB allocation is too small for this Vinix image"

echo "Downloading verified m1n1/Asahi installer components..."
/usr/bin/curl --no-progress-meter --fail --location --retry 3 \
    --output "$INSTALLER_ARCHIVE" "$INSTALLER_URL"
[ "$(sha256 "$INSTALLER_ARCHIVE")" = "$INSTALLER_SHA256" ] \
    || fail "Asahi installer checksum mismatch"
/usr/bin/curl --no-progress-meter --fail --location --retry 3 \
    --output "$UEFI_ARCHIVE" "$UEFI_URL"
[ "$(sha256 "$UEFI_ARCHIVE")" = "$UEFI_SHA256" ] \
    || fail "m1n1/U-Boot package checksum mismatch"

echo "Preparing Vinix boot package..."
/usr/bin/tar -xzf "$INSTALLER_ARCHIVE" -C "$WORK"
/bin/cp "$SCRIPT_DIR/vinix_auto.py" "$WORK/vinix_auto.py"
/bin/mkdir -p "$WORK/os" "$WORK/package/esp/EFI/BOOT" \
    "$WORK/package/esp/boot" "$WORK/package/esp/m1n1"
/usr/bin/unzip -p "$UEFI_ARCHIVE" esp/m1n1/boot.bin > "$WORK/package/esp/m1n1/boot.bin"
/bin/cp "$LOADER" "$WORK/package/esp/EFI/BOOT/BOOTAA64.EFI"
/bin/cp "$KERNEL" "$WORK/package/esp/boot/vinix"
/bin/cp "$INITRAMFS" "$WORK/package/esp/boot/initramfs.tar"
/usr/bin/awk '
    /^[[:space:]]*resolution:/ { next }
    /^[[:space:]]*cmdline:/ {
        print $0 " vinix.apple_gpu=1 vinix.apple_wifi=1"
        found = 1
        next
    }
    { print }
    END {
        if (!found) print "    cmdline: vinix.apple_gpu=1 vinix.apple_wifi=1"
    }
' "$CONFIG" > "$WORK/package/esp/boot/limine.conf"
(cd "$WORK/package" && /usr/bin/zip -0 -q -r "$WORK/os/vinix.zip" .)

cat > "$WORK/installer_data.json" <<'EOF'
{
  "os_list": [
    {
      "name": "Vinix",
      "default_os_name": "Vinix",
      "boot_object": "m1n1.bin",
      "next_object": "m1n1/boot.bin",
      "package": "vinix.zip",
      "external_boot": true,
      "supported_fw": ["13.5", "14.8.3"],
      "partitions": [
        {
          "name": "EFI",
          "type": "EFI",
          "size": "4GB",
          "expand": true,
          "format": "fat",
          "copy_firmware": true,
          "copy_installer_data": true,
          "source": "esp"
        }
      ]
    }
  ]
}
EOF

echo "The disk changes are performed by the upstream Asahi installer."
echo "Administrator authentication is required next."
echo
set +e
/usr/bin/caffeinate -dis /usr/bin/sudo -E "$SCRIPT_DIR/install-vinix.sh" \
    --run-prepared "$WORK" "$TARGET_DISK" "$SPACE_BYTES"
RESULT=$?
set -e
if [ "$RESULT" -eq 0 ]; then
    case "$WORK" in
        "${TMPDIR:-/tmp}"/vinix-install.*) /bin/rm -rf -- "$WORK" ;;
    esac
else
    echo
    echo "Installation stopped. Diagnostic files were retained in: $WORK" >&2
fi
exit "$RESULT"
