#!/bin/bash
# Stage Valve's Linux Steam client for Vinix/aarch64.
#
# Steam is only published for x86 Linux, so it runs through the QEMU user-mode
# translators staged by build-x86-translation-aarch64.sh. Valve's client is a
# glibc program (a 32-bit bootstrapper and 64-bit helpers), which the musl
# Wine roots cannot host: this stages a Debian multiarch root beside them with
# the libraries Valve's own steam-libs packages ask for, plus the GNU tools
# Steam's scripts use, and the launcher that ties it together.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${VINIX_STEAM_BUILD_DIR:-$SCRIPT_DIR/build-aarch64-steam}"
DOWNLOADS="$BUILD_DIR/downloads"
STAGING="$BUILD_DIR/staging"
ROOT="$STAGING/usr/libexec/vinix-steam/root"
HELPERS="$STAGING/usr/libexec/vinix-steam/bin"

# Valve's installer package, which carries the bootstrap archive the client
# unpacks and updates itself from.
STEAM_DEB_URL="${VINIX_STEAM_DEB_URL:-https://cdn.fastly.steamstatic.com/client/installer/steam.deb}"
DEBIAN_MIRROR="${DEBIAN_MIRROR:-https://deb.debian.org/debian}"
DEBIAN_RELEASE="${VINIX_STEAM_DEBIAN_RELEASE:-bookworm}"

case "${1:-}" in
    "") ;;
    --help|-h)
        echo "usage: $0"
        echo "  stages Steam's bootstrap and its x86 glibc runtime under $BUILD_DIR/staging"
        exit 0
        ;;
    *)
        echo "unknown option: $1" >&2
        exit 2
        ;;
esac

for tool in curl python3 tar xz file clang ld.lld; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "missing build tool: $tool" >&2
        exit 1
    fi
done

mkdir -p "$DOWNLOADS"
rm -rf "$STAGING"
mkdir -p "$STAGING/usr/bin" "$STAGING/usr/lib/steam" "$STAGING/usr/share/pixmaps" \
    "$STAGING/usr/share/vinix" "$ROOT" "$HELPERS"

echo "=== fetching Valve's Steam installer ==="
if [ ! -f "$DOWNLOADS/steam.deb" ]; then
    curl -fL --retry 3 -o "$DOWNLOADS/steam.deb.partial" "$STEAM_DEB_URL"
    mv "$DOWNLOADS/steam.deb.partial" "$DOWNLOADS/steam.deb"
fi
rm -rf "$BUILD_DIR/steam-deb"
mkdir -p "$BUILD_DIR/steam-deb"
python3 - "$DOWNLOADS/steam.deb" "$BUILD_DIR/steam-deb" <<'EOF'
import io, sys, tarfile
from pathlib import Path
deb = Path(sys.argv[1]).read_bytes()
out = Path(sys.argv[2])
assert deb.startswith(b"!<arch>\n"), "not a Debian package"
offset = 8
while offset + 60 <= len(deb):
    header = deb[offset:offset + 60]
    name = header[0:16].decode().strip().rstrip("/")
    size = int(header[48:58].decode().strip())
    payload = deb[offset + 60:offset + 60 + size]
    if name.startswith(("control.tar", "data.tar")):
        with tarfile.open(fileobj=io.BytesIO(payload), mode="r:*") as archive:
            archive.extractall(out / name.split(".")[0])
    offset += 60 + size + (size & 1)
EOF
steam_version="$(sed -n 's/^Version: //p' "$BUILD_DIR/steam-deb/control/control")"
bootstrap="$BUILD_DIR/steam-deb/data/usr/lib/steam/bootstraplinux_ubuntu12_32.tar.xz"
if [ ! -f "$bootstrap" ]; then
    echo "the Steam package carries no bootstraplinux_ubuntu12_32.tar.xz" >&2
    exit 1
fi
echo "  steam-launcher $steam_version"
install -m644 "$bootstrap" "$STAGING/usr/lib/steam/bootstraplinux_ubuntu12_32.tar.xz"
install -m644 "$BUILD_DIR/steam-deb/data/usr/share/pixmaps/steam.png" \
    "$STAGING/usr/share/pixmaps/steam.png"
