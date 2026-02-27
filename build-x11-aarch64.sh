#!/bin/bash
set -euo pipefail

# Build X11 stack for aarch64 Vinix
# Downloads Alpine aarch64 packages for libraries/tools,
# cross-compiles xorg-server + fbdev driver with Vinix patches using clang.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -x "$SCRIPT_DIR/link-worktree-build-dirs.sh" ]; then
    "$SCRIPT_DIR/link-worktree-build-dirs.sh"
fi
BUILD_DIR="$SCRIPT_DIR/build-aarch64-x11"
SYSROOT="$BUILD_DIR/sysroot"
STAGING="$BUILD_DIR/staging"  # final output
DOWNLOADS="$BUILD_DIR/downloads"
SOURCES="$BUILD_DIR/sources"

ALPINE_MIRROR="https://dl-cdn.alpinelinux.org/alpine/v3.21"
ALPINE_ARCH="aarch64"

# xorg-server and fbdev versions (matching x86 Vinix recipes)
XORG_SERVER_VERSION="21.1.16"
XORG_SERVER_URL="https://xorg.freedesktop.org/releases/individual/xserver/xorg-server-${XORG_SERVER_VERSION}.tar.xz"
FBDEV_VERSION="0.5.1"
FBDEV_URL="https://xorg.freedesktop.org/releases/individual/driver/xf86-video-fbdev-${FBDEV_VERSION}.tar.xz"

# Cross-compilation tools
LLVM_CLANG="/opt/homebrew/opt/llvm/bin/clang"
LLVM_CLANGXX="/opt/homebrew/opt/llvm/bin/clang++"
if [ ! -x "$LLVM_CLANG" ]; then
    LLVM_CLANG="clang"
fi
if [ ! -x "$LLVM_CLANGXX" ]; then
    LLVM_CLANGXX="clang++"
fi
GCC_TC="$SCRIPT_DIR/build-aarch64-userland/staging/aarch64-linux-musl-native"
GCC_TC_FLAG=""
if [ -d "$GCC_TC" ]; then
    GCC_TC_FLAG="--gcc-toolchain=${GCC_TC}"
fi
CC="$LLVM_CLANG --target=aarch64-linux-musl --sysroot=${SYSROOT} ${GCC_TC_FLAG} -static-libgcc"
LD="ld.lld"
AR="llvm-ar"
RANLIB="llvm-ranlib"
STRIP="llvm-strip"
NM="llvm-nm"
PKG_CONFIG="pkg-config"

mkdir -p "$BUILD_DIR" "$SYSROOT" "$STAGING" "$DOWNLOADS" "$SOURCES"

