#!/bin/bash
# Assemble the ARM64 Vinix test userland on a native Debian ARM64 build VM.
# It contains static BusyBox, a guest-native musl GCC, the V compiler, and an
# optional Mesa/Asahi runtime produced by build-asahi-aarch64.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${VINIX_ARM64_RUNTIME_BUILD_DIR:-$SCRIPT_DIR/build-aarch64-runtime}"
STAGING="$BUILD_DIR/staging"
DOWNLOADS="$BUILD_DIR/downloads"
INITRAMFS="${VINIX_ARM64_INITRAMFS:-$SCRIPT_DIR/build-support/init-aarch64/initramfs.tar}"
ASAHI_STAGING="${VINIX_ASAHI_STAGING:-$SCRIPT_DIR/build-aarch64-asahi/staging}"
PYTHON_STAGING="${VINIX_PYTHON_STAGING:-$SCRIPT_DIR/build-aarch64-python/staging}"
RUBY_STAGING="${VINIX_RUBY_STAGING:-$SCRIPT_DIR/build-aarch64-ruby/staging}"
GO_STAGING="${VINIX_GO_STAGING:-$SCRIPT_DIR/build-aarch64-go/staging}"
NETWORK_TOOLS_STAGING="${VINIX_NETWORK_TOOLS_STAGING:-$SCRIPT_DIR/build-aarch64-network-tools/staging}"
DEVELOPER_TOOLS_STAGING="${VINIX_DEVELOPER_TOOLS_STAGING:-$SCRIPT_DIR/build-aarch64-developer-tools/staging}"
FIREFOX_STAGING="${VINIX_FIREFOX_STAGING:-$SCRIPT_DIR/build-aarch64-firefox/staging}"
CODEX_STAGING="${VINIX_CODEX_STAGING:-$SCRIPT_DIR/build-aarch64-codex/staging}"
MUSL_SYSROOT="${VINIX_MUSL_SYSROOT:-$SCRIPT_DIR/build-aarch64-asahi/sysroot}"

BUSYBOX_VERSION=1.36.1
BUSYBOX_ARCHIVE="busybox-$BUSYBOX_VERSION.tar.bz2"
BUSYBOX_URL="https://busybox.net/downloads/$BUSYBOX_ARCHIVE"
TOOLCHAIN_ARCHIVE=aarch64-linux-musl-native.tgz
TOOLCHAIN_URL=https://musl.cc/aarch64-linux-musl-native.tgz
V_COMMIT=dd859eae55cf4e69346851fe285b9af104c8ffb7
VC_COMMIT=216b1cdc8b1acad5b03e9cf8767f44f2742bf8f5
NPROC="${NPROC:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)}"

merge_staging_tree() {
    local overlay="$1"
    local source relative destination

    # macOS cp follows an existing destination symlink. BusyBox installs many
    # command names as symlinks, so replacing one with a real GNU executable
    # would otherwise overwrite /bin/busybox itself.
    while IFS= read -r -d '' source; do
        relative="${source#"$overlay/"}"
        destination="$STAGING/$relative"
        if [ -L "$destination" ]; then
            rm -f "$destination"
        fi
    done < <(find "$overlay" -mindepth 1 -print0)

    cp -a "$overlay/." "$STAGING/"
}

if [ "$(uname -s)" != Linux ] || [ "$(uname -m)" != aarch64 ]; then
    echo "build-userland-aarch64-vm.sh must run in the Debian ARM64 VM" >&2
    exit 1
fi

for tool in curl git tar patch clang ld.lld file make cc; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "missing build tool: $tool" >&2
        exit 1
    fi
done
if [ ! -f "$MUSL_SYSROOT/usr/lib/libc.a" ]; then
    echo "missing Alpine musl sysroot: $MUSL_SYSROOT" >&2
    echo "run build-asahi-aarch64.sh first, or set VINIX_MUSL_SYSROOT" >&2
    exit 1
fi

find_llvm_tool() {
    local tool="$1"
    local candidate
    for candidate in "$tool" "$tool-21" "$tool-20" "$tool-19" \
        "$tool-18" "$tool-17"; do
        if command -v "$candidate" >/dev/null 2>&1; then
            command -v "$candidate"
            return
        fi
    done
    echo "missing LLVM tool: $tool" >&2
    return 1
}

LLVM_AR="$(find_llvm_tool llvm-ar)"
LLVM_NM="$(find_llvm_tool llvm-nm)"
LLVM_STRIP="$(find_llvm_tool llvm-strip)"
LLVM_OBJCOPY="$(find_llvm_tool llvm-objcopy)"

