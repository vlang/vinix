#!/bin/bash
# Stage QEMU user-mode x86 translation and optional Win64/Win32 Wine runtimes
# for Vinix/aarch64. All runtimes use Alpine 3.21's musl ABI.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${VINIX_X86_64_BUILD_DIR:-$SCRIPT_DIR/build-aarch64-x86-translation}"
DOWNLOADS="$BUILD_DIR/downloads"
STAGING="$BUILD_DIR/staging"
X86_ROOT="$STAGING/usr/libexec/vinix-x86_64/root"
I386_ROOT="$STAGING/usr/libexec/vinix-i386/root"
OFFICE2010_MEDIA="${VINIX_OFFICE2010_MEDIA:-}"
OFFICE2010_PREFIX="${VINIX_OFFICE2010_PREFIX:-}"
WORD2013_MEDIA="${VINIX_WORD2013_MEDIA:-}"
WORD2013_PREFIX="${VINIX_WORD2013_PREFIX:-}"

ALPINE_MIRROR="${ALPINE_MIRROR:-https://dl-cdn.alpinelinux.org/alpine/v3.21}"
NATIVE_ARCH=aarch64
GUEST_ARCH=x86_64
GUEST32_ARCH=x86
WITH_WINE=1

case "${1:-}" in
    "") ;;
    --translator-only) WITH_WINE=0 ;;
    --help|-h)
        echo "usage: $0 [--translator-only]"
        echo "  default: stage the x86-64/i386 translators, Wine and Calculator"
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
if [ "$WITH_WINE" -eq 1 ] &&
   { ! command -v x86_64-w64-mingw32-gcc >/dev/null 2>&1 ||
     ! command -v i686-w64-mingw32-gcc >/dev/null 2>&1; }; then
    echo "missing build tools: x86_64-w64-mingw32-gcc and i686-w64-mingw32-gcc" >&2
    echo "install mingw-w64, or use --translator-only" >&2
    exit 1
fi
for directory in "$OFFICE2010_MEDIA" "$OFFICE2010_PREFIX" \
    "$WORD2013_MEDIA" "$WORD2013_PREFIX"; do
    if [ -n "$directory" ] && [ ! -d "$directory" ]; then
        echo "Office input is not a directory: $directory" >&2
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
if [ -n "$WORD2013_MEDIA" ]; then
    word_setup=''
    for candidate in \
        office/setup64.exe office/SETUP64.EXE \
        setup.exe SETUP.EXE; do
        if [ -f "$WORD2013_MEDIA/$candidate" ]; then
            word_setup="$WORD2013_MEDIA/$candidate"
            break
        fi
    done
    if [ -z "$word_setup" ]; then
        echo "Word 2013 media does not contain an x64 setup executable: $WORD2013_MEDIA" >&2
        exit 1
    fi
    case "$(file -b "$word_setup")" in
        *PE32+*x86-64*) ;;
        *)
            echo "Word 2013 setup is not an x86-64 PE binary: $word_setup" >&2
            exit 1
            ;;
    esac
fi
if [ -n "$WORD2013_PREFIX" ]; then
    word2013=''
    for candidate in \
        "drive_c/Program Files/Microsoft Office 15/root/office15/WINWORD.EXE" \
        "drive_c/Program Files/Microsoft Office/Office15/WINWORD.EXE"; do
        if [ -f "$WORD2013_PREFIX/$candidate" ]; then
            word2013="$WORD2013_PREFIX/$candidate"
            break
        fi
    done
    if [ -z "$word2013" ]; then
        echo "Word 2013 prefix does not contain WINWORD.EXE: $WORD2013_PREFIX" >&2
        exit 1
    fi
    case "$(file -b "$word2013")" in
        *PE32+*x86-64*) ;;
        *)
            echo "Word 2013 WINWORD.EXE is not an x86-64 PE binary: $word2013" >&2
            exit 1
            ;;
    esac
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
    "$STAGING/usr/share/wine" "$X86_ROOT" "$I386_ROOT"

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
GUEST32_MAIN="$(fetch_index "$GUEST32_ARCH" main)"
GUEST32_COMMUNITY="$(fetch_index "$GUEST32_ARCH" community)"

