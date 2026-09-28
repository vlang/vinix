#!/bin/sh
# Host-side check of the Steam launcher against a fake runtime: it has to
# unpack Valve's bootstrap once, link ~/.steam/steam, keep a copy of the
# archive for resets, and start steam.sh with the Debian bash inside a UTS
# namespace, with the translators pointed at the glibc root.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/vinix-steam-test.XXXXXX")
work=$(cd "$work" && pwd)
trap 'rm -rf "$work"' EXIT HUP INT TERM

runtime="$work/runtime"
helpers="$work/helpers"
home="$work/home"
mkdir -p "$runtime/usr/bin" "$runtime/lib" "$runtime/usr/lib/i386-linux-gnu" \
	"$runtime/usr/lib/x86_64-linux-gnu" \
	"$helpers/steamrt-direct" "$home" "$work/bin" \
	"$work/bootstrap/ubuntu12_32"
: > "$runtime/lib/ld-linux.so.2"
: > "$runtime/usr/lib/i386-linux-gnu/libvinix-steam-robust.so"
: > "$runtime/usr/lib/i386-linux-gnu/libXrandr.so.2"
: > "$runtime/usr/lib/x86_64-linux-gnu/libvinix-steam-robust.so"
: > "$helpers/steamrt-direct/_v2-entry-point"
chmod +x "$helpers/steamrt-direct/_v2-entry-point"

# The glibc root's bash and tar stand in for the translated ones: bash
# records how it was started, tar is the host's.
printf '%s\n' '#!/bin/sh' \
	'{' \
	'printf "PWD=%s\n" "$PWD"' \
	'printf "PATH=%s\n" "$PATH"' \
	'printf "I386=%s\n" "$VINIX_I386_ROOT"' \
	'printf "X86_64=%s\n" "$VINIX_X86_64_ROOT"' \
	'printf "MULTIARCH=%s\n" "$VINIX_X86_MULTIARCH"' \
	'printf "I386_PRELOAD=%s\n" "$VINIX_I386_PRELOAD"' \
	'printf "X86_64_PRELOAD=%s\n" "$VINIX_X86_64_PRELOAD"' \
	'printf "MALLOC_MMAP_MAX=%s\n" "$MALLOC_MMAP_MAX_"' \
	'printf "CPU=%s\n" "$QEMU_CPU"' \
	'printf "ALLOW_WX=%s\n" "$VINIX_ALLOW_WX"' \
	'printf "RUNTIME=%s\n" "$STEAM_RUNTIME"' \
	'printf "LOGGER=%s\n" "$STEAM_RUNTIME_LOGGER"' \
	'printf "STEAMRT=%s\n" "$STEAM_RUNTIME_STEAMRT"' \
	'printf "VINIX_DATA=%s\n" "$VINIX_STEAM_DATA"' \
	'printf "SCRIPT=%s\n" "$STEAMSCRIPT"' \
	'printf "UNSHARED=%s\n" "${VINIX_TEST_UNSHARED-}"' \
	'for argument do printf "ARG=%s\n" "$argument"; done' \
	'} > "$VINIX_STEAM_TEST_LOG"' > "$runtime/usr/bin/bash"
printf '%s\n' '#!/bin/sh' 'exec /usr/bin/tar "$@"' > "$runtime/usr/bin/tar"
chmod +x "$runtime/usr/bin/bash" "$runtime/usr/bin/tar"
install -m755 "$root/build-support/steam/tar" "$helpers/tar"

# unshare is asked for a UTS namespace; record that and run the rest.
printf '%s\n' '#!/bin/sh' \
	'[ "$1" = -u ] || exit 1' \
	'shift' \
	'VINIX_TEST_UNSHARED=1 exec "$@"' > "$work/bin/unshare"
chmod +x "$work/bin/unshare"

printf '%s\n' '#!/bin/sh' 'echo steam.sh' > "$work/bootstrap/steam.sh"
chmod +x "$work/bootstrap/steam.sh"
checker="$work/bootstrap/ubuntu12_32/steam-runtime/amd64/usr/bin/steam-runtime-check-requirements"
mkdir -p "$(dirname "$checker")"
printf '%s\n' '#!/bin/sh' 'exit 71' > "$checker"
chmod +x "$checker"
: > "$work/bootstrap/ubuntu12_32/steam"
(cd "$work/bootstrap" && tar cJf "$work/bootstraplinux_ubuntu12_32.tar.xz" .)

# The translators only have to exist for the launcher's check.
: > "$work/bin/qemu-i386"
: > "$work/bin/qemu-x86_64"
chmod +x "$work/bin/qemu-i386" "$work/bin/qemu-x86_64"

export HOME="$home"
export VINIX_I386_EMULATOR="$work/bin/qemu-i386"
export VINIX_X86_64_EMULATOR="$work/bin/qemu-x86_64"
export VINIX_STEAM_ROOT="$runtime"
export VINIX_STEAM_HELPERS="$helpers"
export VINIX_STEAM_BOOTSTRAP="$work/bootstraplinux_ubuntu12_32.tar.xz"
export VINIX_STEAM_UNSHARE="$work/bin/unshare"
export VINIX_STEAM_TEST_LOG="$work/launch.log"
unset QEMU_CPU
unset VINIX_I386_PRELOAD VINIX_X86_64_PRELOAD MALLOC_MMAP_MAX_
unset STEAM_RUNTIME STEAM_RUNTIME_LOGGER
unset STEAM_RUNTIME_STEAMRT