mkdir -p "$DOWNLOADS"
rm -rf "$STAGING"
mkdir -p "$STAGING/bin" "$STAGING/sbin" "$STAGING/usr/bin" \
    "$STAGING/root" "$STAGING/etc" "$STAGING/dev" "$STAGING/proc" \
    "$STAGING/sys" "$STAGING/tmp" "$STAGING/var/log" "$STAGING/var/run"

echo "==> Building static BusyBox $BUSYBOX_VERSION"
if [ ! -f "$DOWNLOADS/$BUSYBOX_ARCHIVE" ]; then
    curl -fL --retry 3 -o "$DOWNLOADS/$BUSYBOX_ARCHIVE" "$BUSYBOX_URL"
fi
BUSYBOX_SOURCE="$BUILD_DIR/busybox-$BUSYBOX_VERSION"
if [ ! -d "$BUSYBOX_SOURCE" ]; then
    tar xf "$DOWNLOADS/$BUSYBOX_ARCHIVE" -C "$BUILD_DIR"
fi
make -C "$BUSYBOX_SOURCE" HOSTCC=cc defconfig
sed -i 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' \
    "$BUSYBOX_SOURCE/.config"
sed -i "s|CONFIG_SYSROOT=\"\"|CONFIG_SYSROOT=\"$MUSL_SYSROOT\"|" \
    "$BUSYBOX_SOURCE/.config"
for option in \
    KBD_MODE LOADFONT OPENVT SETCONSOLE SETKEYCODES SETLOGCONS \
    RESET RESIZE SHOWKEY FGCONSOLE CHVT DEALLOCVT DUMPKMAP LOADKMAP \
    SETFONT FEATURE_SETFONT_TEXTUAL_MAP FEATURE_LOADFONT_PSF2 \
    FEATURE_LOADFONT_RAW INIT LINUXRC FEATURE_HAVE_RPC FEATURE_INETD_RPC \
    SELINUX PAM FEATURE_SYSTEMD FEATURE_MOUNT_NFS SWAPON SWAPOFF; do
    sed -i "s/CONFIG_${option}=y/# CONFIG_${option} is not set/" \
        "$BUSYBOX_SOURCE/.config"
done
make -C "$BUSYBOX_SOURCE" -j"$NPROC" \
    HOSTCC=cc \
    CC="clang --target=aarch64-linux-musl --sysroot=$MUSL_SYSROOT -fuse-ld=lld --rtlib=compiler-rt --unwindlib=none -Qunused-arguments" \
    AR="$LLVM_AR" NM="$LLVM_NM" STRIP="$LLVM_STRIP" \
    OBJCOPY="$LLVM_OBJCOPY" SKIP_STRIP=y
install -m755 "$BUSYBOX_SOURCE/busybox" "$STAGING/bin/busybox"
while IFS= read -r applet; do
    [ -n "$applet" ] || continue
    ln -sf busybox "$STAGING/bin/$applet"
done < <("$STAGING/bin/busybox" --list)

echo "==> Installing guest-native musl GCC"
if [ ! -f "$DOWNLOADS/$TOOLCHAIN_ARCHIVE" ]; then
    curl -fL --retry 3 -o "$DOWNLOADS/$TOOLCHAIN_ARCHIVE" "$TOOLCHAIN_URL"
fi
TOOLCHAIN="$BUILD_DIR/aarch64-linux-musl-native"
if [ ! -x "$TOOLCHAIN/bin/gcc" ]; then
    tar xzf "$DOWNLOADS/$TOOLCHAIN_ARCHIVE" -C "$BUILD_DIR"
fi
GCC_VERSION="$(basename "$(find "$TOOLCHAIN/lib/gcc/aarch64-linux-musl" \
    -mindepth 1 -maxdepth 1 -type d | head -n1)")"
GUEST_TOOLCHAIN="$STAGING/aarch64-linux-musl-native"
mkdir -p "$GUEST_TOOLCHAIN/bin" \
    "$GUEST_TOOLCHAIN/lib/gcc/aarch64-linux-musl/$GCC_VERSION/include" \
    "$GUEST_TOOLCHAIN/libexec/gcc/aarch64-linux-musl/$GCC_VERSION" \
    "$GUEST_TOOLCHAIN/include" "$GUEST_TOOLCHAIN/lib"
