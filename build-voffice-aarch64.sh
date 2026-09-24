#!/bin/bash
# Package VOffice Writer and Calc for Vinix as the release asset that
# `pkg install voffice` downloads. The desktop image never runs this: VOffice
# is an optional application whose source is a separate checkout.
#
# Usage: ./build-voffice-aarch64.sh [--ref=REF] [--publish]
#   --ref builds from a clean export of REF in the office checkout instead of
#   its working tree, e.g. the branch a release was built from.
#   --publish uploads the bundle and its checksum to the latest release of
#   VINIX_VOFFICE_RELEASE_REPO (default vlang/office) with gh. It refuses
#   uncommitted source and a VERSION other than that release's tag.
#
# The office source is VINIX_OFFICE_SOURCE, a sibling ../office checkout, or
# third_party/office. ui2 is chosen the same way as for the desktop.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/build-support/find-v.sh"

PUBLISH=0
REF=
for arg in "$@"; do
    case "$arg" in
        --publish) PUBLISH=1 ;;
        --ref=*) REF="${arg#*=}" ;;
        --help|-h)
            sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "ERROR: unknown option: $arg" >&2
            exit 1
            ;;
    esac
done

if [ -n "${VINIX_UI2_SOURCE:-}" ]; then
    UI2_SOURCE="$VINIX_UI2_SOURCE"
elif [ -f "$SCRIPT_DIR/../ui2/v.mod" ]; then
    UI2_SOURCE="$SCRIPT_DIR/../ui2"
else
    UI2_SOURCE="$SCRIPT_DIR/third_party/ui2"
fi
if [ -n "${VINIX_OFFICE_SOURCE:-}" ]; then
    OFFICE_SOURCE="$VINIX_OFFICE_SOURCE"
elif [ -f "$SCRIPT_DIR/../office/v.mod" ]; then
    OFFICE_SOURCE="$SCRIPT_DIR/../office"
else
    OFFICE_SOURCE="$SCRIPT_DIR/third_party/office"
fi

BUILD_DIR="${VINIX_VOFFICE_BUILD_DIR:-$SCRIPT_DIR/build-aarch64-voffice}"
USERLAND_BUILD_DIR="${VINIX_AARCH64_USERLAND_BUILD_DIR:-$SCRIPT_DIR/build-aarch64-userland}"
SYSROOT="${VINIX_AARCH64_SYSROOT:-$USERLAND_BUILD_DIR/staging}"
LLVM_BIN="${LLVM_BIN:-/opt/homebrew/opt/llvm/bin}"
if [ ! -x "$LLVM_BIN/clang" ]; then
    LLVM_CLANG="$(command -v clang || true)"
    if [ -n "$LLVM_CLANG" ]; then
        LLVM_BIN="$(dirname "$LLVM_CLANG")"
    fi
fi
CC_SHIM="$SCRIPT_DIR/build-support/aarch64-cc-shim"
RELEASE_REPO="${VINIX_VOFFICE_RELEASE_REPO:-vlang/office}"
ASSET=VOffice-vinix-aarch64.tar.gz

if [ ! -f "$OFFICE_SOURCE/v.mod" ] || [ ! -f "$OFFICE_SOURCE/cmd/excel/main.v" ] ||
   [ ! -f "$OFFICE_SOURCE/cmd/word/main.v" ]; then
    echo "ERROR: VOffice not found at $OFFICE_SOURCE." >&2
    echo "Set VINIX_OFFICE_SOURCE or check it out beside Vinix as ../office." >&2
    exit 1
fi
if [ ! -f "$UI2_SOURCE/v.mod" ]; then
    echo "ERROR: ui2 not found at $UI2_SOURCE." >&2
    exit 1
fi
if [ ! -f "$SYSROOT/usr/lib/libc.a" ] || [ ! -d "$SYSROOT/usr/include" ]; then
    echo "ERROR: Alpine development sysroot is incomplete: $SYSROOT" >&2
    echo "Run ./build-userland-aarch64.sh first." >&2
    exit 1
fi
GCCLIB="$(find "$SYSROOT/usr/lib/gcc/aarch64-alpine-linux-musl" \
    -mindepth 1 -maxdepth 1 -type d 2>/dev/null | LC_ALL=C sort | tail -n1)"
if [ -z "$GCCLIB" ] || [ ! -f "$GCCLIB/libgcc.a" ]; then
    echo "ERROR: Alpine GCC runtime not found below $SYSROOT/usr/lib/gcc" >&2
    exit 1
fi
if [ ! -x "$LLVM_BIN/clang" ] || [ ! -x "$LLVM_BIN/llvm-strip" ]; then
    echo "ERROR: LLVM clang and llvm-strip not found in $LLVM_BIN" >&2
    exit 1
fi

