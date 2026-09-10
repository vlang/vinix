#!/bin/bash
# Assemble the aarch64 Vinix userland from official Alpine binaries.
#
# The base filesystem, BusyBox, musl, Linux headers, and optional guest GCC
# come from Alpine packages. Nothing in this script builds a libc, compiler,
# or base command suite from source.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -x "$SCRIPT_DIR/link-worktree-build-dirs.sh" ]; then
    "$SCRIPT_DIR/link-worktree-build-dirs.sh"
fi

BUILD_DIR="${VINIX_AARCH64_USERLAND_BUILD_DIR:-$SCRIPT_DIR/build-aarch64-userland}"
DOWNLOADS="$BUILD_DIR/downloads"
STAGING="$BUILD_DIR/staging"
DEVTOOLS_STAGING="$BUILD_DIR/alpine-devtools"
DEVTOOLS_ARCHIVE="$BUILD_DIR/alpine-devtools.tar"
INIT_DIR="$SCRIPT_DIR/build-support/init-aarch64"
INITRAMFS="${VINIX_AARCH64_INITRAMFS:-$INIT_DIR/initramfs.tar}"

ALPINE_VERSION="${ALPINE_VERSION:-3.21.7}"
ALPINE_BRANCH="${ALPINE_BRANCH:-v3.21}"
ALPINE_MIRROR="${ALPINE_MIRROR:-https://dl-cdn.alpinelinux.org/alpine}"
ALPINE_ARCH=aarch64
ALPINE_SHA256="${ALPINE_SHA256:-d1d1a3fae5f4d6146e9742790a47fcb116199622cfb8439f218a4d5fbe5000da}"
ALPINE_DEVTOOLS="${VINIX_ALPINE_DEVTOOLS:-1}"
ALPINE_BASE_ONLY="${VINIX_ALPINE_BASE_ONLY:-0}"
ARCHIVE="alpine-minirootfs-${ALPINE_VERSION}-${ALPINE_ARCH}.tar.gz"
ARCHIVE_PATH="$DOWNLOADS/$ARCHIVE"
REPOSITORY_ROOT="$ALPINE_MIRROR/$ALPINE_BRANCH"

PYTHON_STAGING="${VINIX_PYTHON_STAGING:-$SCRIPT_DIR/build-aarch64-python/staging}"
RUBY_STAGING="${VINIX_RUBY_STAGING:-$SCRIPT_DIR/build-aarch64-ruby/staging}"
GO_STAGING="${VINIX_GO_STAGING:-$SCRIPT_DIR/build-aarch64-go/staging}"
JAVA_STAGING="${VINIX_JAVA_STAGING:-$SCRIPT_DIR/build-aarch64-java/staging}"
NETWORK_TOOLS_STAGING="${VINIX_NETWORK_TOOLS_STAGING:-$SCRIPT_DIR/build-aarch64-network-tools/staging}"
DEVELOPER_TOOLS_STAGING="${VINIX_DEVELOPER_TOOLS_STAGING:-$SCRIPT_DIR/build-aarch64-developer-tools/staging}"
FIREFOX_STAGING="${VINIX_FIREFOX_STAGING:-$SCRIPT_DIR/build-aarch64-firefox/staging}"
MINECRAFT_STAGING="${VINIX_MINECRAFT_STAGING:-$SCRIPT_DIR/build-aarch64-minecraft/staging}"
CODEX_STAGING="${VINIX_CODEX_STAGING:-$SCRIPT_DIR/build-aarch64-codex/staging}"
CLAUDE_STAGING="${VINIX_CLAUDE_STAGING:-$SCRIPT_DIR/build-aarch64-claude/staging}"
X86_TRANSLATION_STAGING="${VINIX_X86_TRANSLATION_STAGING:-$SCRIPT_DIR/build-aarch64-x86-translation/staging}"

case "$BUILD_DIR" in
    ''|/|"$SCRIPT_DIR")
        echo "ERROR: refusing unsafe aarch64 userland build directory: $BUILD_DIR" >&2
        exit 1
        ;;
esac

for tool in curl file python3 tar; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "missing build tool: $tool" >&2
        exit 1
    fi
done

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

sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

fetch_alpine_indexes() {
    local repository archive index
    for repository in main community; do
        archive="$DOWNLOADS/${repository}_APKINDEX.tar.gz"
        index="$DOWNLOADS/${repository}_APKINDEX"
        if [ ! -f "$index" ]; then
            echo "    fetching Alpine ${repository} index"
            curl -fL --retry 3 \
                "$REPOSITORY_ROOT/$repository/$ALPINE_ARCH/APKINDEX.tar.gz" \
                -o "$archive"
            tar xOf "$archive" APKINDEX > "$index"
        fi
    done
}