printf '%s\n' "${steam_version#*:}" > "$STAGING/usr/share/vinix/steam-launcher-version"

fetch_index() {
    local architecture="$1"
    local index="$DOWNLOADS/${DEBIAN_RELEASE}_${architecture}_Packages"
    if [ ! -f "$index" ]; then
        echo "  fetching Debian $DEBIAN_RELEASE/$architecture index" >&2
        curl -fL --retry 3 -o "$index.xz" \
            "$DEBIAN_MIRROR/dists/$DEBIAN_RELEASE/main/binary-$architecture/Packages.xz"
        xz -d "$index.xz"
    fi
    printf '%s\n' "$index"
}

# The packages steam-libs-i386 and steam-libs-amd64 depend on and recommend,
# less the D-Bus, portal, VA-API and Vulkan pieces nothing here provides.
# The 32-bit set hosts the client, the 64-bit set the web helper, both on top
# of the runtime Valve ships.
guest_libraries=(libc6 libcrypt1 libegl1 libgbm1 libgl1 libgl1-mesa-dri \
    libgcc-s1 libgpg-error0 libstdc++6 libudev1 libxcb-dri3-0 libxcb1 \
    libxinerama1 libx11-6 libnss3 libxss1 libxtst6 libxkbcommon-x11-0 \
    libfontconfig1 libasound2 libsdl2-2.0-0 libusb-1.0-0)
# The updated 32-bit steamui.so loads these directly. Valve's bootstrapper
# does not, so a smoke test of the bootstrap alone cannot catch their absence.
client_libraries_i386=(libgtk2.0-0 libpipewire-0.3-0 libpulse0 \
    libxcb-res0 libxi6 libxrandr2 libxrender1 libopenal1 libnm0 libva2 \
    libvdpau1 libbz2-1.0 libsm6 libice6)
# The 64-bit Chromium helper and its libcef.so have a separate ELF dependency
# set, including GTK's accessibility and printing interfaces.
client_libraries_amd64=(libglib2.0-0 libxi6 libxrender1 libxrandr2 \
    libxcomposite1 libxdamage1 libibus-1.0-5 libdbus-1-3 libatk1.0-0 \
    libatk-bridge2.0-0 libcups2 libpango-1.0-0 libcairo2 libatspi2.0-0 \
    libva2 libvdpau1 libbz2-1.0)
# Steam's launch scripts are bash and lean on GNU tar, xz, coreutils,
# findutils and util-linux's getopt; the image's busybox has none of the
# options they use.
guest_tools=(bash coreutils tar xz-utils gzip grep sed mawk findutils \
    diffutils debianutils util-linux xdg-user-dirs dbus-daemon dbus-x11)
# Package management, documentation, init scripts and the bits a maintainer
# script would have generated are not part of a runtime that is never
# installed with dpkg.
ignored=(dpkg debconf debconf-2.0 perl-base install-info libc-l10n \
    sensible-utils tzdata libnss-nis libnss-nisplus x11-common lsb-base \
    sysvinit-utils init-system-helpers)

ignore_flags=()
for name in "${ignored[@]}"; do
    ignore_flags+=(--ignore "$name")
done

echo "=== staging the i386 glibc runtime ==="
python3 "$SCRIPT_DIR/build-support/debian-root.py" \
    --index "$(fetch_index i386)" --mirror "$DEBIAN_MIRROR" \
    --cache "$DOWNLOADS/i386" --root "$ROOT" \
    --manifest "$BUILD_DIR/i386-packages" "${ignore_flags[@]}" \
    "${guest_libraries[@]}" "${client_libraries_i386[@]}"

echo "=== staging the x86-64 glibc runtime and tools ==="
python3 "$SCRIPT_DIR/build-support/debian-root.py" \
    --index "$(fetch_index amd64)" --mirror "$DEBIAN_MIRROR" \
    --cache "$DOWNLOADS/amd64" --root "$ROOT" \
    --manifest "$BUILD_DIR/amd64-packages" "${ignore_flags[@]}" \
    "${guest_libraries[@]}" "${client_libraries_amd64[@]}" "${guest_tools[@]}"