echo "=== staging the $NATIVE_ARCH x86 translators ==="
python3 "$SCRIPT_DIR/build-support/alpine-resolve.py" \
    --index main "$NATIVE_MAIN" \
    --index community "$NATIVE_COMMUNITY" \
    qemu-x86_64 qemu-i386 samba-winbind-clients > "$BUILD_DIR/native-packages"
while IFS=$'\t' read -r repository filename; do
    [ -n "$filename" ] || continue
    download_package "$NATIVE_ARCH" "$repository" "$filename" "$STAGING"
done < "$BUILD_DIR/native-packages"

# Wine invokes ntlm_auth from inside the translated process environment.
# Keep the native helper behind a trampoline which removes the x86 library
# search paths before execing it, otherwise the AArch64 dynamic loader is
# asked to open x86-64 libraries.
mkdir -p "$STAGING/usr/libexec/vinix-native-helpers"
mv "$STAGING/usr/bin/ntlm_auth" \
    "$STAGING/usr/libexec/vinix-native-helpers/ntlm_auth"
install -m755 "$SCRIPT_DIR/build-support/x86-translation/run-native-ntlm-auth" \
    "$STAGING/usr/bin/ntlm_auth"

guest_packages=(busybox)
if [ "$WITH_WINE" -eq 1 ]; then
    # Wine loads GnuTLS dynamically for bcrypt's asymmetric-key support, so
    # it is not part of Alpine's required Wine dependency closure. Office's
    # setup validates its product key through that API and rejects every key
    # when the provider is absent.
    # The X11 driver opens the Composite and Xinerama clients dynamically.
    # They are optional from Alpine's package perspective, but Office 2013's
    # Direct2D window remains black when either client is unavailable.
    # Direct software rendering is required by newer Office releases.  Wine is
    # an x86-64 process, so it must load an x86-64 DRI driver even though the
    # X server and desktop compositor are native AArch64 processes.
    guest_packages+=(font-carlito font-liberation gnutls libxcomposite libxinerama \
        mesa-dri-gallium wine)
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

if [ "$WITH_WINE" -eq 1 ]; then
    echo "=== staging the $GUEST32_ARCH Wine32 runtime ==="
    python3 "$SCRIPT_DIR/build-support/alpine-resolve.py" \
        --index main "$GUEST32_MAIN" \
        --index community "$GUEST32_COMMUNITY" \
        busybox font-liberation gnutls libxcomposite libxinerama \
        mesa-dri-gallium wine \
        > "$BUILD_DIR/guest32-packages"
    while IFS=$'\t' read -r repository filename; do
        [ -n "$filename" ] || continue
        download_package "$GUEST32_ARCH" "$repository" "$filename" "$I386_ROOT"
    done < "$BUILD_DIR/guest32-packages"