# A release asset must be built from committed source that says which release
# it is. The working tree of a live checkout is neither.
if [ -n "$REF" ]; then
    SOURCE_EXPORT="$BUILD_DIR/source"
    rm -rf "$SOURCE_EXPORT"
    mkdir -p "$SOURCE_EXPORT"
    git -C "$OFFICE_SOURCE" archive "$REF" | tar -x -C "$SOURCE_EXPORT"
    echo "==> Using VOffice $REF ($(git -C "$OFFICE_SOURCE" rev-parse --short "$REF"))"
    OFFICE_SOURCE="$SOURCE_EXPORT"
elif [ "$PUBLISH" -eq 1 ] && git -C "$OFFICE_SOURCE" rev-parse --git-dir >/dev/null 2>&1 &&
     [ -n "$(git -C "$OFFICE_SOURCE" status --porcelain --untracked-files=no)" ]; then
    echo "ERROR: $OFFICE_SOURCE has uncommitted changes; publish a clean build with --ref=REF" >&2
    exit 1
fi
if [ "$PUBLISH" -eq 1 ]; then
    command -v gh >/dev/null 2>&1 || { echo "ERROR: --publish needs gh" >&2; exit 1; }
    RELEASE_TAG="$(gh release view --repo "$RELEASE_REPO" --json tagName --jq .tagName)"
    SOURCE_VERSION="$(sed -n '1p' "$OFFICE_SOURCE/VERSION" 2>/dev/null || true)"
    if [ "v$SOURCE_VERSION" != "$RELEASE_TAG" ]; then
        echo "ERROR: VOffice source is version '${SOURCE_VERSION:-unknown}' but the latest $RELEASE_REPO release is $RELEASE_TAG" >&2
        exit 1
    fi
fi

echo "==> Building VOffice Calc and Writer for aarch64 Vinix..."
mkdir -p "$BUILD_DIR"
python3 "$SCRIPT_DIR/desktop/tools/build_voffice.py" \
    --repo "$SCRIPT_DIR" --office-source "$OFFICE_SOURCE" --ui2-source "$UI2_SOURCE" \
    --output "$BUILD_DIR/bin" --work "$BUILD_DIR/work" \
    --v "$V" --arch arm64 --clang "$LLVM_BIN/clang" --strip "$LLVM_BIN/llvm-strip" \
    --target aarch64-linux-musl --sysroot "$SYSROOT" --gcclib "$GCCLIB" \
    --cc-shim "$CC_SHIM" --llvm-bin "$LLVM_BIN"

# One top-level directory holding what `pkg install voffice` copies below
# /usr/bin: both executables, and the artwork and translations they look up
# beside themselves.
echo "==> Packaging $ASSET..."
BUNDLE="$BUILD_DIR/bundle"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/voffice/assets/ribbon" "$BUNDLE/voffice/translations"
install -m755 "$BUILD_DIR/bin/voffice-writer" "$BUILD_DIR/bin/voffice-calc" \
    "$BUNDLE/voffice/"
install -m644 "$OFFICE_SOURCE/assets/logo.png" "$BUNDLE/voffice/assets/logo.png"
install -m644 "$OFFICE_SOURCE"/assets/ribbon/*.png "$BUNDLE/voffice/assets/ribbon/"
cp -R "$OFFICE_SOURCE/translations/." "$BUNDLE/voffice/translations/"
if [ -f "$OFFICE_SOURCE/VERSION" ]; then
    install -m644 "$OFFICE_SOURCE/VERSION" "$BUNDLE/voffice/VERSION"
fi

# COPYFILE_DISABLE keeps macOS from adding ._ members that the guest would
# unpack as stray files. Publish the archive and its checksum atomically.
ARCHIVE="$BUILD_DIR/$ASSET"
ARCHIVE_TMP="$(mktemp "$BUILD_DIR/.$ASSET.XXXXXX")"
trap 'rm -f "$ARCHIVE_TMP" "$ARCHIVE_TMP.sha256"' EXIT
COPYFILE_DISABLE=1 tar --format=ustar -czf "$ARCHIVE_TMP" -C "$BUNDLE" voffice
if command -v sha256sum >/dev/null 2>&1; then
    digest="$(sha256sum "$ARCHIVE_TMP" | awk '{ print $1 }')"
else
    digest="$(shasum -a 256 "$ARCHIVE_TMP" | awk '{ print $1 }')"
fi
printf '%s  %s\n' "$digest" "$ASSET" > "$ARCHIVE_TMP.sha256"
chmod 644 "$ARCHIVE_TMP" "$ARCHIVE_TMP.sha256"
mv -f "$ARCHIVE_TMP" "$ARCHIVE"
mv -f "$ARCHIVE_TMP.sha256" "$ARCHIVE.sha256"
trap - EXIT
echo "    $ARCHIVE"
echo "    $ARCHIVE.sha256"

if [ "$PUBLISH" -eq 1 ]; then
    echo "==> Uploading to $RELEASE_REPO release $RELEASE_TAG..."
    gh release upload "$RELEASE_TAG" "$ARCHIVE" "$ARCHIVE.sha256" --repo "$RELEASE_REPO" --clobber
else
    echo "Publish with: $0 --publish"
fi
