#!/bin/bash
# Cross-compile musl + busybox + GCC toolchain for aarch64 Vinix on macOS
# Produces: build-support/init-aarch64/initramfs.tar
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -x "$SCRIPT_DIR/link-worktree-build-dirs.sh" ]; then
    "$SCRIPT_DIR/link-worktree-build-dirs.sh"
fi
BUILD_DIR="$SCRIPT_DIR/build-aarch64-userland"
SYSROOT="$BUILD_DIR/sysroot"
STAGING="$BUILD_DIR/staging"
INIT_DIR="$SCRIPT_DIR/build-support/init-aarch64"

MUSL_VERSION="1.2.5"
BUSYBOX_VERSION="1.36.1"
LINUX_VERSION="6.6.72"
COMPILER_RT_VERSION="21.1.5"

NPROC=$(sysctl -n hw.ncpu 2>/dev/null || echo 4)

# LLVM tools (from Homebrew)
LLVM_BIN="/opt/homebrew/opt/llvm/bin"
if [ ! -x "$LLVM_BIN/llvm-ar" ]; then
    echo "ERROR: LLVM tools not found at $LLVM_BIN"
    echo "Install: brew install llvm"
    exit 1
fi

TARGET=aarch64-linux-gnu
CC="clang --target=$TARGET"
AR="$LLVM_BIN/llvm-ar"
RANLIB="$LLVM_BIN/llvm-ranlib"
NM="$LLVM_BIN/llvm-nm"
STRIP="$LLVM_BIN/llvm-strip"
OBJCOPY="$LLVM_BIN/llvm-objcopy"

mkdir -p "$BUILD_DIR" "$SYSROOT"

# ── Step 1: Build musl ──
if [ ! -f "$SYSROOT/lib/libc.a" ]; then
    echo "==> Building musl $MUSL_VERSION..."

    cd "$BUILD_DIR"
    if [ ! -d "musl-$MUSL_VERSION" ]; then
        if [ ! -f "musl-$MUSL_VERSION.tar.gz" ]; then
            echo "    Downloading musl..."
            curl -LO "https://musl.libc.org/releases/musl-$MUSL_VERSION.tar.gz"
        fi
        tar xf "musl-$MUSL_VERSION.tar.gz"
    fi

    cd "musl-$MUSL_VERSION"
    [ -f config.mak ] && make clean 2>/dev/null || true

    CC="$CC" AR="$AR" RANLIB="$RANLIB" \
        ./configure \
        --prefix="$SYSROOT" \
        --target=aarch64 \
        --disable-shared \
        CFLAGS="-O2 -fPIC"

    make -j"$NPROC" AR="$AR" RANLIB="$RANLIB"
    make install

    echo "    musl installed to $SYSROOT"
else
    echo "==> musl already built, skipping"
fi

if [ ! -f "$SYSROOT/lib/libc.a" ]; then
    echo "ERROR: musl build failed"
    exit 1
fi

# ── Step 2: Install Linux kernel headers ──
if [ ! -f "$SYSROOT/include/linux/types.h" ]; then
    echo "==> Installing Linux kernel headers..."

    cd "$BUILD_DIR"
    if [ ! -d "linux-$LINUX_VERSION" ]; then
        if [ ! -f "linux-$LINUX_VERSION.tar.xz" ]; then
            echo "    Downloading Linux kernel..."
            curl -LO "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$LINUX_VERSION.tar.xz"
        fi
        tar xf "linux-$LINUX_VERSION.tar.xz"
    fi

    LINUX_SRC="$BUILD_DIR/linux-$LINUX_VERSION"

    # Copy UAPI headers (musl doesn't provide linux/ headers)
    mkdir -p "$SYSROOT/include/linux" "$SYSROOT/include/asm" "$SYSROOT/include/asm-generic" "$SYSROOT/include/mtd"
    cp -r "$LINUX_SRC/include/uapi/linux/"* "$SYSROOT/include/linux/"
    cp -r "$LINUX_SRC/include/uapi/asm-generic/"* "$SYSROOT/include/asm-generic/"
    cp -r "$LINUX_SRC/arch/arm64/include/uapi/asm/"* "$SYSROOT/include/asm/"
    cp -r "$LINUX_SRC/include/uapi/mtd/"* "$SYSROOT/include/mtd/"

    # Generate asm/ fallback wrappers for headers not in arch/arm64
    for f in "$SYSROOT/include/asm-generic/"*.h; do
        name=$(basename "$f")
        if [ ! -f "$SYSROOT/include/asm/$name" ]; then
            echo "#include <asm-generic/$name>" > "$SYSROOT/include/asm/$name"
        fi
    done

    # Sanitize: strip kernel-internal includes and annotations
    find "$SYSROOT/include/linux" "$SYSROOT/include/asm" "$SYSROOT/include/asm-generic" "$SYSROOT/include/mtd" \
        -name "*.h" -exec sed -i '' \
        -e '/#include <linux\/compiler_types.h>/d' \
        -e '/#include <linux\/compiler.h>/d' \
        -e 's/ __user / /g' -e 's/ __user$//g' -e 's/__user //g' \
        -e 's/ __force / /g' -e 's/__force //g' \
        -e 's/ __iomem / /g' -e 's/__iomem //g' \
        -e 's/ __rcu / /g' -e 's/__rcu //g' \
        -e 's/ __bitwise / /g' -e 's/__bitwise //g' \
        -e 's/ __percpu / /g' -e 's/__percpu //g' \
        -e 's/__attribute_const__//g' \
        {} +

    # Create stub headers for kernel internals
    cat > "$SYSROOT/include/linux/compiler_types.h" << 'STUB'
