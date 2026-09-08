#!/bin/bash
# Stage QEMU user-mode x86-64 translation and an optional Win64 Wine runtime
# for Vinix/aarch64. Both runtimes use Alpine 3.21's musl ABI.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${VINIX_X86_64_BUILD_DIR:-$SCRIPT_DIR/build-aarch64-x86-translation}"
DOWNLOADS="$BUILD_DIR/downloads"
STAGING="$BUILD_DIR/staging"
X86_ROOT="$STAGING/usr/libexec/vinix-x86_64/root"
OFFICE2010_MEDIA="${VINIX_OFFICE2010_MEDIA:-}"
OFFICE2010_PREFIX="${VINIX_OFFICE2010_PREFIX:-}"

ALPINE_MIRROR="${ALPINE_MIRROR:-https://dl-cdn.alpinelinux.org/alpine/v3.21}"
NATIVE_ARCH=aarch64
GUEST_ARCH=x86_64
WITH_WINE=1

case "${1:-}" in
    "") ;;
    --translator-only) WITH_WINE=0 ;;
    --help|-h)
        echo "usage: $0 [--translator-only]"
        echo "  default: stage the translator, x86-64 musl runtime, Wine and Calculator"
        echo "  --translator-only: omit Wine and the Windows test applications"
        exit 0
        ;;
    *)
        echo "unknown option: $1" >&2
        exit 2
        ;;
esac

for tool in curl python3 tar clang ld.lld file; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "missing build tool: $tool" >&2
        exit 1
    fi
done
if [ "$WITH_WINE" -eq 1 ] && ! command -v x86_64-w64-mingw32-gcc >/dev/null 2>&1; then
    echo "missing build tool: x86_64-w64-mingw32-gcc" >&2
    echo "install mingw-w64, or use --translator-only" >&2
    exit 1
fi
for directory in "$OFFICE2010_MEDIA" "$OFFICE2010_PREFIX"; do
    if [ -n "$directory" ] && [ ! -d "$directory" ]; then
        echo "Office 2010 input is not a directory: $directory" >&2
        exit 1
    fi
done
if [ -n "$OFFICE2010_MEDIA" ]; then
    office_setup=''
    for candidate in x64/setup.exe x64/SETUP.EXE X64/setup.exe X64/SETUP.EXE; do
        if [ -f "$OFFICE2010_MEDIA/$candidate" ]; then
            office_setup="$OFFICE2010_MEDIA/$candidate"
            break
        fi
    done
    if [ -z "$office_setup" ]; then
        echo "Office 2010 media does not contain x64/setup.exe: $OFFICE2010_MEDIA" >&2
        exit 1
    fi
fi
if [ -n "$OFFICE2010_PREFIX" ]; then
    office_word="$OFFICE2010_PREFIX/drive_c/Program Files/Microsoft Office/Office14/WINWORD.EXE"
    if [ ! -f "$office_word" ]; then
        echo "Office 2010 prefix does not contain Office14/WINWORD.EXE: $OFFICE2010_PREFIX" >&2
        exit 1
    fi
    case "$(file -b "$office_word")" in
        *PE32+*x86-64*) ;;
        *)
            echo "Office 2010 WINWORD.EXE is not an x86-64 PE binary: $office_word" >&2
            exit 1
            ;;
    esac
fi

mkdir -p "$DOWNLOADS"
rm -rf "$STAGING"
mkdir -p "$STAGING/root" "$STAGING/usr/bin" "$STAGING/usr/share/vinix" \
    "$STAGING/usr/share/wine" "$X86_ROOT"

fetch_index() {
    local architecture="$1" repository="$2"
    local index="$DOWNLOADS/${architecture}_${repository}_APKINDEX"
    local archive="$DOWNLOADS/${architecture}_${repository}_APKINDEX.tar.gz"
    if [ ! -f "$index" ]; then
        echo "  fetching Alpine $architecture/$repository index" >&2
        curl -fL --retry 3 -o "$archive" \
            "$ALPINE_MIRROR/$repository/$architecture/APKINDEX.tar.gz"
        tar xOf "$archive" APKINDEX > "$index"
    fi
    printf '%s\n' "$index"
}