stage_alpine_packages() {
    local destination="$1" repository filename package_archive
    shift

    fetch_alpine_indexes
    python3 "$SCRIPT_DIR/build-support/alpine-resolve.py" \
        --index main "$DOWNLOADS/main_APKINDEX" \
        --index community "$DOWNLOADS/community_APKINDEX" \
        "$@" > "$BUILD_DIR/packages"

    while IFS=$'\t' read -r repository filename; do
        [ -n "$filename" ] || continue
        package_archive="$DOWNLOADS/$filename"
        if [ ! -f "$package_archive" ]; then
            echo "    downloading $filename"
            curl -fL --retry 3 \
                "$REPOSITORY_ROOT/$repository/$ALPINE_ARCH/$filename" \
                -o "$package_archive"
        fi
        echo "    extracting $filename"
        # APK signatures, metadata, and payload are concatenated tar streams.
        # bsdtar can report the trailing stream after extracting the payload.
        tar -ixzf "$package_archive" -C "$destination" 2>/dev/null || true
        rm -f "$destination/.PKGINFO" "$destination/.SIGN"* \
            "$destination/.trigger"* "$destination/.pre-"* "$destination/.post-"*
    done < "$BUILD_DIR/packages"
}

mkdir -p "$DOWNLOADS"
if [ ! -f "$ARCHIVE_PATH" ]; then
    echo "==> Fetching Alpine ${ALPINE_VERSION} aarch64 minirootfs..."
    curl -fL --retry 3 \
        "$REPOSITORY_ROOT/releases/$ALPINE_ARCH/$ARCHIVE" \
        -o "$ARCHIVE_PATH"
fi

ARCHIVE_ACTUAL_SHA256="$(sha256_file "$ARCHIVE_PATH")"
if [ "$ARCHIVE_ACTUAL_SHA256" != "$ALPINE_SHA256" ]; then
    echo "ERROR: Alpine minirootfs checksum mismatch." >&2
    echo "Expected: $ALPINE_SHA256" >&2
    echo "Actual:   $ARCHIVE_ACTUAL_SHA256" >&2
    exit 1
fi

echo "==> Staging the Alpine aarch64 userland..."
rm -rf "$STAGING"
mkdir -p "$STAGING"
tar -xzf "$ARCHIVE_PATH" -C "$STAGING"

if [ "$ALPINE_DEVTOOLS" = 1 ]; then
    echo "==> Staging Alpine's prebuilt C/C++ toolchain..."
    rm -rf "$DEVTOOLS_STAGING"
    mkdir -p "$DEVTOOLS_STAGING"
    stage_alpine_packages "$DEVTOOLS_STAGING" build-base
    merge_staging_tree "$DEVTOOLS_STAGING"
    DEVTOOLS_ARCHIVE_TMP="$(mktemp "$BUILD_DIR/.alpine-devtools.tar.XXXXXX")"
    if ! COPYFILE_DISABLE=1 tar --format=ustar -cf "$DEVTOOLS_ARCHIVE_TMP" \
        -C "$DEVTOOLS_STAGING" .; then
        rm -f "$DEVTOOLS_ARCHIVE_TMP"
        exit 1
    fi
    mv -f "$DEVTOOLS_ARCHIVE_TMP" "$DEVTOOLS_ARCHIVE"
else
    echo "==> Skipping guest development tools (VINIX_ALPINE_DEVTOOLS=0)"
    : > "$BUILD_DIR/packages"
    rm -f "$DEVTOOLS_ARCHIVE"
fi

# Vinix starts /sbin/init directly. Keep the base userland entirely Alpine:
# this shell script is interpreted by Alpine's stock /bin/busybox.
rm -f "$STAGING/sbin/init"
install -m755 "$SCRIPT_DIR/build-support/init-aarch64/alpine-init" \
    "$STAGING/sbin/init"
mkdir -p "$STAGING/dev" "$STAGING/proc" "$STAGING/sys" "$STAGING/tmp" \
    "$STAGING/root" "$STAGING/var/log" "$STAGING/var/run"
chmod 1777 "$STAGING/tmp"

cat > "$STAGING/etc/profile" << 'EOF'
export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
export HOME=/root
export TERM=linux
export PS1='vinix# '
export LD_LIBRARY_PATH=/usr/lib:/usr/lib/xorg/modules
export LIBGL_DRIVERS_PATH=/usr/lib/xorg/modules/dri:/usr/lib/dri
export SSL_CA_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
export XBPS_ARCH=aarch64
EOF