# ── Helper: download and extract Alpine package ──
download_apk() {
    local repo="$1"  # main or community
    local pkg="$2"
    local index_file="$DOWNLOADS/${repo}_APKINDEX"

    # Download index if not cached
    if [ ! -f "$index_file" ]; then
        echo "  Downloading ${repo} APKINDEX..."
        curl -sL "${ALPINE_MIRROR}/${repo}/${ALPINE_ARCH}/APKINDEX.tar.gz" \
            | tar xz -C "$DOWNLOADS" APKINDEX
        mv "$DOWNLOADS/APKINDEX" "$index_file"
    fi

    # Find package filename from index
    local filename
    filename=$(awk -v pkg="$pkg" '
        /^P:/{name=$0; sub(/^P:/,"",name)}
        /^V:/{ver=$0; sub(/^V:/,"",ver)}
        /^$/{if(name==pkg) print name "-" ver ".apk"}
    ' "$index_file")

    if [ -z "$filename" ]; then
        echo "  WARNING: Package '$pkg' not found in ${repo} repo, skipping"
        return 1
    fi

    local url="${ALPINE_MIRROR}/${repo}/${ALPINE_ARCH}/${filename}"
    local local_file="$DOWNLOADS/${filename}"

    if [ ! -f "$local_file" ]; then
        echo "  Downloading ${filename}..."
        curl -sL -o "$local_file" "$url" || {
            echo "  ERROR: Failed to download $url"
            return 1
        }
    fi

    # Extract to sysroot (APK files are just gzipped tars)
    echo "  Extracting ${filename} -> sysroot/"
    tar xzf "$local_file" -C "$SYSROOT" 2>/dev/null || true
    # Clean up APK metadata
    rm -f "$SYSROOT/.PKGINFO" "$SYSROOT/.SIGN"*
}

# ── Step 1: Download Alpine packages ──
echo "=== Step 1: Downloading Alpine aarch64 packages ==="

# Core C library
MAIN_PKGS=(
    musl musl-dev
    zlib zlib-dev
    brotli brotli-dev brotli-libs
    libpng libpng-dev
    bzip2 bzip2-dev libbz2
    expat expat-dev libexpat
    freetype freetype-dev
    fontconfig fontconfig-dev
    libffi libffi-dev
    nettle nettle-dev
    libxau libxau-dev
    libxdmcp libxdmcp-dev
    libxcb libxcb-dev
    xcb-proto
    xorgproto
    xtrans
    util-macros
    pixman pixman-dev
    libepoxy libepoxy-dev
    libx11 libx11-dev
    libxext libxext-dev
    libxrender libxrender-dev
    libxfixes libxfixes-dev
    libxrandr libxrandr-dev
    libxi libxi-dev
    libxdamage libxdamage-dev
    libxt libxt-dev
    libxmu libxmu-dev
    libxpm libxpm-dev
    libxaw libxaw-dev
    libxft libxft-dev
    libxkbfile libxkbfile-dev
    libxshmfence libxshmfence-dev
    libfontenc libfontenc-dev
    libice libice-dev
    libsm libsm-dev
    libxv libxv-dev
    libxxf86vm libxxf86vm-dev
    libxtst libxtst-dev
    libdrm libdrm-dev
    linux-headers
    mesa
    mesa-dev
    mesa-gl
    mesa-glapi
    mesa-egl
    mesa-gbm
    mesa-gles
    mesa-osmesa
    mesa-xatracker
    mesa-dri-gallium
    glu
    glu-dev
    xkbcomp
    xkeyboard-config
    font-misc-misc
    font-cursor-misc
)

COMMUNITY_PKGS=(
    libxfont2
    libxfont2-dev
    libxcvt
    libxcvt-dev
    xclock
    xinit
    xauth
    xmodmap
    xrdb
    xset
    xorg-server-common
    freeglut
    freeglut-dev
    mesa-demos
)

echo "--- Downloading main packages ---"
for pkg in "${MAIN_PKGS[@]}"; do
    download_apk "main" "$pkg" || true
done

echo "--- Downloading community packages ---"
for pkg in "${COMMUNITY_PKGS[@]}"; do
    download_apk "community" "$pkg" || true
done

# ── Step 2: Fix up sysroot ──
echo ""
echo "=== Step 2: Setting up sysroot ==="

# Create standard library symlinks
# musl installs as /lib/ld-musl-aarch64.so.1 and /lib/libc.musl-aarch64.so.1
# Many packages expect /usr/lib/libc.so
if [ -d "$SYSROOT/lib" ]; then
    # Ensure /usr/lib exists and has musl
    mkdir -p "$SYSROOT/usr/lib"
    # Link musl crt files if they're in /lib
    for f in "$SYSROOT"/lib/crt*.o "$SYSROOT"/lib/libc.a "$SYSROOT"/lib/libm.a; do
        [ -f "$f" ] && ln -sf "$f" "$SYSROOT/usr/lib/" 2>/dev/null || true
    done
fi

# Fix pkg-config files to use our sysroot
if [ -d "$SYSROOT/usr/lib/pkgconfig" ]; then
    echo "  Fixing pkg-config prefix paths..."
    for pc in "$SYSROOT"/usr/lib/pkgconfig/*.pc; do
        [ -f "$pc" ] || continue
        [ -L "$pc" ] && continue
        # Replace absolute prefix with sysroot-relative
        sed -i.bak "s|^prefix=.*|prefix=${SYSROOT}/usr|" "$pc"
        rm -f "${pc}.bak"
    done
fi

echo "  Sysroot size: $(du -sh "$SYSROOT" | cut -f1)"

# ── Step 3: Download and build xorg-server ──
echo ""
echo "=== Step 3: Building xorg-server ${XORG_SERVER_VERSION} ==="

XORG_SRC="$SOURCES/xorg-server-${XORG_SERVER_VERSION}"
if [ ! -d "$XORG_SRC" ]; then
    echo "  Downloading xorg-server source..."
    curl -sL "$XORG_SERVER_URL" | tar xJ -C "$SOURCES"
fi

# Apply Vinix patches
PATCH_FILE="$SCRIPT_DIR/patches/xorg-server/jinx-working-patch.patch"
if [ -f "$PATCH_FILE" ]; then
    echo "  Applying Vinix patches..."
    cd "$XORG_SRC"
    # Try to apply, skip if already applied
    patch -p1 -N < "$PATCH_FILE" 2>/dev/null || echo "  (patches may already be applied)"
fi

echo "  Configuring xorg-server..."
cd "$XORG_SRC"

export PKG_CONFIG_PATH="${SYSROOT}/usr/lib/pkgconfig:${SYSROOT}/usr/share/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="${SYSROOT}"
export PKG_CONFIG_LIBDIR="${SYSROOT}/usr/lib/pkgconfig:${SYSROOT}/usr/share/pkgconfig"

# Cross-compilation flags
export CC="$LLVM_CLANG --target=aarch64-linux-musl --sysroot=${SYSROOT} ${GCC_TC_FLAG} -static-libgcc"
export CXX="$LLVM_CLANGXX --target=aarch64-linux-musl --sysroot=${SYSROOT} ${GCC_TC_FLAG} -static-libgcc"
export CFLAGS="-O2 -I${SYSROOT}/usr/include -D__vinix__"
export CPPFLAGS="-I${SYSROOT}/usr/include"
export LDFLAGS="-fuse-ld=lld -L${SYSROOT}/usr/lib -L${SYSROOT}/lib -rdynamic"
export LD="ld.lld"

./configure \
    --host=aarch64-linux-musl \
    --prefix=/usr \
    --sysconfdir=/etc \
    --localstatedir=/var \
    --with-xkb-bin-directory=/usr/bin \
    --with-xkb-path=/usr/share/X11/xkb \
    --with-xkb-output=/var/lib/xkb \
    --with-fontrootdir=/usr/share/fonts/X11 \
    --enable-xorg \
    --enable-xvfb \
    --disable-xephyr \
    --disable-xnest \
    --disable-suid-wrapper \
    --disable-pciaccess \
    --disable-dpms \
    --disable-xres \
    --disable-xvmc \
    --disable-systemd-logind \
    --disable-secure-rpc \
    --disable-config-udev \
    --disable-dri \
    --disable-dri2 \
    --disable-dri3 \
    --disable-int10-module \
    --disable-vgahw \
    --disable-libdrm \
    --disable-glamor \
    --enable-glx \
    --disable-xinerama \
    --enable-screensaver \
    2>&1 | tail -20

# Fix libtool: cross-compile leaves export_dynamic_flag_spec empty, so -export-dynamic
# (needed for dlopen'd modules to resolve symbols from the Xorg binary) gets silently dropped.
sed -i.bak 's/^export_dynamic_flag_spec=""$/export_dynamic_flag_spec="\${wl}--export-dynamic"/' libtool

echo "  Building xorg-server..."
make -j$(sysctl -n hw.ncpu) 2>&1 | tail -5
make install DESTDIR="$STAGING" 2>&1 | tail -5

# ── Step 4: Build xf86-video-fbdev ──
echo ""
echo "=== Step 4: Building xf86-video-fbdev ${FBDEV_VERSION} ==="

FBDEV_SRC="$SOURCES/xf86-video-fbdev-${FBDEV_VERSION}"
if [ ! -d "$FBDEV_SRC" ]; then
    echo "  Downloading fbdev driver source..."
    curl -sL "$FBDEV_URL" | tar xJ -C "$SOURCES"
fi

FBDEV_PATCH="$SCRIPT_DIR/patches/xf86-video-fbdev/jinx-working-patch.patch"
if [ -f "$FBDEV_PATCH" ]; then
    echo "  Applying Vinix patches..."
    cd "$FBDEV_SRC"
    patch -p1 -N < "$FBDEV_PATCH" 2>/dev/null || echo "  (patches may already be applied)"
fi

echo "  Configuring fbdev driver..."
cd "$FBDEV_SRC"

# Need xorg-server headers from our build
export CFLAGS="-O2 -I${SYSROOT}/usr/include -I${STAGING}/usr/include/xorg -I${STAGING}/usr/include/pixman-1 -D__vinix__"
export PKG_CONFIG_PATH="${STAGING}/usr/lib/pkgconfig:${SYSROOT}/usr/lib/pkgconfig:${SYSROOT}/usr/share/pkgconfig"
# fbdev links against helper libs produced by xorg-server (e.g. libshadow.so)
export LDFLAGS="-fuse-ld=lld -L${STAGING}/usr/lib/xorg/modules -Wl,-rpath-link,${STAGING}/usr/lib/xorg/modules -L${SYSROOT}/usr/lib -L${SYSROOT}/lib -rdynamic"

./configure \
    --host=aarch64-linux-musl \
    --prefix=/usr \
    --disable-pciaccess \
    SYSROOT="${SYSROOT}" \
    2>&1 | tail -10

echo "  Building fbdev driver..."
make -j$(sysctl -n hw.ncpu) 2>&1 | tail -5
make install DESTDIR="$STAGING" 2>&1 | tail -5

# ── Step 5: Collect runtime files ──
echo ""
echo "=== Step 5: Collecting runtime files ==="

# Copy dynamic linker
mkdir -p "$STAGING/lib"
cp -a "$SYSROOT"/lib/ld-musl-*.so.1 "$STAGING/lib/" 2>/dev/null || true

# Copy shared libraries from sysroot
mkdir -p "$STAGING/usr/lib"
for lib in "$SYSROOT"/usr/lib/*.so*; do
    [ -f "$lib" ] || [ -L "$lib" ] || continue
    cp -a "$lib" "$STAGING/usr/lib/"
done
for lib in "$SYSROOT"/lib/*.so*; do
    [ -f "$lib" ] || [ -L "$lib" ] || continue
    cp -a "$lib" "$STAGING/lib/"
done

# Copy OpenGL/X11 headers for in-guest builds (e.g. triangle demo via gcc)
mkdir -p "$STAGING/usr/include"
for incdir in GL KHR X11; do
    if [ -d "$SYSROOT/usr/include/$incdir" ]; then
        cp -a "$SYSROOT/usr/include/$incdir" "$STAGING/usr/include/"
    fi
done

# Copy binaries from sysroot (xclock, xinit, xauth, etc.)
mkdir -p "$STAGING/usr/bin"
for bin in xclock xinit startx xauth xmodmap xrdb xset xkbcomp glxinfo glxgears tri glxdemo; do
    [ -f "$SYSROOT/usr/bin/$bin" ] && cp -a "$SYSROOT/usr/bin/$bin" "$STAGING/usr/bin/"
done

# Copy XKB data
if [ -d "$SYSROOT/usr/share/X11/xkb" ]; then
    mkdir -p "$STAGING/usr/share/X11"
    cp -a "$SYSROOT/usr/share/X11/xkb" "$STAGING/usr/share/X11/"
fi

# Copy fonts
for fontdir in "$SYSROOT/usr/share/fonts/X11" "$SYSROOT/usr/share/fonts/misc"; do
    if [ -d "$fontdir" ]; then
        mkdir -p "$STAGING/$(echo "$fontdir" | sed "s|${SYSROOT}||")"
        cp -a "$fontdir"/* "$STAGING/$(echo "$fontdir" | sed "s|${SYSROOT}||")/"
    fi
done

# Copy fontconfig config
if [ -d "$SYSROOT/etc/fonts" ]; then
    mkdir -p "$STAGING/etc/fonts"
    cp -a "$SYSROOT/etc/fonts"/* "$STAGING/etc/fonts/"
fi

# Create xorg.conf
mkdir -p "$STAGING/etc/X11"
cat > "$STAGING/etc/X11/xorg.conf" << 'XORGEOF'
Section "ServerFlags"
    Option "AllowEmptyInput" "true"
    Option "AutoAddDevices" "false"
    Option "AutoEnableDevices" "false"
EndSection

Section "Module"
    Load "fbdev"
EndSection

Section "Device"
    Identifier "Card0"
    Driver "fbdev"
    Option "fbdev" "/dev/fb0"
EndSection

Section "Screen"
    Identifier "Screen0"
    Device "Card0"
EndSection
XORGEOF

# Create xinitrc
mkdir -p "$STAGING/root"
cat > "$STAGING/root/.xinitrc" << 'XINITEOF'
#!/bin/sh
exec xclock -geometry 400x400+50+50
XINITEOF
chmod +x "$STAGING/root/.xinitrc"

echo ""
echo "=== Build complete ==="
echo "Staging directory: $STAGING"
echo "Size: $(du -sh "$STAGING" | cut -f1)"
echo ""
echo "Contents:"
ls -la "$STAGING/usr/bin/" 2>/dev/null | head -20
echo "..."
echo "Xorg modules:"
ls "$STAGING"/usr/lib/xorg/modules/drivers/ 2>/dev/null || echo "(none yet)"