download_package() {
    local architecture="$1" repository="$2" filename="$3" destination="$4"
    local archive="$DOWNLOADS/${architecture}_${filename}"
    if [ ! -f "$archive" ]; then
        echo "  downloading $architecture/$filename"
        curl -fL --retry 3 -o "$archive.partial" \
            "$ALPINE_MIRROR/$repository/$architecture/$filename"
        mv "$archive.partial" "$archive"
    fi
    echo "  extracting $architecture/$filename"
    # APK signatures, metadata and payload are concatenated tar streams. The
    # host tar can report the trailing stream after extracting successfully.
    tar xzf "$archive" -C "$destination" 2>/dev/null || true
    rm -f "$destination/.PKGINFO" "$destination/.SIGN"* \
        "$destination/.trigger"* "$destination/.pre-"* "$destination/.post-"*
}

NATIVE_MAIN="$(fetch_index "$NATIVE_ARCH" main)"
NATIVE_COMMUNITY="$(fetch_index "$NATIVE_ARCH" community)"
GUEST_MAIN="$(fetch_index "$GUEST_ARCH" main)"
GUEST_COMMUNITY="$(fetch_index "$GUEST_ARCH" community)"

echo "=== staging the $NATIVE_ARCH x86-64 translator ==="
python3 "$SCRIPT_DIR/build-support/alpine-resolve.py" \
    --index main "$NATIVE_MAIN" \
    --index community "$NATIVE_COMMUNITY" \
    qemu-x86_64 > "$BUILD_DIR/native-packages"
while IFS=$'\t' read -r repository filename; do
    [ -n "$filename" ] || continue
    download_package "$NATIVE_ARCH" "$repository" "$filename" "$STAGING"
done < "$BUILD_DIR/native-packages"

guest_packages=(busybox)
if [ "$WITH_WINE" -eq 1 ]; then
    guest_packages+=(font-liberation wine)
fi

echo "=== staging the $GUEST_ARCH musl runtime ==="
python3 "$SCRIPT_DIR/build-support/alpine-resolve.py" \
    --index main "$GUEST_MAIN" \
    --index community "$GUEST_COMMUNITY" \
    "${guest_packages[@]}" > "$BUILD_DIR/guest-packages"
while IFS=$'\t' read -r repository filename; do
    [ -n "$filename" ] || continue
    download_package "$GUEST_ARCH" "$repository" "$filename" "$X86_ROOT"
done < "$BUILD_DIR/guest-packages"