#ifndef _LINUX_COMPILER_TYPES_H
#define _LINUX_COMPILER_TYPES_H
#define __user
#define __kernel
#define __iomem
#define __force
#define __bitwise
#define __rcu
#define __percpu
#endif
STUB

    cat > "$SYSROOT/include/linux/compiler.h" << 'STUB'
#ifndef _LINUX_COMPILER_H
#define _LINUX_COMPILER_H
#include <linux/compiler_types.h>
#endif
STUB

    cat > "$SYSROOT/include/linux/version.h" << 'STUB'
#ifndef _LINUX_VERSION_H
#define _LINUX_VERSION_H
#define LINUX_VERSION_CODE 393800
#define KERNEL_VERSION(a,b,c) (((a) << 16) + ((b) << 8) + (c))
#endif
STUB

    echo "    kernel headers installed"
else
    echo "==> kernel headers already installed, skipping"
fi

# ── Step 3: Build compiler-rt builtins (libgcc substitute) ──
if [ ! -s "$SYSROOT/lib/libgcc.a" ] || [ "$(wc -c < "$SYSROOT/lib/libgcc.a")" -lt 1000 ]; then
    echo "==> Building compiler-rt builtins..."

    cd "$BUILD_DIR"
    if [ ! -d "compiler-rt-$COMPILER_RT_VERSION.src" ]; then
        if [ ! -f "compiler-rt-$COMPILER_RT_VERSION.src.tar.xz" ]; then
            echo "    Downloading compiler-rt..."
            curl -LO "https://github.com/llvm/llvm-project/releases/download/llvmorg-$COMPILER_RT_VERSION/compiler-rt-$COMPILER_RT_VERSION.src.tar.xz"
        fi
        tar xf "compiler-rt-$COMPILER_RT_VERSION.src.tar.xz"
    fi

    BUILTINS_SRC="$BUILD_DIR/compiler-rt-$COMPILER_RT_VERSION.src/lib/builtins"
    BUILTINS_OUT="$BUILD_DIR/builtins-obj"
    mkdir -p "$BUILTINS_OUT"

    for f in "$BUILTINS_SRC"/*.c; do
        name=$(basename "$f" .c)
        clang --target=aarch64-linux-gnu -O2 -fPIC -ffreestanding \
            -I"$BUILTINS_SRC" \
            -c "$f" -o "$BUILTINS_OUT/$name.o" 2>/dev/null || true
    done
    for f in "$BUILTINS_SRC/aarch64/"*.c; do
        name=$(basename "$f" .c)
        clang --target=aarch64-linux-gnu -O2 -fPIC -ffreestanding \
            -I"$BUILTINS_SRC" \
            -c "$f" -o "$BUILTINS_OUT/$name.o" 2>/dev/null || true
    done

    "$AR" rcs "$SYSROOT/lib/libgcc.a" "$BUILTINS_OUT"/*.o

    # Create empty stubs for other gcc libs
    "$AR" rcs "$SYSROOT/lib/libgcc_eh.a"

    echo "    compiler-rt builtins built"
else
    echo "==> compiler-rt builtins already built, skipping"
fi

# Create stub CRT files (clang -static needs crtbeginT.o, crtend.o)
if [ ! -f "$SYSROOT/lib/crtbeginT.o" ]; then
    echo '.text' | clang --target=aarch64-linux-gnu -c -x assembler - -o "$SYSROOT/lib/crtbeginT.o"
    echo '.text' | clang --target=aarch64-linux-gnu -c -x assembler - -o "$SYSROOT/lib/crtend.o"
fi

# ── Step 4: Build busybox ──
if [ ! -f "$STAGING/bin/busybox" ]; then
    echo "==> Building busybox $BUSYBOX_VERSION..."

    cd "$BUILD_DIR"
    if [ ! -d "busybox-$BUSYBOX_VERSION" ]; then
        if [ ! -f "busybox-$BUSYBOX_VERSION.tar.bz2" ]; then
            echo "    Downloading busybox..."
            curl -LO "https://busybox.net/downloads/busybox-$BUSYBOX_VERSION.tar.bz2"
        fi
        tar xf "busybox-$BUSYBOX_VERSION.tar.bz2"
    fi

    cd "busybox-$BUSYBOX_VERSION"
    make HOSTCC=cc defconfig

    # Configure for cross-compilation
    sed -i '' 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config
    sed -i '' "s|CONFIG_SYSROOT=\"\"|CONFIG_SYSROOT=\"$SYSROOT\"|" .config
    sed -i '' "s|CONFIG_EXTRA_CFLAGS=\"\"|CONFIG_EXTRA_CFLAGS=\"-I$SYSROOT/include\"|" .config
    sed -i '' "s|CONFIG_EXTRA_LDFLAGS=\"\"|CONFIG_EXTRA_LDFLAGS=\"-L$SYSROOT/lib -fuse-ld=lld\"|" .config
    sed -i '' "s|CONFIG_PREFIX=\"./_install\"|CONFIG_PREFIX=\"$STAGING\"|" .config
    sed -i '' 's/CONFIG_STATIC_LIBGCC=y/# CONFIG_STATIC_LIBGCC is not set/' .config

    # Disable console-tools (need Linux VT ioctls we don't support)
    for opt in KBD_MODE LOADFONT OPENVT SETCONSOLE SETKEYCODES SETLOGCONS \
               RESET RESIZE SHOWKEY FGCONSOLE CHVT DEALLOCVT DUMPKMAP LOADKMAP \
               SETFONT FEATURE_SETFONT_TEXTUAL_MAP FEATURE_LOADFONT_PSF2 FEATURE_LOADFONT_RAW \
               INIT LINUXRC; do
        sed -i '' "s/CONFIG_${opt}=y/# CONFIG_${opt} is not set/" .config 2>/dev/null || true
    done

    # Disable features not needed on Vinix
    for opt in FEATURE_HAVE_RPC FEATURE_INETD_RPC SELINUX PAM FEATURE_SYSTEMD \
               FEATURE_MOUNT_NFS SWAPON SWAPOFF; do
        sed -i '' "s/CONFIG_${opt}=y/# CONFIG_${opt} is not set/" .config 2>/dev/null || true
    done

    make -j"$NPROC" \
        HOSTCC=cc \
        CC="clang --target=$TARGET" \
        AR="$AR" NM="$NM" STRIP="$STRIP" OBJCOPY="$OBJCOPY" \
        SKIP_STRIP=y

    make install \
        HOSTCC=cc \
        CC="clang --target=$TARGET" \
        AR="$AR" NM="$NM" STRIP="$STRIP" OBJCOPY="$OBJCOPY" \
        SKIP_STRIP=y

    echo "    busybox installed to $STAGING"
else
    echo "==> busybox already built, skipping"
fi

if [ ! -f "$STAGING/bin/busybox" ]; then
    echo "ERROR: busybox build failed"
    exit 1
fi

echo "==> Verifying busybox binary..."
file "$STAGING/bin/busybox"

# ── Step 5: Download and strip GCC toolchain ──
GCC_TC_DIR="$BUILD_DIR/aarch64-linux-musl-native"
GCC_TC_STAGING="$STAGING/aarch64-linux-musl-native"

if [ ! -d "$GCC_TC_STAGING/bin" ]; then
    echo "==> Setting up GCC toolchain..."

    # Download pre-built static toolchain from musl.cc
    cd "$BUILD_DIR"
    if [ ! -d "aarch64-linux-musl-native" ]; then
        if [ ! -f "aarch64-linux-musl-native.tgz" ]; then
            echo "    Downloading aarch64-linux-musl-native.tgz (85MB)..."
            curl -LO "https://musl.cc/aarch64-linux-musl-native.tgz"
        fi
        echo "    Extracting toolchain..."
        tar xf "aarch64-linux-musl-native.tgz"
    fi

    # Detect GCC version inside the toolchain
    GCC_VER=$(ls "$GCC_TC_DIR/lib/gcc/aarch64-linux-musl/" | head -1)
    echo "    GCC version: $GCC_VER"

    # Copy to staging, stripping non-essential files
    echo "    Stripping toolchain to C-only essentials..."
    mkdir -p "$GCC_TC_STAGING/bin"
    mkdir -p "$GCC_TC_STAGING/lib/gcc/aarch64-linux-musl/$GCC_VER/include"
    mkdir -p "$GCC_TC_STAGING/libexec/gcc/aarch64-linux-musl/$GCC_VER"
    mkdir -p "$GCC_TC_STAGING/include"

    # Binaries: gcc driver + binutils essentials
    for bin in gcc as ld ld.bfd ar ranlib nm strip objdump readelf; do
        [ -f "$GCC_TC_DIR/bin/$bin" ] && cp "$GCC_TC_DIR/bin/$bin" "$GCC_TC_STAGING/bin/"
    done
    # cc symlink
    ln -sf gcc "$GCC_TC_STAGING/bin/cc"

    # GCC compiler proper (cc1, collect2)
    for f in cc1 collect2 lto-wrapper; do
        [ -f "$GCC_TC_DIR/libexec/gcc/aarch64-linux-musl/$GCC_VER/$f" ] && \
            cp "$GCC_TC_DIR/libexec/gcc/aarch64-linux-musl/$GCC_VER/$f" \
               "$GCC_TC_STAGING/libexec/gcc/aarch64-linux-musl/$GCC_VER/"
    done
    # liblto_plugin if present
    cp "$GCC_TC_DIR/libexec/gcc/aarch64-linux-musl/$GCC_VER"/liblto_plugin.so* \
       "$GCC_TC_STAGING/libexec/gcc/aarch64-linux-musl/$GCC_VER/" 2>/dev/null || true

    # GCC internal headers (stddef.h, stdarg.h, stdbool.h, etc.)
    cp -r "$GCC_TC_DIR/lib/gcc/aarch64-linux-musl/$GCC_VER/include/"* \
       "$GCC_TC_STAGING/lib/gcc/aarch64-linux-musl/$GCC_VER/include/"

    # GCC runtime libraries and CRT files
    cp "$GCC_TC_DIR/lib/gcc/aarch64-linux-musl/$GCC_VER"/libgcc.a \
       "$GCC_TC_STAGING/lib/gcc/aarch64-linux-musl/$GCC_VER/" 2>/dev/null || true
    cp "$GCC_TC_DIR/lib/gcc/aarch64-linux-musl/$GCC_VER"/libgcc_eh.a \
       "$GCC_TC_STAGING/lib/gcc/aarch64-linux-musl/$GCC_VER/" 2>/dev/null || true
    cp "$GCC_TC_DIR/lib/gcc/aarch64-linux-musl/$GCC_VER"/crt*.o \
       "$GCC_TC_STAGING/lib/gcc/aarch64-linux-musl/$GCC_VER/" 2>/dev/null || true

    # musl C library (static) and CRT files
    for f in libc.a libm.a libpthread.a librt.a libdl.a libcrypt.a libresolv.a libutil.a; do
        [ -f "$GCC_TC_DIR/lib/$f" ] && cp "$GCC_TC_DIR/lib/$f" "$GCC_TC_STAGING/lib/"
    done
    # CRT files: crt1.o, crti.o, crtn.o, rcrt1.o (static PIE), Scrt1.o (shared PIE)
    for f in crt1.o crti.o crtn.o rcrt1.o Scrt1.o; do
        [ -f "$GCC_TC_DIR/lib/$f" ] && cp "$GCC_TC_DIR/lib/$f" "$GCC_TC_STAGING/lib/"
    done

    # musl + Linux headers (strip C++ headers — not needed and paths too long for ustar tar)
    cp -r "$GCC_TC_DIR/include/"* "$GCC_TC_STAGING/include/"
    rm -rf "$GCC_TC_STAGING/include/c++"

    # GCC searches for system headers at:
    #   <sysroot>/aarch64-linux-musl/include  (primary)
    #   <sysroot>/usr/include                  (fallback)
    # Copy headers there (real copies, not symlinks — avoids VFS edge cases)
    mkdir -p "$GCC_TC_STAGING/aarch64-linux-musl"
    cp -r "$GCC_TC_STAGING/include" "$GCC_TC_STAGING/aarch64-linux-musl/include"
    mkdir -p "$GCC_TC_STAGING/usr"
    cp -r "$GCC_TC_STAGING/include" "$GCC_TC_STAGING/usr/include"

    # Report sizes
    TC_SIZE=$(du -sh "$GCC_TC_STAGING" | cut -f1)
    echo "    Stripped toolchain size: $TC_SIZE"
    echo "    Toolchain installed to initramfs at /aarch64-linux-musl-native/"
else
    echo "==> GCC toolchain already staged, skipping"
fi

# ── Step 6: Build init (small ELF that execs /bin/sh) ──
# (init just execs /bin/sh with proper environment)
echo "==> Building init..."

cat > "$BUILD_DIR/init.c" << 'INIT_EOF'
typedef unsigned long u64;
typedef long i64;

static inline i64 syscall3(u64 nr, u64 a0, u64 a1, u64 a2) {
    register u64 x8 __asm__("x8") = nr;
    register u64 x0 __asm__("x0") = a0;
    register u64 x1 __asm__("x1") = a1;
    register u64 x2 __asm__("x2") = a2;
    __asm__ volatile("svc #0"
        : "+r"(x0)
        : "r"(x8), "r"(x1), "r"(x2)
        : "memory");
    return (i64)x0;
}

static inline i64 syscall1(u64 nr, u64 a0) {
    register u64 x8 __asm__("x8") = nr;
    register u64 x0 __asm__("x0") = a0;
    __asm__ volatile("svc #0" : "+r"(x0) : "r"(x8) : "memory");
    return (i64)x0;
}

#define SYS_write  64
#define SYS_execve 221
#define SYS_exit   93

static u64 strlen(const char *s) { u64 n = 0; while (s[n]) n++; return n; }
static void puts(const char *s) { syscall3(SYS_write, 1, (u64)s, strlen(s)); }

void _start(void) {
    puts("\n  Vinix (aarch64) — starting /bin/sh\n\n");

    char *argv[] = {"/bin/sh", (char *)0};
    char *envp[] = {
        "PATH=/aarch64-linux-musl-native/bin:/bin:/sbin:/usr/bin:/usr/sbin",
        "HOME=/root",
        "TERM=linux",
        "PS1=vinix# ",
        "LD_LIBRARY_PATH=/usr/lib:/usr/lib/xorg/modules",
        "LIBGL_DRIVERS_PATH=/usr/lib/xorg/modules/dri:/usr/lib/dri",
        (char *)0
    };

    syscall3(SYS_execve, (u64)argv[0], (u64)argv, (u64)envp);

    puts("init: execve /bin/sh failed\n");
    syscall1(SYS_exit, 1);
    for (;;) ;
}
INIT_EOF

mkdir -p "$STAGING/sbin"
clang -target aarch64-linux-none -nostdlib -ffreestanding -O2 -c \
    -o "$BUILD_DIR/init.o" "$BUILD_DIR/init.c"
ld.lld -m aarch64elf --nostdlib -static \
    -o "$STAGING/sbin/init" "$BUILD_DIR/init.o"

echo "    init binary built"

# ── Step 7: Create filesystem and package initramfs ──
echo "==> Setting up filesystem..."
mkdir -p "$STAGING"/{dev,proc,sys,tmp,etc,var/log,var/run,root}

cat > "$STAGING/etc/passwd" << 'EOF'
root:x:0:0:root:/root:/bin/sh
EOF

cat > "$STAGING/etc/group" << 'EOF'
root:x:0:
EOF

echo "vinix" > "$STAGING/etc/hostname"

cat > "$STAGING/etc/profile" << 'EOF'
export PATH=/aarch64-linux-musl-native/bin:/bin:/sbin:/usr/bin:/usr/sbin
export HOME=/root
export TERM=linux
export PS1='vinix# '
export LD_LIBRARY_PATH=/usr/lib:/usr/lib/xorg/modules
export LIBGL_DRIVERS_PATH=/usr/lib/xorg/modules/dri:/usr/lib/dri
EOF

# Add test hello.c
cat > "$STAGING/root/hello.c" << 'EOF'
#include <stdio.h>
int main(void) {
    printf("Hello from GCC on Vinix!\n");
    return 0;
}
EOF

# ── Step 8: Integrate X11 (Xorg + xclock) ──
X11_STAGING="$SCRIPT_DIR/build-aarch64-x11/staging"
X11_SYSROOT="$SCRIPT_DIR/build-aarch64-x11/sysroot"
if [ -d "$X11_STAGING/usr/bin" ] && [ -f "$X11_STAGING/usr/bin/Xorg" ]; then
    echo "==> Integrating X11..."

    # Dynamic linker
    mkdir -p "$STAGING/lib"
    cp -a "$X11_STAGING/lib/"* "$STAGING/lib/"

    # Binaries
    mkdir -p "$STAGING/usr/bin"
    cp -a "$X11_STAGING/usr/bin/"* "$STAGING/usr/bin/"
    # Fallback: if mesa-demos triangle wasn't staged, pull it from sysroot.
    if [ -f "$X11_SYSROOT/usr/bin/tri" ] && [ ! -f "$STAGING/usr/bin/tri" ]; then
        cp -a "$X11_SYSROOT/usr/bin/tri" "$STAGING/usr/bin/"
    fi

    # Shared libraries
    mkdir -p "$STAGING/usr/lib"
    cp -a "$X11_STAGING/usr/lib/"*.so* "$STAGING/usr/lib/" 2>/dev/null || true
    # Mesa runtime pieces live in sysroot subdirs (not in x11 staging .so copy above).
    # Copy both trees (if present) to avoid stale/empty dirs masking real content.
    if [ -d "$X11_SYSROOT/usr/lib/dri" ]; then
        cp -a "$X11_SYSROOT/usr/lib/dri" "$STAGING/usr/lib/"
    fi
    if [ -d "$X11_STAGING/usr/lib/dri" ]; then
        cp -a "$X11_STAGING/usr/lib/dri" "$STAGING/usr/lib/"
    fi
    if [ -d "$X11_SYSROOT/usr/lib/gallium-pipe" ]; then
        cp -a "$X11_SYSROOT/usr/lib/gallium-pipe" "$STAGING/usr/lib/"
    fi
    if [ -d "$X11_STAGING/usr/lib/gallium-pipe" ]; then
        cp -a "$X11_STAGING/usr/lib/gallium-pipe" "$STAGING/usr/lib/"
    fi

    # Development headers for in-guest OpenGL builds (triangle demo, etc.)
    mkdir -p "$STAGING/usr/include"
    for incdir in GL KHR X11; do
        if [ -d "$X11_STAGING/usr/include/$incdir" ]; then
            cp -a "$X11_STAGING/usr/include/$incdir" "$STAGING/usr/include/"
        elif [ -d "$X11_SYSROOT/usr/include/$incdir" ]; then
            cp -a "$X11_SYSROOT/usr/include/$incdir" "$STAGING/usr/include/"
        fi
    done

    # Resolve .so symlinks to regular files.
    # musl ld.so (1.2.4+) opens libraries with O_NOFOLLOW, so symlinks can
    # fail with ELOOP when libraries/drivers are dlopen'd at runtime.
    resolve_so_symlinks() {
        local tree="$1"
        [ -d "$tree" ] || return 0
        find "$tree" -type l -name '*.so*' | while IFS= read -r link; do
            [ -L "$link" ] || continue
            target=$(readlink "$link")
            if [ "${target#/}" != "$target" ]; then
                real="$STAGING$target"
            else
                real="$(cd "$(dirname "$link")" && realpath -q "$target" 2>/dev/null || echo "$(dirname "$link")/$target")"
            fi
            if [ -f "$real" ]; then
                rm "$link"
                cp "$real" "$link"
            fi
        done
    }
    # Xorg modules (drivers, extensions, dri, helper libs)
    mkdir -p "$STAGING/usr/lib/xorg"
    cp -a "$X11_STAGING/usr/lib/xorg/modules" "$STAGING/usr/lib/xorg/"
    if [ -d "$X11_SYSROOT/usr/lib/xorg/modules/dri" ]; then
        cp -a "$X11_SYSROOT/usr/lib/xorg/modules/dri" "$STAGING/usr/lib/xorg/modules/"
    fi
    resolve_so_symlinks "$STAGING/usr/lib"
    resolve_so_symlinks "$STAGING/lib"
    resolve_so_symlinks "$STAGING/usr/lib/xorg/modules"
    resolve_so_symlinks "$STAGING/usr/lib/dri"
    resolve_so_symlinks "$STAGING/usr/lib/gallium-pipe"

    # XKB data
    mkdir -p "$STAGING/usr/share/X11"
    cp -a "$X11_STAGING/usr/share/X11/xkb" "$STAGING/usr/share/X11/"

    # Fonts
    mkdir -p "$STAGING/usr/share/fonts/X11"
    if [ -d "$X11_STAGING/usr/share/fonts/X11" ]; then
        cp -a "$X11_STAGING/usr/share/fonts/X11/"* "$STAGING/usr/share/fonts/X11/" 2>/dev/null || true
    fi

    # Fontconfig
    cp -a "$X11_STAGING/etc/fonts" "$STAGING/etc/" 2>/dev/null || true

    # Xorg config
    mkdir -p "$STAGING/etc/X11"
    cat > "$STAGING/etc/X11/xorg.conf" << 'XCONF'
Section "ServerFlags"
    Option "AllowEmptyInput" "true"
    Option "AllowIndirectGLXProtocol" "on"
    Option "IndirectGLX" "on"
EndSection

Section "Module"
    Load "glx"
EndSection

Section "Device"
    Identifier "Card0"
    Driver "fbdev"
EndSection
XCONF

    # .xinitrc for xclock demo
    mkdir -p "$STAGING/root"
    cat > "$STAGING/root/.xinitrc" << 'XINITRC'
#!/bin/sh
exec xclock -geometry 400x400+50+50
XINITRC
    chmod +x "$STAGING/root/.xinitrc"

    # OpenGL triangle sample
    cat > "$STAGING/root/gl_triangle.c" << 'GLEOF'
#if defined(__has_include)
#  if __has_include(<GL/freeglut.h>)
#    include <GL/freeglut.h>
#  else
#    include <GL/glut.h>
#  endif
#else
#  include <GL/glut.h>
#endif

static void draw(void) {
    glClearColor(0.08f, 0.08f, 0.10f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);

    glBegin(GL_TRIANGLES);
        glColor3f(1.0f, 0.2f, 0.2f); glVertex2f(-0.65f, -0.45f);
        glColor3f(0.2f, 1.0f, 0.2f); glVertex2f( 0.65f, -0.45f);
        glColor3f(0.2f, 0.4f, 1.0f); glVertex2f( 0.00f,  0.65f);
    glEnd();

    glutSwapBuffers();
}

int main(int argc, char **argv) {
    glutInit(&argc, argv);
    glutInitDisplayMode(GLUT_DOUBLE | GLUT_RGB);
    glutInitWindowSize(800, 600);
    glutCreateWindow("Vinix OpenGL Triangle");
    glutDisplayFunc(draw);
    glutMainLoop();
    return 0;
}
GLEOF

    # Helper that compiles and launches the triangle under Xorg.
cat > "$STAGING/usr/bin/run-gl-triangle" << 'GLRUN'
#!/bin/sh
set -e

target="/usr/bin/tri"
compile_log="/tmp/run-gl-triangle-compile.log"

compile_source=0
if [ "${1:-}" = "--compile" ]; then
    compile_source=1
fi

if [ "$compile_source" -eq 1 ] && [ -f /root/gl_triangle.c ]; then
    echo "run-gl-triangle: compiling /root/gl_triangle.c ..."
    if gcc /root/gl_triangle.c -O2 -I/usr/include -L/usr/lib -o /root/gl_triangle -lglut -lGL -lX11 -lm >"$compile_log" 2>&1; then
        target="/root/gl_triangle"
    else
        echo "run-gl-triangle: guest linker cannot link Alpine RELR shared libs; falling back to /usr/bin/tri"
        echo "run-gl-triangle: compile log: $compile_log"
    fi
else
    echo "run-gl-triangle: using prebuilt /usr/bin/tri (pass --compile to try source build)"
fi

if [ ! -x "$target" ]; then
    echo "run-gl-triangle: no runnable triangle binary found ($target)"
    exit 1
fi

cat > /tmp/.xinitrc.gl << EOF
#!/bin/sh
exec "$target"
EOF
chmod +x /tmp/.xinitrc.gl

if [ "${VINIX_FORCE_SOFTWARE_GL:-1}" = "1" ]; then
    export LIBGL_ALWAYS_SOFTWARE=1
    export MESA_LOADER_DRIVER_OVERRIDE="${MESA_LOADER_DRIVER_OVERRIDE:-swrast}"
fi
if [ "${VINIX_FORCE_INDIRECT_GL:-1}" = "1" ]; then
    export LIBGL_ALWAYS_INDIRECT=1
fi
export LIBGL_DRIVERS_PATH="${LIBGL_DRIVERS_PATH:-/usr/lib/xorg/modules/dri:/usr/lib/dri}"
echo "run-gl-triangle: starting X11 session"
exec /usr/bin/startx /tmp/.xinitrc.gl
GLRUN
    chmod +x "$STAGING/usr/bin/run-gl-triangle"

    # /tmp needs to exist and be writable for X11 sockets
    mkdir -p "$STAGING/tmp/.X11-unix"

    # /var/lib/xkb needed for XKB compiled keymaps
    mkdir -p "$STAGING/var/lib/xkb"

    # Direct X11 launcher — bypasses xinit (which has a UDF crash on aarch64).
    cat > "$STAGING/usr/bin/startx" << 'STARTX'
#!/bin/sh
# Direct X11 launcher for Vinix on aarch64.
set -e

mkdir -p /tmp/.X11-unix

d=0
while [ -e "/tmp/.X11-unix/X$d" ] || [ -e "/tmp/.X$d-lock" ]; do
    d=$((d + 1))
done
display=":$d"
export DISPLAY="$display"

echo "startx: launching Xorg on $display"
/usr/bin/Xorg "$display" +iglx -noreset \
    </dev/null >/var/log/Xorg.startx.log 2>&1 &
SERVER_PID=$!
echo "startx: Xorg PID=$SERVER_PID (sleeping 1s for init)"
sleep 1

if [ "$#" -gt 0 ]; then
    if [ -f "$1" ]; then
        client="$1"
        shift
        exec /bin/sh "$client" "$@"
    else
        exec "$@"
    fi
elif [ -f "$HOME/.xinitrc" ]; then
    exec /bin/sh "$HOME/.xinitrc"
else
    exec xclock -geometry 400x400+50+50
fi
STARTX
    chmod +x "$STAGING/usr/bin/startx"

    # musl dynamic linker library search path config
    # Xorg modules (libfbdevhw.so etc.) live in /usr/lib/xorg/modules/
    # and are DT_NEEDED by drivers loaded via dlopen
    cat > "$STAGING/etc/ld-musl-aarch64.path" << 'LDPATH'
/lib
/usr/lib
/usr/lib/xorg/modules
LDPATH

    # Generate fonts.dir for the misc font directory.
    # Prefer the Docker-generated fonts.dir (has correct XLFD names from mkfontdir).
    # Fall back to a simplified generator if Docker version not available.
    if [ -d "$STAGING/usr/share/fonts/X11/misc" ]; then
        FONT_DIR="$STAGING/usr/share/fonts/X11/misc"
        if [ -f "$FONT_DIR/fonts.dir" ] && [ "$(head -1 "$FONT_DIR/fonts.dir")" -gt 10 ] 2>/dev/null; then
            FONT_COUNT=$(head -1 "$FONT_DIR/fonts.dir")
            echo "    Using existing fonts.dir ($FONT_COUNT fonts)"
        else
            cd "$FONT_DIR"
            FONT_COUNT=$(ls *.pcf.gz 2>/dev/null | wc -l | tr -d ' ')
            echo "$FONT_COUNT" > fonts.dir
            for f in *.pcf.gz; do
                [ -f "$f" ] || continue
                basename="${f%.pcf.gz}"
                echo "$f -misc-$basename-medium-r-normal--0-0-0-0-c-0-iso8859-1" >> fonts.dir
            done
            cd "$STAGING"
            echo "    Generated fonts.dir ($FONT_COUNT fonts)"
        fi
        # Ensure fonts.alias exists
        if [ ! -f "$FONT_DIR/fonts.alias" ]; then
            cat > "$FONT_DIR/fonts.alias" << 'FONTALIAS'
fixed	-misc-fixed-medium-r-semicondensed--13-120-75-75-c-60-iso8859-1
cursor	cursor
FONTALIAS
            echo "    Created fonts.alias"
        fi
    fi

    X11_SIZE=$(du -sh "$X11_STAGING" | cut -f1)
    echo "    X11 files integrated ($X11_SIZE)"
else
    echo "==> X11 staging not found, skipping (run build-x11-aarch64.sh first)"
fi

echo "==> Packaging initramfs..."
INITRAMFS="$INIT_DIR/initramfs.tar"
mkdir -p "$INIT_DIR"
cd "$STAGING"
COPYFILE_DISABLE=1 tar --format=ustar -cf "$INITRAMFS" .
echo "    initramfs: $(du -h "$INITRAMFS" | cut -f1)"
echo ""
echo "=== Build complete ==="
echo "Initramfs: $INITRAMFS"
echo "Busybox applets: $(find "$STAGING" -type l | wc -l | tr -d ' ')"
echo ""
echo "To boot: ./run-aarch64.sh"
