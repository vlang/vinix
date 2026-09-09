#!/bin/sh
# Download and verify the boot files consumed by install-vinix.sh.
set -eu

PAYLOAD_ASSET=Vinix-M1-Payload.zip
PAYLOAD_SHA256=96d2a33924f3d77418d1ea5cd82fa78294a0d29e4ad3d4996c676a147d81687c
PAYLOAD_URL="https://github.com/vlang/vinix/releases/download/m1-installer-latest/${PAYLOAD_ASSET}"

fail() {
    echo "error: $*" >&2
    exit 1
}

[ "$#" -eq 1 ] || fail "usage: fetch-vinix-payload.sh DESTINATION"
DESTINATION=$1
[ -n "$DESTINATION" ] || fail "payload destination is empty"

EXPECTED_SHA256=${VINIX_PAYLOAD_SHA256:-$PAYLOAD_SHA256}
[ "${#EXPECTED_SHA256}" -eq 64 ] || fail "invalid Vinix image checksum"
case "$EXPECTED_SHA256" in *[!0-9a-f]*) fail "invalid Vinix image checksum" ;; esac

ARCHIVE=$(mktemp "${TMPDIR:-/tmp}/vinix-payload-download.XXXXXX")
cleanup() {
    case "$ARCHIVE" in
        "${TMPDIR:-/tmp}"/vinix-payload-download.*) /bin/rm -f -- "$ARCHIVE" ;;
    esac
}
trap cleanup EXIT HUP INT TERM

echo "Downloading the Vinix image (about 1 GB)..."
/usr/bin/curl --fail --location --retry 3 --progress-bar \
    --output "$ARCHIVE" "${VINIX_PAYLOAD_URL:-$PAYLOAD_URL}"
ACTUAL_SHA256=$(/usr/bin/shasum -a 256 "$ARCHIVE" | /usr/bin/awk '{print $1}')
[ "$ACTUAL_SHA256" = "$EXPECTED_SHA256" ] || fail "Vinix image checksum mismatch"

/bin/mkdir -p "$DESTINATION"
/usr/bin/unzip -q "$ARCHIVE" -d "$DESTINATION"
for required in BOOTAA64.EFI limine.conf vinix initramfs.tar; do
    [ -s "$DESTINATION/$required" ] || fail "Vinix image is missing $required"
done
echo "Vinix image verified."