# Absolute symlinks would otherwise leave the private root and resolve on the
# native Vinix root. Materialise their in-root targets instead.
find "$ROOT" -type l | while IFS= read -r link; do
    target="$(readlink "$link")"
    case "$target" in
        /*) real="$ROOT$target" ;;
        *) continue ;;
    esac
    if [ -f "$real" ]; then
        rm -f "$link"
        cp "$real" "$link"
    elif [ -d "$real" ]; then
        rm -f "$link"
        ln -s "$(python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1], os.path.dirname(sys.argv[2])))' "$real" "$link")" "$link"
    fi
done

# Debian's PulseAudio library uses an absolute RUNPATH for its private helper.
# Expose that helper beside libpulse so the private root remains self-contained.
for architecture in i386 x86_64; do
    pulse_dir="$ROOT/usr/lib/${architecture}-linux-gnu"
    for pulse in "$pulse_dir"/pulseaudio/libpulsecommon-*.so; do
        [ -f "$pulse" ] || continue
        ln -snf "pulseaudio/$(basename "$pulse")" "$pulse_dir/$(basename "$pulse")"
    done
done

# Nothing here ran the maintainer scripts. The alternatives they would have
# registered are the ones Steam's scripts call by their generic names.
ln -snf mawk "$ROOT/usr/bin/awk"
# Debian Bookworm still puts these executables in /bin. The launcher starts
# bash and tar by their /usr/bin paths inside the private runtime, so provide
# relative links that stay inside that runtime on both the build host and Vinix.
for tool in bash tar uname; do
    if [ ! -e "$ROOT/usr/bin/$tool" ] && [ -x "$ROOT/bin/$tool" ]; then
        ln -s "../../bin/$tool" "$ROOT/usr/bin/$tool"
    fi
done
# QEMU's -L redirects an absolute path into this root when the path exists
# there. Debian packages create empty system directories, and Chromium opens
# /proc itself before looking up self/task relative to that descriptor. An
# empty private /proc then hides Vinix's live procfs; the same applies to
# device nodes, runtime sockets, temporary files, and users' homes.
for live_dir in proc sys dev run tmp home root boot; do
    if [ -d "$ROOT/$live_dir" ]; then
        rmdir "$ROOT/$live_dir"
    fi
done
# glibc looks the machine's locale settings and its own loader cache up here;
# neither is generated, and the loader falls back to its built-in paths.
mkdir -p "$ROOT/etc/ld.so.conf.d"
: > "$ROOT/etc/ld.so.conf"
# Steam's scripts read the distribution from here to describe the host.
cat > "$ROOT/etc/os-release" <<EOF
PRETTY_NAME="Vinix (Steam x86 runtime, Debian $DEBIAN_RELEASE)"
NAME="Vinix"
ID=vinix
ID_LIKE=debian
VERSION_ID="0.1"
EOF

for loader in lib/ld-linux.so.2 lib64/ld-linux-x86-64.so.2; do
    if [ ! -e "$ROOT/$loader" ]; then
        echo "the glibc runtime is missing /$loader" >&2
        exit 1
    fi
done
for tool in bash tar xz env uname realpath md5sum cmp find getopt xdg-user-dir; do
    if [ ! -x "$ROOT/usr/bin/$tool" ]; then
        echo "the x86-64 tool set is missing /usr/bin/$tool" >&2
        exit 1
    fi
done

# QEMU linux-user does not implement get_robust_list. Steam's i386 UI checks
# that syscall against glibc's thread head and aborts when QEMU returns ENOSYS.
# Compile the small guest-only shim without host headers or startup objects.
echo "=== building the i386 Steam robust-list shim ==="
clang --target=i386-linux-gnu -fPIC -shared -nostdlib -fuse-ld=lld \
    -Wall -Wextra -Werror \
    -Wl,-soname,libvinix-steam-robust.so \
    -o "$ROOT/usr/lib/i386-linux-gnu/libvinix-steam-robust.so" \
    "$SCRIPT_DIR/build-support/steam/robust-list-i386.c"
echo "=== building the x86-64 Steam robust-list shim ==="
clang --target=x86_64-linux-gnu -fPIC -shared -nostdlib -fuse-ld=lld \
    -Wall -Wextra -Werror \
    -Wl,-soname,libvinix-steam-robust.so \
    -o "$ROOT/usr/lib/x86_64-linux-gnu/libvinix-steam-robust.so" \
    "$SCRIPT_DIR/build-support/steam/robust-list-x86_64.c"

# Exercise 4 KiB x86 MADV_DONTNEED against Vinix's 16 KiB host pages during
# steam-smoke; adjacent guest pages must survive the discard.
clang --target=x86_64-linux-gnu -nostdlib -static -fuse-ld=lld \
    -Wl,-e,_start -O1 -Wall -Wextra -Werror \
    -o "$STAGING/usr/bin/steam-madvise-probe" \
    "$SCRIPT_DIR/tests/steam/madvise-x86_64.c"

echo "=== installing the launcher ==="
install -m755 "$SCRIPT_DIR/build-support/steam/steam" "$STAGING/usr/bin/steam"
install -m755 "$SCRIPT_DIR/build-support/steam/steam-hosted" "$STAGING/usr/bin/steam-hosted"
# The translated D-Bus daemon reads this absolute config path from Vinix's
# filesystem, outside the private glibc root.
mkdir -p "$STAGING/usr/share/dbus-1"
install -m644 "$ROOT/usr/share/dbus-1/session.conf" \
    "$STAGING/usr/share/dbus-1/session.conf"
# The scout client starts the service by command name while SteamRT 3 links
# commands from steamrt-direct/bin. Cover both PATH layouts.
install -m755 "$SCRIPT_DIR/build-support/steam/steam-runtime-launcher-service" \
    "$STAGING/usr/bin/steam-runtime-launcher-service"
install -m755 "$SCRIPT_DIR/build-support/steam/steam-runtime-launcher-service" \
    "$ROOT/usr/bin/steam-runtime-launcher-service"
install -m755 "$SCRIPT_DIR/build-support/steam/steam-runtime-launcher-service" \
    "$HELPERS/steam-runtime-launcher-service"
# steamwebhelper.sh insists on a steamrt entry point even when the Steam
# client runs with STEAM_RUNTIME=0. The wrapper uses GNU env for the script's
# leading `--`, then starts Chromium with the software GL settings that work
# on Vinix's translated X11 display.
mkdir -p "$HELPERS/steamrt-direct"
install -m755 "$SCRIPT_DIR/build-support/steam/steamrt-entry-point" \
    "$HELPERS/steamrt-direct/_v2-entry-point"
mkdir -p "$HELPERS/steamrt-direct/bin"
install -m755 "$SCRIPT_DIR/build-support/steam/steam-runtime-launcher-service" \
    "$HELPERS/steamrt-direct/bin/steam-runtime-launcher-service"
for helper in zenity ldd uname tar; do
    install -m755 "$SCRIPT_DIR/build-support/steam/$helper" "$HELPERS/$helper"
done
install -m755 "$SCRIPT_DIR/build-support/steam/qemu-dns.py" "$HELPERS/qemu-dns"
# Steam's WebUI transport resolves the PID behind its loopback socket through
# lsof -P -F upnR -i TCP@127.0.0.1:<port>. The BusyBox applet has different
# output and cannot perform the required socket lookup.
install -m755 "$SCRIPT_DIR/build-support/steam/lsof" "$STAGING/usr/bin/lsof"
# Valve's runtime scripts start with #!/bin/bash. The desktop build installs
# this only into an image that has no bash of its own.
install -m755 "$SCRIPT_DIR/build-support/steam/bash" "$STAGING/usr/libexec/vinix-steam/bash"
install -m755 "$SCRIPT_DIR/tests/steam/steam-smoke" "$STAGING/usr/bin/steam-smoke"

file "$ROOT/usr/bin/bash" "$ROOT/lib/ld-linux.so.2"
echo
echo "Steam staged: $(du -sh "$STAGING" | cut -f1)"
echo "output: $STAGING"
echo "guest commands: steam, steam-smoke"
