#!/bin/bash
# Build a private host QEMU whose VirtIO tablet forwards horizontal wheels.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/build/qemu-horizontal"
VERSION=11.1.1
SHA256=079ffbff8a7111bbc89022107cbabf3bbfd614d5fc9d7cc675991196aca12482
ARCHIVE="$WORK/downloads/qemu-$VERSION.tar.xz"
SOURCE="$WORK/qemu-$VERSION"
PATCH="$ROOT/patches/qemu/virtio-horizontal-wheel.patch"
OUTPUT="$WORK/bin/qemu-system-aarch64"
STAMP="$WORK/patch.sha256"
patch_digest=$(cat "$PATCH" "$ROOT/scripts/build-qemu-input.sh" \
    "$ROOT/build-support/generator-sdk.v" "$ROOT/build-support/generatorsdk/core.v" \
    | shasum -a 256 | awk '{print $1}')
if [ -x "$OUTPUT" ] && [ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$patch_digest" ]; then
    exit 0
fi
# Provision QEMU's upstream generator SDK separately. V verifies its declared
# tomli dependency without launching an interpreter or package installer.
python=$("$ROOT/build-support/generator-sdk" qemu \
    "${VINIX_QEMU_BUILD_PYTHON:-$WORK/python/bin/python3}")
mkdir -p "$WORK/downloads" "$WORK/obj" "$WORK/bin"
LOCK="$WORK/.lock"
while ! ln -s "$$" "$LOCK" 2>/dev/null; do
    owner=$(readlink "$LOCK" 2>/dev/null || true)
    if [ -n "$owner" ] && ! kill -0 "$owner" 2>/dev/null; then rm -f "$LOCK"; continue; fi
    sleep 1
done
trap 'if [ "$(readlink "$LOCK" 2>/dev/null || true)" = "$$" ]; then rm -f "$LOCK"; fi' EXIT
if [ -x "$OUTPUT" ] && [ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$patch_digest" ]; then exit 0; fi
if [ ! -f "$ARCHIVE" ] || [ "$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')" != "$SHA256" ]; then
    curl -fL --retry 3 -o "$ARCHIVE.partial" "https://download.qemu.org/qemu-$VERSION.tar.xz"
    echo "$SHA256  $ARCHIVE.partial" | shasum -a 256 -c -
    mv "$ARCHIVE.partial" "$ARCHIVE"
fi
if [ ! -f "$SOURCE/configure" ]; then
    tar -xJf "$ARCHIVE" -C "$WORK"
fi
if git -C "$SOURCE" apply --check "$PATCH" 2>/dev/null; then
    git -C "$SOURCE" apply "$PATCH"
elif ! git -C "$SOURCE" apply --reverse --check "$PATCH" 2>/dev/null; then
    echo "ERROR: QEMU source does not match the horizontal wheel patch: $SOURCE" >&2
    exit 1
fi
if [ "$(uname -s)" = Darwin ]; then
    # Homebrew's pkg-config resolves GLib, Pixman and libslirp.
    display_flags=(--enable-cocoa --enable-hvf)
else
    display_flags=()
fi
echo "==> Building QEMU $VERSION with horizontal VirtIO scrolling (first run only)"
(
    cd "$WORK/obj"
    "$SOURCE/configure" --python="$python" --enable-download --target-list=aarch64-softmmu --enable-slirp \
        --datadir="$SOURCE/pc-bios" --with-suffix= \
        --disable-docs --disable-tools --disable-guest-agent --disable-debug-info \
        --disable-opengl --disable-virglrenderer --disable-gtk --disable-sdl --disable-dbus-display \
        "${display_flags[@]}"
    ninja -j"${VINIX_QEMU_BUILD_JOBS:-8}" qemu-system-aarch64
)
cp "$WORK/obj/qemu-system-aarch64" "$OUTPUT.partial"
if [ "$(uname -s)" = Darwin ]; then
    xattr -cr "$OUTPUT.partial"
    codesign --force --sign - --entitlements "$ROOT/build-support/venus/hvf-entitlements.plist" "$OUTPUT.partial"
fi
mv "$OUTPUT.partial" "$OUTPUT"
printf '%s\n' "$patch_digest" > "$STAMP"
echo "==> Built $OUTPUT"