for binary in gcc as ld ld.bfd ar ranlib nm strip objdump readelf; do
    [ ! -f "$TOOLCHAIN/bin/$binary" ] || \
        cp "$TOOLCHAIN/bin/$binary" "$GUEST_TOOLCHAIN/bin/"
done
ln -sf gcc "$GUEST_TOOLCHAIN/bin/cc"
for binary in cc1 collect2 lto-wrapper; do
    source="$TOOLCHAIN/libexec/gcc/aarch64-linux-musl/$GCC_VERSION/$binary"
    [ ! -f "$source" ] || cp "$source" \
        "$GUEST_TOOLCHAIN/libexec/gcc/aarch64-linux-musl/$GCC_VERSION/"
done
cp "$TOOLCHAIN/libexec/gcc/aarch64-linux-musl/$GCC_VERSION"/liblto_plugin.so* \
    "$GUEST_TOOLCHAIN/libexec/gcc/aarch64-linux-musl/$GCC_VERSION/" \
    2>/dev/null || true
cp -a "$TOOLCHAIN/lib/gcc/aarch64-linux-musl/$GCC_VERSION/include/." \
    "$GUEST_TOOLCHAIN/lib/gcc/aarch64-linux-musl/$GCC_VERSION/include/"
for library in libgcc.a libgcc_eh.a crtbegin.o crtbeginS.o crtbeginT.o \
    crtend.o crtendS.o; do
    source="$TOOLCHAIN/lib/gcc/aarch64-linux-musl/$GCC_VERSION/$library"
    [ ! -f "$source" ] || cp "$source" \
        "$GUEST_TOOLCHAIN/lib/gcc/aarch64-linux-musl/$GCC_VERSION/"
done
for library in libc.a libm.a libpthread.a librt.a libdl.a libcrypt.a \
    libresolv.a libutil.a libgcc_s.so libgcc_s.so.1 libatomic.a \
    libatomic.so libatomic.so.1 libatomic.so.1.2.0 \
    crt1.o crti.o crtn.o rcrt1.o Scrt1.o; do
    [ ! -f "$TOOLCHAIN/lib/$library" ] || \
        cp "$TOOLCHAIN/lib/$library" "$GUEST_TOOLCHAIN/lib/"
done
cp -a "$TOOLCHAIN/include/." "$GUEST_TOOLCHAIN/include/"
find "$GUEST_TOOLCHAIN/include" -type d -name c++ -prune -exec rm -rf {} +
mkdir -p "$GUEST_TOOLCHAIN/aarch64-linux-musl" "$GUEST_TOOLCHAIN/usr"
cp -a "$GUEST_TOOLCHAIN/include" "$GUEST_TOOLCHAIN/aarch64-linux-musl/"
cp -a "$GUEST_TOOLCHAIN/include" "$GUEST_TOOLCHAIN/usr/"

echo "==> Building V for Vinix/aarch64"
V_SOURCE="$BUILD_DIR/v-source"
VC_SOURCE="$BUILD_DIR/vc-source"
if [ ! -d "$V_SOURCE/.git" ]; then
    mkdir -p "$V_SOURCE"
    git -C "$V_SOURCE" init
    git -C "$V_SOURCE" fetch --depth=1 https://github.com/vlang/v.git "$V_COMMIT"
    git -C "$V_SOURCE" -c advice.detachedHead=false checkout --detach FETCH_HEAD
fi
if [ ! -d "$VC_SOURCE/.git" ]; then
    mkdir -p "$VC_SOURCE"
    git -C "$VC_SOURCE" init
    git -C "$VC_SOURCE" fetch --depth=1 https://github.com/vlang/vc.git "$VC_COMMIT"
    git -C "$VC_SOURCE" -c advice.detachedHead=false checkout --detach FETCH_HEAD
fi
if patch --dry-run -p0 -d "$VC_SOURCE" \
    < "$SCRIPT_DIR/build-support/v/v.c.patch" >/dev/null 2>&1; then
    patch -p0 -d "$VC_SOURCE" < "$SCRIPT_DIR/build-support/v/v.c.patch"
elif ! patch --dry-run -R -p0 -d "$VC_SOURCE" \
    < "$SCRIPT_DIR/build-support/v/v.c.patch" >/dev/null 2>&1; then
    echo "V bootstrap source is neither clean nor patched as expected" >&2
    exit 1