fi

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
find "$I386_ROOT" -type l | while IFS= read -r link; do
    target="$(readlink "$link")"
    case "$target" in
        /*) real="$I386_ROOT$target" ;;
        *) continue ;;
    esac
    if [ -f "$real" ]; then
        rm -f "$link"
        cp "$real" "$link"
    fi
done

if [ "$WITH_WINE" -eq 1 ]; then
    # Windows MSXML treats encoding="unicode" as UTF-16/UCS-2. Office 2013
    # uses that declaration, while Alpine's libxml2 rejects it by default.
    python3 "$SCRIPT_DIR/build-support/x86-translation/patch-msxml-unicode.py" \
        "$X86_ROOT/usr/lib/wine/x86_64-windows/msxml3.dll"
    python3 "$SCRIPT_DIR/build-support/x86-translation/patch-msxml-unicode.py" \
        "$I386_ROOT/usr/lib/wine/i386-windows/msxml3.dll"

    # qemu-user also leaves x86-64 REG_TRAPNO at -1. Apply the amd64 variant
    # of Wine's trap-inference fix before starting any Win64 application.
    python3 "$SCRIPT_DIR/build-support/x86-translation/patch-wine-x86_64-qemu.py" \
        "$X86_ROOT/usr/lib/wine/x86_64-unix/ntdll.so"

    # Office passes eight-byte-aligned context and jump buffers through its
    # error-reporting path. Use Wine's unaligned-safe x86-64 instruction forms
    # at the exact Alpine 9.17 PE sites that consume those buffers.
    python3 "$SCRIPT_DIR/build-support/x86-translation/patch-wine-x86_64-context.py" \
        "$X86_ROOT/usr/lib/wine/x86_64-windows/ntdll.dll"

    # qemu-user leaves the i386 REG_TRAPNO field at -1. Backport Wine's
    # upstream trap-inference fix so routine PE module page faults are handled
    # instead of surfacing as illegal-instruction crashes.
    python3 "$SCRIPT_DIR/build-support/x86-translation/patch-wine-i386-qemu.py" \
        "$I386_ROOT/usr/lib/wine/i386-unix/ntdll.so"

    # Translated service executables need longer than Wine's native ten-second
    # default to load their PE modules and connect to services.exe.  Without
    # this, RpcSs and the device services time out just before they call the
    # service dispatcher, leaving complex Office applications blocked on RPC.
    python3 "$SCRIPT_DIR/build-support/x86-translation/patch-wine-service-timeout.py" \
        "$X86_ROOT/usr/lib/wine/x86_64-windows/services.exe"
    python3 "$SCRIPT_DIR/build-support/x86-translation/patch-wine-service-timeout.py" \
        "$I386_ROOT/usr/lib/wine/i386-windows/services.exe"

    # Wine's i386 preloader reserves the low Windows address space before the
    # PIE loader starts. Without it qemu-i386 maps Wine at 0x00400000, where a
    # normal PE32 executable also needs to load. Keep both real i386 binaries
    # under private names and put native shell trampolines at Wine's derived
    # re-exec paths so every child starts through qemu and the preloader too.
    mv "$I386_ROOT/usr/bin/wine" "$I386_ROOT/usr/bin/wine-bin"
    mv "$I386_ROOT/usr/bin/wine-preloader" \
        "$I386_ROOT/usr/bin/wine-preloader-bin"
    install -m755 \
        "$SCRIPT_DIR/build-support/x86-translation/reexec-wine-x86-32" \
        "$I386_ROOT/usr/bin/wine"
    install -m755 \
        "$SCRIPT_DIR/build-support/x86-translation/reexec-wine-preloader-x86-32" \
        "$I386_ROOT/usr/bin/wine-preloader"
fi

echo "=== building the translated Linux smoke fixture ==="
clang --target=x86_64-linux-none -c \
    "$SCRIPT_DIR/tests/x86-translation/smoke.S" \
    -o "$BUILD_DIR/x86-translation-smoke.o"
ld.lld -m elf_x86_64 -static -o "$STAGING/usr/share/vinix/x86-translation-smoke" \
    "$BUILD_DIR/x86-translation-smoke.o"
install -m755 "$SCRIPT_DIR/build-support/x86-translation/run-x86-64" \
    "$STAGING/usr/bin/run-x86-64"
install -m755 "$SCRIPT_DIR/build-support/x86-translation/run-x86-32" \
    "$STAGING/usr/bin/run-x86-32"
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
    ln -snf /usr/libexec/vinix-i386/root/usr/lib/wine/i386-windows \
        "$STAGING/usr/share/wine/i386-windows"
    for prefix in "$STAGING/root/.wine-x86_64" \
        "$STAGING/root/.wine-office2010-x86_64" \
        "$STAGING/root/.wine-word2013-x86_64"; do
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
        # Keep the PE32 modules available for Wine's WoW64 prefix layout. PE32
        # execution itself uses the separate translated i386 Unix runtime.
        mkdir -p "$prefix/drive_c/windows/syswow64"
        for builtin in "$X86_ROOT/usr/lib/wine/i386-windows/"*; do
            [ -f "$builtin" ] || continue
            ln -snf "/usr/share/wine/i386-windows/${builtin##*/}" \
                "$prefix/drive_c/windows/syswow64/${builtin##*/}"
        done
    done
    for prefix in "$STAGING/root/.wine-x86_32"; do
        mkdir -p "$prefix/drive_c/windows/system32" "$prefix/dosdevices"
        install -m644 "$SCRIPT_DIR/build-support/x86-translation/wine-update-disabled" \
            "$prefix/.update-timestamp"
        ln -snf ../drive_c "$prefix/dosdevices/c:"
        ln -snf / "$prefix/dosdevices/z:"
        for builtin in "$I386_ROOT/usr/lib/wine/i386-windows/"*; do
            [ -f "$builtin" ] || continue
            ln -snf "/usr/share/wine/i386-windows/${builtin##*/}" \
                "$prefix/drive_c/windows/system32/${builtin##*/}"
        done
    done
    x86_64-w64-mingw32-gcc -Os -s -mwindows \
        "$SCRIPT_DIR/tests/wine/calculator.c" \
        -o "$STAGING/usr/share/wine/vinix-calculator.exe"
    x86_64-w64-mingw32-gcc -Os -s \
        "$SCRIPT_DIR/tests/wine/smoke.c" \
        -o "$STAGING/usr/share/wine/vinix-wine-smoke.exe"
    x86_64-w64-mingw32-gcc -Os -s -shared \
        "$SCRIPT_DIR/build-support/x86-translation/sppc-office-compat.c" \
        -o "$STAGING/usr/share/wine/vinix-sppc-office-compat.dll"
    i686-w64-mingw32-gcc -Os -s \
        "$SCRIPT_DIR/tests/wine/smoke.c" \
        -o "$STAGING/usr/share/wine/vinix-wine-smoke32.exe"
    install -m644 \
        "$SCRIPT_DIR/build-support/x86-translation/word2013-wine.reg" \
        "$STAGING/usr/share/wine/word2013-wine.reg"
    for root in "$X86_ROOT" "$I386_ROOT"; do
        install -m644 \
            "$SCRIPT_DIR/build-support/x86-translation/vinix-fonts.conf" \
            "$root/etc/fonts/conf.d/35-vinix-wine.conf"
    done
    install -m755 "$SCRIPT_DIR/build-support/x86-translation/run-wine-x86-64" \
        "$STAGING/usr/bin/run-wine-x86-64"
    for launcher in wine wine64 wineserver msiexec notepad regedit regsvr32 \
        wineboot winecfg wineconsole winefile winemine winepath calculator \
        office2010-setup word2010 word2013-setup word2013; do
        install -m755 "$SCRIPT_DIR/build-support/x86-translation/run-wine-x86-64" \
            "$STAGING/usr/bin/$launcher"
    done
    install -m755 "$SCRIPT_DIR/build-support/x86-translation/run-wine-x86-32" \
        "$STAGING/usr/bin/wine32"
    install -m755 "$SCRIPT_DIR/build-support/x86-translation/run-wine-x86-32" \
        "$STAGING/usr/bin/wineserver32"
    install -m755 "$SCRIPT_DIR/tests/wine/wine-smoke" \
        "$STAGING/usr/bin/wine-smoke"
    install -m755 "$SCRIPT_DIR/tests/wine/wine-smoke32" \
        "$STAGING/usr/bin/wine-smoke32"

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
    if [ -n "$WORD2013_MEDIA" ]; then
        echo "=== staging licensed Word 2013 media ==="
        mkdir -p "$STAGING/root/word2013-media"
        cp -a "$WORD2013_MEDIA/." "$STAGING/root/word2013-media/"
    fi
    if [ -n "$WORD2013_PREFIX" ]; then
        echo "=== staging the supplied Word 2013 Wine prefix ==="
        word2013_target="$STAGING/root/.wine-word2013-x86_64"
        rm -rf "$word2013_target"
        mkdir -p "$word2013_target"
        cp -a "$WORD2013_PREFIX/." "$word2013_target/"
        install -m644 "$SCRIPT_DIR/build-support/x86-translation/wine-update-disabled" \
            "$word2013_target/.update-timestamp"
        # A conventionally prepared prefix contains private copies of Wine's
        # PE modules. Deduplicate only byte-identical files: Office also puts
        # native ATL and Visual C++ runtimes in system32 under names provided
        # by Wine, and replacing those breaks its delay-loaded components.
        for builtin in "$X86_ROOT/usr/lib/wine/x86_64-windows/"*; do
            [ -f "$builtin" ] || continue
            target="$word2013_target/drive_c/windows/system32/${builtin##*/}"
            if [ -f "$target" ] && cmp -s "$builtin" "$target"; then
                rm -f "$target"
                ln -snf "/usr/share/wine/x86_64-windows/${builtin##*/}" \
                    "$target"
            fi
        done
        for builtin in "$X86_ROOT/usr/lib/wine/i386-windows/"*; do
            [ -f "$builtin" ] || continue
            target="$word2013_target/drive_c/windows/syswow64/${builtin##*/}"
            if [ -f "$target" ] && cmp -s "$builtin" "$target"; then
                rm -f "$target"
                ln -snf "/usr/share/wine/i386-windows/${builtin##*/}" \
                    "$target"
            fi
        done
        # These Wine modules carry Vinix/QEMU compatibility patches and must
        # match the Unix half of the staged Wine build, even when the supplied
        # prefix was prepared with an earlier build of the same Wine version.
        for builtin in ntdll.dll msxml3.dll; do
            rm -f "$word2013_target/drive_c/windows/system32/$builtin"
            ln -snf "/usr/share/wine/x86_64-windows/$builtin" \
                "$word2013_target/drive_c/windows/system32/$builtin"
        done
        # Apply the current runtime settings on first boot. In particular,
        # imported prefixes can contain font-cache paths from the machine on
        # which Office was installed; the launcher replaces those paths only
        # after it knows the final Vinix runtime root.
        rm -f "$word2013_target/.vinix-word2013-settings"
    fi
    # Wine's generated sppc.dll export aborts Word at startup. Replace it only
    # in Word's isolated prefix with a non-activating compatibility DLL that
    # reports missing licensing policy through normal HRESULTs.
    rm -f "$STAGING/root/.wine-word2013-x86_64/drive_c/windows/system32/sppc.dll"
    ln -snf /usr/share/wine/vinix-sppc-office-compat.dll \
        "$STAGING/root/.wine-word2013-x86_64/drive_c/windows/system32/sppc.dll"
fi

file "$STAGING/usr/bin/qemu-x86_64" \
    "$STAGING/usr/share/vinix/x86-translation-smoke"
echo
echo "x86-64 translation layer staged: $(du -sh "$STAGING" | cut -f1)"
echo "output: $STAGING"
if [ "$WITH_WINE" -eq 1 ]; then
    echo "guest commands: x86-translation-smoke.sh, wine-smoke, wine-smoke32, calculator, word2010, word2013"
    echo "Office 2010 setup: office2010-setup /path/to/x64/setup.exe"
    echo "Word 2013 setup: word2013-setup /path/to/x64/setup.exe"
else
    echo "guest command: x86-translation-smoke.sh"
fi