# Absolute package symlinks would otherwise escape the private x86 root and
# resolve to native AArch64 files. Materialise their in-root targets instead.
find "$X86_ROOT" -type l | while IFS= read -r link; do
    target="$(readlink "$link")"
    case "$target" in
        /*) real="$X86_ROOT$target" ;;
        *) continue ;;
    esac
    if [ -f "$real" ]; then
        rm -f "$link"
        cp "$real" "$link"
    fi
done

echo "=== building the translated Linux smoke fixture ==="
clang --target=x86_64-linux-none -c \
    "$SCRIPT_DIR/tests/x86-translation/smoke.S" \
    -o "$BUILD_DIR/x86-translation-smoke.o"
ld.lld -m elf_x86_64 -static -o "$STAGING/usr/share/vinix/x86-translation-smoke" \
    "$BUILD_DIR/x86-translation-smoke.o"
install -m755 "$SCRIPT_DIR/build-support/x86-translation/run-x86-64" \
    "$STAGING/usr/bin/run-x86-64"
install -m755 "$SCRIPT_DIR/tests/x86-translation/smoke.sh" \
    "$STAGING/root/x86-translation-smoke.sh"

if [ "$WITH_WINE" -eq 1 ]; then
    echo "=== building the Win64 test applications ==="
    # Wine's wine.inf DefaultInstall pass relies on Linux facilities Vinix does
    # not expose yet and can wait forever during first boot. Wine explicitly
    # supports a "disable" update stamp; the built-in DLLs remain available from
    # WINEDLLPATH, so seed a lightweight Win64 prefix with that update disabled.
    # Keep prefix link targets below ustar's 100-byte link-name limit: several
    # Windows Runtime DLL names are long enough to exceed it with the private
    # runtime's canonical path.
    ln -snf /usr/libexec/vinix-x86_64/root/usr/lib/wine/x86_64-windows \
        "$STAGING/usr/share/wine/x86_64-windows"
    for prefix in "$STAGING/root/.wine-x86_64" \
        "$STAGING/root/.wine-office2010-x86_64"; do
        mkdir -p "$prefix/drive_c/windows/system32" "$prefix/dosdevices"
        install -m644 "$SCRIPT_DIR/build-support/x86-translation/wine-update-disabled" \
            "$prefix/.update-timestamp"
        ln -snf ../drive_c "$prefix/dosdevices/c:"
        ln -snf / "$prefix/dosdevices/z:"
        # The skipped INF pass normally copies Wine's built-in PE modules here.
        # Link them from the immutable private runtime instead, keeping one copy
        # of the several-hundred-megabyte DLL set in the image.
        for builtin in "$X86_ROOT/usr/lib/wine/x86_64-windows/"*; do
            [ -f "$builtin" ] || continue
            ln -snf "/usr/share/wine/x86_64-windows/${builtin##*/}" \
                "$prefix/drive_c/windows/system32/${builtin##*/}"
        done
    done
    x86_64-w64-mingw32-gcc -Os -s -mwindows \
        "$SCRIPT_DIR/tests/wine/calculator.c" \
        -o "$STAGING/usr/share/wine/vinix-calculator.exe"
    x86_64-w64-mingw32-gcc -Os -s \
        "$SCRIPT_DIR/tests/wine/smoke.c" \
        -o "$STAGING/usr/share/wine/vinix-wine-smoke.exe"
    install -m755 "$SCRIPT_DIR/build-support/x86-translation/run-wine-x86-64" \
        "$STAGING/usr/bin/run-wine-x86-64"
    for launcher in wine wine64 wineserver msiexec notepad regedit regsvr32 \
        wineboot winecfg wineconsole winefile winemine winepath calculator \
        office2010-setup word2010; do
        install -m755 "$SCRIPT_DIR/build-support/x86-translation/run-wine-x86-64" \
            "$STAGING/usr/bin/$launcher"
    done
    install -m755 "$SCRIPT_DIR/tests/wine/wine-smoke" \
        "$STAGING/usr/bin/wine-smoke"

    if [ -n "$OFFICE2010_MEDIA" ]; then
        echo "=== staging licensed Office 2010 media ==="
        mkdir -p "$STAGING/root/office2010-media"
        cp -a "$OFFICE2010_MEDIA/." "$STAGING/root/office2010-media/"
    fi
    if [ -n "$OFFICE2010_PREFIX" ]; then
        echo "=== staging the supplied Office 2010 Wine prefix ==="
        cp -a "$OFFICE2010_PREFIX/." "$STAGING/root/.wine-office2010-x86_64/"
        install -m644 "$SCRIPT_DIR/build-support/x86-translation/wine-update-disabled" \
            "$STAGING/root/.wine-office2010-x86_64/.update-timestamp"
    fi
fi

file "$STAGING/usr/bin/qemu-x86_64" \
    "$STAGING/usr/share/vinix/x86-translation-smoke"
echo
echo "x86-64 translation layer staged: $(du -sh "$STAGING" | cut -f1)"
echo "output: $STAGING"
if [ "$WITH_WINE" -eq 1 ]; then
    echo "guest commands: x86-translation-smoke.sh, wine-smoke, calculator, word2010"
    echo "Office 2010 setup: office2010-setup /path/to/x64/setup.exe"
else
    echo "guest command: x86-translation-smoke.sh"
fi
