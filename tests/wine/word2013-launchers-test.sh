#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
tmp_root=${TMPDIR:-/tmp}
tmp_root=${tmp_root%/}
work=$(mktemp -d "$tmp_root/vinix-word2013-test.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

runtime="$work/runtime"
home="$work/home"
media="$work/media"
registry="$work/word2013-wine.reg"
prefix="$home/.wine-word2013-x86_64"
word="$prefix/drive_c/Program Files/Microsoft Office 15/root/office15/WINWORD.EXE"
mkdir -p "$runtime/usr/bin" "$media/office" "${word%/*}" "$work/bin"
: > "$runtime/usr/bin/wine"
: > "$media/office/setup64.exe"
: > "$registry"
: > "$word"
chmod +x "$runtime/usr/bin/wine"

ln -s "$root/build-support/x86-translation/run-wine-x86-64" \
    "$work/bin/word2013-setup"
ln -s "$root/build-support/x86-translation/run-wine-x86-64" \
    "$work/bin/word2013"

runner="$work/record-runner"
printf '%s\n' '#!/bin/sh' \
    '{' \
    'printf "PWD=%s\n" "$PWD"' \
    'printf "WINEARCH=%s\n" "$WINEARCH"' \
    'printf "WINEPREFIX=%s\n" "$WINEPREFIX"' \
    'printf "WINEDLLOVERRIDES=%s\n" "$WINEDLLOVERRIDES"' \
    'printf "MESA_GLTHREAD=%s\n" "${MESA_GLTHREAD:-}"' \
    'printf "FONTCONFIG_FILE=%s\n" "${FONTCONFIG_FILE:-}"' \
    'printf "FONTCONFIG_PATH=%s\n" "${FONTCONFIG_PATH:-}"' \
    'printf "FONTCONFIG_SYSROOT=%s\n" "${FONTCONFIG_SYSROOT:-}"' \
    'printf "TEMP=%s\n" "$TEMP"' \
    'for argument do printf "ARG=%s\n" "$argument"; done' \
    '} >> "$VINIX_WORD_TEST_LOG"' > "$runner"
chmod +x "$runner"

export HOME="$home"
export USER=root
export VINIX_X86_64_ROOT="$runtime"
export VINIX_X86_64_RUNNER="$runner"
export VINIX_WORD2013_MEDIA_ROOT="$media"
export VINIX_WORD2013_REGISTRY_FILE="$registry"
export VINIX_WORD2013_REGISTRY_PATH='Z:\word2013-wine.reg'
export VINIX_WORD_TEST_LOG="$work/launch.log"

"$work/bin/word2013-setup"
grep -Fx "PWD=$media/office" "$VINIX_WORD_TEST_LOG"
grep -Fx 'WINEARCH=win64' "$VINIX_WORD_TEST_LOG"
grep -Fx "WINEPREFIX=$prefix" "$VINIX_WORD_TEST_LOG"
grep -Fx 'TEMP=C:\users\root\Temp' "$VINIX_WORD_TEST_LOG"
test -d "$prefix/drive_c/users/root/Temp"
test -f "$prefix/drive_c/vinix-word2013-media/Office/setup64.exe"
grep -Fx "ARG=$runtime/usr/bin/wine" "$VINIX_WORD_TEST_LOG"
grep -Fx 'ARG=cmd.exe' "$VINIX_WORD_TEST_LOG"
grep -Fx 'ARG=/d' "$VINIX_WORD_TEST_LOG"
grep -Fx 'ARG=/c' "$VINIX_WORD_TEST_LOG"
grep -Fx 'ARG=set TEMP=C:\users\root\Temp&&set TMP=C:\users\root\Temp&&C:\vinix-word2013-media\Office\setup64.exe' "$VINIX_WORD_TEST_LOG"
grep -Fx "ARG=$runtime/usr/bin/wineserver" "$VINIX_WORD_TEST_LOG"
grep -Fx 'ARG=-w' "$VINIX_WORD_TEST_LOG"

# The 64-bit volume-license media uses a root setup.exe and MSI product
# directories instead of the retail Office/setup64.exe layout.
rm -rf "$prefix/drive_c/vinix-word2013-media"
: > "$media/setup.exe"
: > "$VINIX_WORD_TEST_LOG"
"$work/bin/word2013-setup" "$media/setup.exe" /adminfile custom.msp
grep -Fx "PWD=$media" "$VINIX_WORD_TEST_LOG"
test -L "$prefix/drive_c/vinix-word2013-media"
test "$(readlink "$prefix/drive_c/vinix-word2013-media")" = "$media"
grep -Fx 'ARG=cmd.exe' "$VINIX_WORD_TEST_LOG"
grep -Fx 'ARG=set TEMP=C:\users\root\Temp&&set TMP=C:\users\root\Temp&&C:\vinix-word2013-media\setup.exe' "$VINIX_WORD_TEST_LOG"
grep -Fx 'ARG=/adminfile' "$VINIX_WORD_TEST_LOG"
grep -Fx 'ARG=custom.msp' "$VINIX_WORD_TEST_LOG"

"$work/bin/word2013"
grep -Fx 'WINEDLLOVERRIDES=sppc=n;mscoree,mshtml=;' "$VINIX_WORD_TEST_LOG"
grep -Fx 'MESA_GLTHREAD=false' "$VINIX_WORD_TEST_LOG"
grep -Fx "FONTCONFIG_FILE=$runtime/etc/fonts/fonts.conf" "$VINIX_WORD_TEST_LOG"
grep -Fx "FONTCONFIG_PATH=$runtime/etc/fonts" "$VINIX_WORD_TEST_LOG"
grep -Fx "FONTCONFIG_SYSROOT=$runtime" "$VINIX_WORD_TEST_LOG"
grep -Fx 'ARG=reg.exe' "$VINIX_WORD_TEST_LOG"
grep -Fx 'ARG=import' "$VINIX_WORD_TEST_LOG"
grep -Fx 'ARG=Z:\word2013-wine.reg' "$VINIX_WORD_TEST_LOG"
test -f "$prefix/.vinix-word2013-settings"
test "$(cat "$prefix/.vinix-word2013-settings")" = 5
grep -Fx 'ARG=explorer.exe' "$VINIX_WORD_TEST_LOG"
grep -Fx 'ARG=/desktop=root,768x576' "$VINIX_WORD_TEST_LOG"
grep -Fx 'ARG=C:\Program Files\Microsoft Office 15\root\office15\WINWORD.EXE' "$VINIX_WORD_TEST_LOG"
grep -Fx 'ARG=/a' "$VINIX_WORD_TEST_LOG"

: > "$VINIX_WORD_TEST_LOG"
"$work/bin/word2013" /safe
grep -Fx 'ARG=/safe' "$VINIX_WORD_TEST_LOG"
if grep -Fxq 'ARG=/a' "$VINIX_WORD_TEST_LOG"; then
    echo 'word2013 unexpectedly combined its default /a mode with caller arguments' >&2
    exit 1
fi

rm -f "$word"
if "$work/bin/word2013" >"$work/missing.out" 2>&1; then
    echo 'word2013 unexpectedly accepted a missing WINWORD.EXE' >&2
    exit 1
fi
grep -F '64-bit Microsoft Word 2013 is not installed' "$work/missing.out"
echo 'Word 2013 x64 launcher tests passed.'