fi
mkdir -p "$V_SOURCE/vc"
cp "$VC_SOURCE/v.c" "$V_SOURCE/vc/v.c"
clang --target=aarch64-linux-musl --sysroot="$MUSL_SYSROOT" \
    -fuse-ld=lld --rtlib=compiler-rt --unwindlib=none -static \
    -O2 -w -std=gnu99 -D__vinix__ "$V_SOURCE/vc/v.c" \
    -o "$V_SOURCE/v" -lm -lpthread
"$V_SOURCE/v" version
mkdir -p "$STAGING/usr/v"
install -m755 "$V_SOURCE/v" "$STAGING/usr/v/v"
cp -a "$V_SOURCE/vlib" "$STAGING/usr/v/"
if [ -d "$V_SOURCE/thirdparty" ]; then
    cp -a "$V_SOURCE/thirdparty" "$STAGING/usr/v/"
fi
# Compiler/runtime modules are sufficient for an on-target smoke build. Drop
# the upstream test corpus to keep boot-time initramfs unpacking manageable.
find "$STAGING/usr/v/vlib" -type d \
    \( -name tests -o -name slow_tests -o -name testdata \) \
    -prune -exec rm -rf {} +
find "$STAGING/usr/v/vlib" -type f \
    \( -name '*_test.v' -o -name '*.vv' -o -name '*.out' \) -delete
ln -sf ../v/v "$STAGING/usr/bin/v"

echo "==> Installing init and compiler smoke tests"
clang --target=aarch64-linux-none -nostdlib -ffreestanding -O2 \
    -c "$SCRIPT_DIR/build-support/init-aarch64/full-init.c" -o "$BUILD_DIR/init.o"
ld.lld -m aarch64elf --nostdlib -static -o "$STAGING/sbin/init" \
    "$BUILD_DIR/init.o"
printf '%s\n' \
    'export PATH=/aarch64-linux-musl-native/bin:/bin:/sbin:/usr/bin:/usr/sbin' \
    'export HOME=/root' \
    'export TERM=linux' \
    "export PS1='vinix# '" \
    'export LD_LIBRARY_PATH=/usr/lib:/usr/lib/xorg/modules' \
    'export SSL_CA_CERT_FILE=/etc/ssl/certs/ca-certificates.crt' \
    'export XBPS_ARCH=aarch64' \
    > "$STAGING/etc/profile"
printf '%s\n' 'root:x:0:0:root:/root:/bin/sh' > "$STAGING/etc/passwd"
printf '%s\n' 'root:x:0:' > "$STAGING/etc/group"
printf '%s\n' vinix > "$STAGING/etc/hostname"
printf '%s\n' '#include <stdio.h>' \
    'int main(void) { puts("Hello from GCC on Vinix/aarch64!"); return 0; }' \
    > "$STAGING/root/hello.c"
printf '%s\n' 'fn main() { println("Hello from V on Vinix/aarch64!") }' \
    > "$STAGING/root/hello.v"
cat > "$STAGING/etc/vinix-boot-test.sh" <<'BOOT_TEST'
#!/bin/sh
set -e

echo "VINIX ARM64 GCC/V BOOT TEST"
/aarch64-linux-musl-native/bin/gcc --version
/aarch64-linux-musl-native/bin/gcc /root/hello.c -o /tmp/hello-c
/tmp/hello-c
/usr/v/v version
/usr/v/v -gc none run /root/hello.v
echo "VINIX ARM64 GCC/V BOOT TEST: PASS"

if [ -e /dev/dri/renderD128 ] && [ -x /usr/bin/run-gl-triangle-agx ]; then
    echo "GPU render node detected; starting the hardware render test"
    if timeout -k 5 120 /usr/bin/run-gl-triangle-agx --rebuild; then
        echo "VINIX HARDWARE RENDER TEST: PASS"
    else
        status=$?
        echo "VINIX HARDWARE RENDER TEST: FAIL ($status)" >&2
        echo "A recovery shell will remain available for diagnostics." >&2
    fi
elif [ -e /dev/dri/renderD128 ]; then
    echo "VINIX HARDWARE RENDER TEST: FAIL (Mesa runtime unavailable)" >&2
else
    echo "GPU render node absent"
fi

if command -v python3 >/dev/null 2>&1; then
    echo "VINIX ARM64 PYTHON 3 BOOT TEST"
    python3 /root/python3-smoke.py
else
    echo "Python 3 staging absent; skipping the Python boot test"
fi

if command -v ruby >/dev/null 2>&1; then
    echo "VINIX ARM64 RUBY BOOT TEST"
    ruby /root/ruby-smoke.rb