cat > "$STAGING/root/hello.c" << 'EOF'
#include <stdio.h>
int main(void) {
    printf("Hello from Alpine GCC on Vinix!\n");
    return 0;
}
EOF

if [ ! -x "$STAGING/bin/busybox" ] ||
   [ ! -e "$STAGING/lib/ld-musl-aarch64.so.1" ]; then
    echo "ERROR: Alpine base userland is incomplete" >&2
    exit 1
fi
if [ "$ALPINE_DEVTOOLS" = 1 ] && [ ! -x "$STAGING/usr/bin/gcc" ]; then
    echo "ERROR: Alpine build-base did not provide /usr/bin/gcc" >&2
    exit 1
fi

file "$STAGING/bin/busybox" "$STAGING/lib/ld-musl-aarch64.so.1"

# ── Optional runtime overlays ──
if [ "$ALPINE_BASE_ONLY" != 1 ]; then
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
    for incdir in EGL GL GLES2 GLES3 KHR X11; do
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

    # Keep the exact EGL/GLES source in the image so --rebuild verifies that
    # the Vinix-hosted GCC can compile and link against the Asahi userspace.
    if [ -f "$SCRIPT_DIR/gl-triangle/egl_triangle.c" ]; then
        mkdir -p "$STAGING/usr/share/examples/gl-triangle"
        cp "$SCRIPT_DIR/gl-triangle/egl_triangle.c" \
            "$STAGING/usr/share/examples/gl-triangle/"
    fi

    # Helper that compiles and launches the triangle under Xorg.
cat > "$STAGING/usr/bin/run-gl-triangle" << 'GLRUN'
#!/bin/sh
set -e

# Prefer the render-only Apple GPU path when its Mesa runtime and DRM node are
# present.  It displays through /dev/fb0 and deliberately bypasses Xorg.
if [ "${VINIX_FORCE_SOFTWARE_GL:-0}" != "1" ] \
    && [ -e /dev/dri/renderD128 ] \
    && [ -x /usr/bin/run-gl-triangle-agx ] \
    && [ -x /usr/bin/gl-triangle-agx ]; then
    exec /usr/bin/run-gl-triangle-agx "$@"
fi

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

    # Direct launcher — bypasses xinit (which has a UDF crash on aarch64) and
    # stops Xorg when its client exits so a native compositor can reclaim fb0.
    install -m755 "$SCRIPT_DIR/build-support/xorg-server/startx" \
        "$STAGING/usr/bin/startx"

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

# Firefox brings its GTK/X11 client-side dependency closure. Merge it before
# Asahi so the hardware-specific Mesa runtime remains authoritative on M1.
if [ -x "$FIREFOX_STAGING/usr/bin/run-firefox" ]; then
    echo "==> Integrating Firefox ESR runtime..."
    cp -a "$FIREFOX_STAGING/." "$STAGING/"
else
    echo "==> Firefox staging not found, skipping (run build-firefox-aarch64.sh first)"
fi

# Minetest is a native C++/SDL/OpenGL client. Merge it before Asahi so the
# hardware-specific Mesa userspace remains the final graphics implementation.
if [ -x "$MINECRAFT_STAGING/usr/bin/minecraft" ]; then
    echo "==> Integrating C++ Minecraft runtime..."
    merge_staging_tree "$MINECRAFT_STAGING"
else
    echo "==> Minecraft staging not found, skipping (run build-minecraft-aarch64.sh first)"
fi

# The native Asahi build is produced in the Debian ARM64 VM. Once its staging
# directory has been copied back beside this script, merge it last so its EGL,
# GLES and Gallium libraries replace any software-only Mesa copies from X11.
ASAHI_STAGING="$SCRIPT_DIR/build-aarch64-asahi/staging"
if [ -x "$ASAHI_STAGING/usr/bin/gl-triangle-agx" ]; then
    echo "==> Integrating native Apple GPU userspace..."
    cp -a "$ASAHI_STAGING/." "$STAGING/"
    install -m755 "$SCRIPT_DIR/gl-triangle/run-gl-triangle" \
        "$STAGING/usr/bin/run-gl-triangle"
    install -m755 "$SCRIPT_DIR/gl-triangle/run-gl-triangle-agx" \
        "$STAGING/usr/bin/run-gl-triangle-agx"
    install -m755 "$SCRIPT_DIR/gl-triangle/run-m1-agx-smoke" \
        "$STAGING/usr/bin/run-m1-agx-smoke"

    # Make copied library links self-contained in the initramfs. Some links
    # in the Alpine packages are absolute and otherwise resolve on the host.
    find "$STAGING/usr/lib" -type l -name '*.so*' | while IFS= read -r link; do
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
else
    echo "==> Asahi staging not found, skipping (run build-asahi-aarch64.sh in the ARM64 VM first)"
