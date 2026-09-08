#!/bin/bash
# Stage OpenJDK (JDK plus its full JRE) for the Vinix aarch64 userland.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${VINIX_JAVA_BUILD_DIR:-$SCRIPT_DIR/build-aarch64-java}"
DOWNLOADS="$BUILD_DIR/downloads"
STAGING="$BUILD_DIR/staging"

# OpenJDK 25 is the newest OpenJDK release packaged by Alpine 3.24, the latest
# stable Alpine branch. Pin the branch and major package so builds remain
# reproducible while still receiving Alpine's maintenance updates for JDK 25.
ALPINE_MIRROR="${ALPINE_MIRROR:-https://dl-cdn.alpinelinux.org/alpine/v3.24}"
ALPINE_ARCH=aarch64
OPENJDK_PACKAGE=openjdk25-jdk
JAVA_HOME=/usr/lib/jvm/java-25-openjdk

for tool in curl python3 tar; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "missing build tool: $tool" >&2
        exit 1
    fi
done

mkdir -p "$DOWNLOADS"
rm -rf "$STAGING"
mkdir -p "$STAGING"

for repository in main community; do
    index="$DOWNLOADS/${repository}_APKINDEX"
    if [ ! -f "$index" ]; then
        echo "  fetching ${repository} index"
        archive="$DOWNLOADS/${repository}_APKINDEX.tar.gz"
        curl -fL --retry 3 -o "$archive" \
            "$ALPINE_MIRROR/$repository/$ALPINE_ARCH/APKINDEX.tar.gz"
        tar xOf "$archive" APKINDEX > "$index"
    fi
done

echo "=== resolving $OPENJDK_PACKAGE for $ALPINE_ARCH ==="
python3 "$SCRIPT_DIR/build-support/alpine-resolve.py" \
    --index main "$DOWNLOADS/main_APKINDEX" \
    --index community "$DOWNLOADS/community_APKINDEX" \
    "$OPENJDK_PACKAGE" ca-certificates-bundle > "$BUILD_DIR/packages"

while IFS=$'\t' read -r repository filename; do
    [ -n "$filename" ] || continue
    archive="$DOWNLOADS/$filename"
    if [ ! -f "$archive" ]; then
        echo "  downloading $filename"
        curl -fL --retry 3 -o "$archive" \
            "$ALPINE_MIRROR/$repository/$ALPINE_ARCH/$filename"
    fi
    echo "  extracting $filename"
    # APK signatures, metadata and payload are concatenated tar streams. The
    # host tar can report the trailing stream after extracting successfully.
    tar xzf "$archive" -C "$STAGING" 2>/dev/null || true
    rm -f "$STAGING/.PKGINFO" "$STAGING/.SIGN"* "$STAGING/.trigger"* \
        "$STAGING/.pre-"* "$STAGING/.post-"*
done < "$BUILD_DIR/packages"

mkdir -p "$STAGING/root" "$STAGING/usr/bin" "$STAGING/etc/profile.d"
install -m644 "$SCRIPT_DIR/tests/java/VinixJavaSmoke.java" \
    "$STAGING/root/VinixJavaSmoke.java"
install -m755 "$SCRIPT_DIR/tests/java/smoke.sh" \
    "$STAGING/root/java-smoke.sh"

# Alpine normally creates the architecture-independent Java trust store from
# its Mozilla certificate package in an apk trigger. Raw APK extraction does
# not execute triggers, so produce the same JKS input explicitly and keep the
# package's standard $JAVA_HOME/lib/security/cacerts symlink usable.
python3 "$SCRIPT_DIR/build-support/java-cacerts.py" \
    "$STAGING/usr/share/ca-certificates/mozilla" \
    "$STAGING/etc/ssl/certs/java/cacerts"

# java-common normally creates these alternatives from apk maintainer scripts.
# This overlay extracts APK payloads without executing scripts, so publish the
# JDK commands explicitly. Relative aliases remain valid after the tree is
# merged into the initramfs.
for command_path in "$STAGING$JAVA_HOME/bin/"*; do
    [ -x "$command_path" ] || continue
    command_name=$(basename "$command_path")
    ln -sf "../lib/jvm/java-25-openjdk/bin/$command_name" \
        "$STAGING/usr/bin/$command_name"
done

cat > "$STAGING/etc/profile.d/java.sh" <<'EOF'
export JAVA_HOME=/usr/lib/jvm/java-25-openjdk
export PATH="$JAVA_HOME/bin:$PATH"
EOF

# Vinix's dynamic loader currently opens shared objects without following
# aliases. Materialize library links, but retain command and JVM-directory
# aliases such as /usr/bin/java and $JAVA_HOME/jre.
find "$STAGING/lib" "$STAGING/usr/lib" -type l -name '*.so*' 2>/dev/null | \
while IFS= read -r link; do
    target=$(readlink "$link")
    case "$target" in
        /*) real="$STAGING$target" ;;
        *)  real="$(dirname "$link")/$target" ;;
    esac
    if [ -f "$real" ]; then
        rm "$link"
        cp "$real" "$link"
    fi
done

for binary in java javac jar; do
    if [ ! -x "$STAGING/usr/bin/$binary" ]; then
        echo "missing staged Java binary: $binary" >&2
        exit 1
    fi
done
if [ ! -f "$STAGING$JAVA_HOME/lib/server/libjvm.so" ]; then
    echo "missing staged HotSpot server VM" >&2
    exit 1
fi
if [ ! -s "$STAGING/etc/ssl/certs/java/cacerts" ]; then
    echo "missing staged Java CA trust store" >&2
    exit 1
fi

echo
echo "staged: $(du -sh "$STAGING" | cut -f1)"
echo "packages: $(wc -l < "$BUILD_DIR/packages" | tr -d ' ')"
echo "java home: $JAVA_HOME"
