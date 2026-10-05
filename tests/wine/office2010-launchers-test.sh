#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/vinix-office2010-test.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

runtime="$work/runtime"
home="$work/home"
media="$work/media"
prefix="$home/.wine-office2010-x86_64"
word="$prefix/drive_c/Program Files/Microsoft Office/Office14/WINWORD.EXE"
mkdir -p "$runtime/usr/bin" "$media/x64" "${word%/*}" "$work/bin"
: > "$runtime/usr/bin/wine"
: > "$media/x64/setup.exe"
: > "$word"
chmod +x "$runtime/usr/bin/wine"

ln -s "$root/build-support/x86-translation/run-wine-x86-64" \
    "$work/bin/office2010-setup"
ln -s "$root/build-support/x86-translation/run-wine-x86-64" \
    "$work/bin/word2010"

runner="$work/record-runner"
printf '%s\n' '#!/bin/sh' \
    '{' \
    'printf "WINEARCH=%s\n" "$WINEARCH"' \
    'printf "WINEPREFIX=%s\n" "$WINEPREFIX"' \
    'for argument do printf "ARG=%s\n" "$argument"; done' \
    '} > "$VINIX_OFFICE_TEST_LOG"' > "$runner"
chmod +x "$runner"

export HOME="$home"
export VINIX_X86_64_ROOT="$runtime"
export VINIX_X86_64_RUNNER="$runner"
export VINIX_OFFICE2010_MEDIA_ROOT="$media"
export VINIX_OFFICE_TEST_LOG="$work/launch.log"

"$work/bin/office2010-setup"
grep -Fx 'WINEARCH=win64' "$VINIX_OFFICE_TEST_LOG"
grep -Fx "WINEPREFIX=$prefix" "$VINIX_OFFICE_TEST_LOG"
grep -Fx "ARG=$runtime/usr/bin/wine" "$VINIX_OFFICE_TEST_LOG"
grep -Fx "ARG=$media/x64/setup.exe" "$VINIX_OFFICE_TEST_LOG"

"$work/bin/word2010" /safe
grep -Fx "ARG=$word" "$VINIX_OFFICE_TEST_LOG"
grep -Fx 'ARG=/safe' "$VINIX_OFFICE_TEST_LOG"

rm -f "$word"
if "$work/bin/word2010" >"$work/missing.out" 2>&1; then
    echo 'word2010 unexpectedly accepted a missing WINWORD.EXE' >&2
    exit 1
fi
grep -F '64-bit Microsoft Word 2010 is not installed' "$work/missing.out"
echo 'Office 2010 Win64 launcher tests passed.'