"$root/build-support/steam/steam" -silent
data="$home/.local/share/Steam"
[ -x "$data/steam.sh" ] || { echo "the bootstrap was not unpacked" >&2; exit 1; }
[ ! -x "$data/ubuntu12_32/steam-runtime/amd64/usr/bin/steam-runtime-check-requirements" ] || {
	echo "the namespace requirement checker is still executable" >&2; exit 1;
}
[ "$(readlink "$home/.steam/steam")" = "$data" ] || { echo "~/.steam/steam is not linked" >&2; exit 1; }
cmp -s "$VINIX_STEAM_BOOTSTRAP" "$data/bootstrap.tar.xz" || { echo "no bootstrap copy kept" >&2; exit 1; }
mkdir -p "$work/old-style" "$work/checkpoint-style"
(cd "$work/old-style" && "$helpers/tar" xf "$VINIX_STEAM_BOOTSTRAP")
"$helpers/tar" --blocking-factor=128 --checkpoint=1 \
	--checkpoint-action='exec=echo $TAR_CHECKPOINT' -xf "$VINIX_STEAM_BOOTSTRAP" \
	-C "$work/checkpoint-style"
[ -x "$work/old-style/steam.sh" ] && [ -x "$work/checkpoint-style/steam.sh" ]
grep -Fx "PWD=$data" "$VINIX_STEAM_TEST_LOG"
grep -Fx "I386=$runtime" "$VINIX_STEAM_TEST_LOG"
grep -Fx "X86_64=$runtime" "$VINIX_STEAM_TEST_LOG"
grep -Fx "MULTIARCH=1" "$VINIX_STEAM_TEST_LOG"
grep -Fx "I386_PRELOAD=$runtime/usr/lib/i386-linux-gnu/libvinix-steam-robust.so:$runtime/usr/lib/i386-linux-gnu/libXrandr.so.2" "$VINIX_STEAM_TEST_LOG"
grep -Fx "X86_64_PRELOAD=$runtime/usr/lib/x86_64-linux-gnu/libvinix-steam-robust.so" "$VINIX_STEAM_TEST_LOG"
grep -Fx "MALLOC_MMAP_MAX=0" "$VINIX_STEAM_TEST_LOG"
grep -Fx "CPU=max" "$VINIX_STEAM_TEST_LOG"
grep -Fx "ALLOW_WX=1" "$VINIX_STEAM_TEST_LOG"
grep -Fx "RUNTIME=0" "$VINIX_STEAM_TEST_LOG"
grep -Fx "LOGGER=0" "$VINIX_STEAM_TEST_LOG"
grep -Fx "STEAMRT=$helpers/steamrt-direct" "$VINIX_STEAM_TEST_LOG"
grep -Fx "VINIX_DATA=$data" "$VINIX_STEAM_TEST_LOG"
grep -Fx "SCRIPT=/usr/bin/steam" "$VINIX_STEAM_TEST_LOG"
grep -Fx "UNSHARED=1" "$VINIX_STEAM_TEST_LOG"
grep -F "PATH=$helpers:$runtime/usr/bin:$runtime/bin:" "$VINIX_STEAM_TEST_LOG"
grep -Fx "ARG=$data/steam.sh" "$VINIX_STEAM_TEST_LOG"
grep -Fx "ARG=-no-cef-sandbox" "$VINIX_STEAM_TEST_LOG"
grep -Fx "ARG=-silent" "$VINIX_STEAM_TEST_LOG"

# The direct runtime's launcher command must reach the downloaded service.
service="$data/steamrt64/pv-runtime/steam-runtime-steamrt/pressure-vessel/libexec/steam-runtime-tools-0/x86_64-linux-gnu-srt-launcher-service"
mkdir -p "$(dirname "$service")"
printf '%s\n' '#!/bin/sh' 'printf "%s\n" "$*" > "$VINIX_STEAM_TEST_SERVICE_LOG"' > "$service"
chmod +x "$service"
VINIX_STEAM_DATA="$data" VINIX_STEAM_TEST_SERVICE_LOG="$work/service.log" \
    "$root/build-support/steam/steam-runtime-launcher-service" --alongside-steam
grep -Fx -- '--alongside-steam' "$work/service.log"

# A second launch must not unpack again over the client's own files.
: > "$data/ubuntu12_32/steam"
echo updated > "$data/marker"
"$root/build-support/steam/steam"
[ -f "$data/marker" ] || { echo "the second launch unpacked the bootstrap again" >&2; exit 1; }

# Without the namespace privilege the client still starts.
printf '%s\n' '#!/bin/sh' 'exit 1' > "$work/bin/unshare"
"$root/build-support/steam/steam"
grep -Fx "UNSHARED=" "$VINIX_STEAM_TEST_LOG"

rm -f "$runtime/lib/ld-linux.so.2"
if "$root/build-support/steam/steam" >"$work/missing.out" 2>&1; then
	echo 'steam unexpectedly accepted a missing glibc root' >&2
	exit 1
fi
grep -F 'x86 glibc runtime is not installed' "$work/missing.out"
echo 'Steam launcher tests passed.'