fi

if [ -x "$PYTHON_STAGING/usr/bin/python3" ]; then
    echo "==> Integrating Python 3 runtime..."
    cp -a "$PYTHON_STAGING/." "$STAGING/"
else
    echo "==> Python 3 staging not found, skipping (run build-python-aarch64.sh first)"
fi

if [ -x "$RUBY_STAGING/usr/bin/ruby" ]; then
    echo "==> Integrating Ruby runtime..."
    cp -a "$RUBY_STAGING/." "$STAGING/"
else
    echo "==> Ruby staging not found, skipping (run build-ruby-aarch64.sh first)"
fi

if [ -x "$GO_STAGING/usr/bin/go" ] || [ -x "$GO_STAGING/usr/lib/go/bin/go" ]; then
    echo "==> Integrating Go toolchain..."
    merge_staging_tree "$GO_STAGING"
else
    echo "==> Go staging not found, skipping (run build-go-aarch64.sh first)"
fi

if [ -x "$JAVA_STAGING/usr/bin/java" ] && [ -x "$JAVA_STAGING/usr/bin/javac" ]; then
    echo "==> Integrating OpenJDK runtime and toolchain..."
    merge_staging_tree "$JAVA_STAGING"
else
    echo "==> OpenJDK staging not found, skipping (run build-java-aarch64.sh first)"
fi

if [ -x "$NETWORK_TOOLS_STAGING/usr/bin/curl" ]; then
    echo "==> Integrating network developer tools..."
    cp -a "$NETWORK_TOOLS_STAGING/." "$STAGING/"
else
    echo "==> Network tools staging not found, skipping (run build-network-tools-aarch64.sh first)"
fi

if [ -x "$DEVELOPER_TOOLS_STAGING/usr/bin/cmake" ]; then
    echo "==> Integrating native developer tools..."
    merge_staging_tree "$DEVELOPER_TOOLS_STAGING"
else
    echo "==> Developer tools staging not found, skipping (run build-developer-tools-aarch64.sh first)"
fi

if [ -x "$CODEX_STAGING/usr/bin/codex" ]; then
    echo "==> Integrating Codex CLI runtime..."
    cp -a "$CODEX_STAGING/." "$STAGING/"
else
    echo "==> Codex staging not found, skipping (run build-codex-aarch64.sh first)"
fi

if [ -x "$CLAUDE_STAGING/usr/bin/claude" ]; then
    echo "==> Integrating Claude Code CLI runtime..."
    cp -a "$CLAUDE_STAGING/." "$STAGING/"
else
    echo "==> Claude Code staging not found, skipping (run build-claude-aarch64.sh first)"
fi

if [ -x "$X86_TRANSLATION_STAGING/usr/bin/qemu-x86_64" ]; then
    echo "==> Integrating x86-64 translation and Wine runtime..."
    merge_staging_tree "$X86_TRANSLATION_STAGING"
else
    echo "==> x86-64 translation staging not found, skipping (run build-x86-translation-aarch64.sh first)"
fi
else
    echo "==> Skipping optional runtime overlays (VINIX_ALPINE_BASE_ONLY=1)"
fi

echo "==> Packaging initramfs..."
mkdir -p "$(dirname "$INITRAMFS")"
cd "$STAGING"
# Write beside the published image and rename only once tar has finished.
# deploy/push can run while this build is in progress; writing INITRAMFS
# directly lets rsync observe a truncated tar and abort mid-transfer.
INITRAMFS_TMP="$(mktemp "$(dirname "$INITRAMFS")/.initramfs.tar.XXXXXX")"
if ! COPYFILE_DISABLE=1 tar --format=ustar -cf "$INITRAMFS_TMP" .; then
    rm -f "$INITRAMFS_TMP"
    exit 1
fi
mv -f "$INITRAMFS_TMP" "$INITRAMFS"
echo "    initramfs: $(du -h "$INITRAMFS" | cut -f1)"
echo ""
echo "=== Build complete ==="
echo "Initramfs: $INITRAMFS"
echo "Busybox applets: $(find "$STAGING" -type l | wc -l | tr -d ' ')"
echo ""
echo "To boot: ./run-aarch64.sh"