else
    echo "Ruby staging absent; skipping the Ruby boot test"
fi

if command -v go >/dev/null 2>&1; then
    echo "VINIX ARM64 GO BOOT TEST"
    /root/go-smoke.sh
else
    echo "Go staging absent; skipping the Go boot test"
fi

if command -v curl >/dev/null 2>&1; then
    /root/network-tools-smoke.sh
else
    echo "Network tools staging absent; skipping the network client boot test"
fi

if command -v cmake >/dev/null 2>&1; then
    /root/developer-tools-smoke.sh
else
    echo "Developer tools staging absent; skipping the native build test"
fi

if command -v codex >/dev/null 2>&1; then
    echo "VINIX ARM64 CODEX CLI BOOT TEST"
    if command -v python3 >/dev/null 2>&1; then
        python3 /root/codex-smoke.py
    else
        codex --version
        codex --help >/dev/null
        echo "VINIX ARM64 CODEX CLI BOOT TEST: PASS (startup only; Python unavailable)"
    fi
else
    echo "Codex CLI staging absent; skipping the Codex boot test"
fi

exec /bin/sh -l
BOOT_TEST
chmod +x "$STAGING/etc/vinix-boot-test.sh"

if [ -x "$FIREFOX_STAGING/usr/bin/run-firefox" ]; then
    echo "==> Integrating Firefox ESR runtime"
    cp -a "$FIREFOX_STAGING/." "$STAGING/"
else
    echo "==> Firefox staging not found, packaging without Firefox"
fi

if [ -x "$ASAHI_STAGING/usr/bin/gl-triangle-agx" ]; then
    echo "==> Integrating Mesa hardware runtime"
    cp -a "$ASAHI_STAGING/." "$STAGING/"
else
    echo "==> Mesa/Asahi staging not found, packaging without GPU userspace"
fi

if [ -x "$PYTHON_STAGING/usr/bin/python3" ]; then
    echo "==> Integrating Python 3 runtime"
    cp -a "$PYTHON_STAGING/." "$STAGING/"
else
    echo "==> Python 3 staging not found, packaging without Python"
fi

if [ -x "$RUBY_STAGING/usr/bin/ruby" ]; then
    echo "==> Integrating Ruby runtime"
    cp -a "$RUBY_STAGING/." "$STAGING/"
else
    echo "==> Ruby staging not found, packaging without Ruby"
fi

if [ -x "$GO_STAGING/usr/bin/go" ] || [ -x "$GO_STAGING/usr/lib/go/bin/go" ]; then
    echo "==> Integrating Go toolchain"
    merge_staging_tree "$GO_STAGING"
else
    echo "==> Go staging not found, packaging without Go"
fi

if [ -x "$NETWORK_TOOLS_STAGING/usr/bin/curl" ]; then
    echo "==> Integrating network developer tools"
    cp -a "$NETWORK_TOOLS_STAGING/." "$STAGING/"
else
    echo "==> Network tools staging not found, packaging without network clients"
fi

if [ -x "$DEVELOPER_TOOLS_STAGING/usr/bin/cmake" ]; then
    echo "==> Integrating native developer tools"
    merge_staging_tree "$DEVELOPER_TOOLS_STAGING"
else
    echo "==> Developer tools staging not found, packaging without native build tools"
fi

if [ -x "$CODEX_STAGING/usr/bin/codex" ]; then
    echo "==> Integrating Codex CLI runtime"
    cp -a "$CODEX_STAGING/." "$STAGING/"
else
    echo "==> Codex staging not found, packaging without Codex"
fi

echo "==> Verifying staged ARM64 executables"
file "$STAGING/bin/busybox" "$GUEST_TOOLCHAIN/bin/gcc" \
    "$STAGING/usr/v/v" "$STAGING/sbin/init"

mkdir -p "$(dirname "$INITRAMFS")"
# Publish atomically so a host-side rsync cannot open this image halfway
# through packaging.
INITRAMFS_TMP="$(mktemp "$(dirname "$INITRAMFS")/.initramfs.tar.XXXXXX")"
if ! (cd "$STAGING" && tar --format=ustar -cf "$INITRAMFS_TMP" .); then
    rm -f "$INITRAMFS_TMP"
    exit 1
fi
mv -f "$INITRAMFS_TMP" "$INITRAMFS"
echo "==> ARM64 initramfs ready: $INITRAMFS ($(du -h "$INITRAMFS" | cut -f1))"
