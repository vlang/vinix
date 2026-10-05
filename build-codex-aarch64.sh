#!/bin/bash
# Stage the official Codex CLI ARM64/musl package for Vinix.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${VINIX_CODEX_BUILD_DIR:-$SCRIPT_DIR/build-aarch64-codex}"
DOWNLOADS="$BUILD_DIR/downloads"
STAGING="$BUILD_DIR/staging"
PACKAGE_DIR="$BUILD_DIR/package"

CODEX_VERSION="${CODEX_VERSION:-0.153.4}"
CODEX_ARCHIVE="codex-${CODEX_VERSION}-linux-arm64.tgz"
CODEX_URL="${CODEX_URL:-https://registry.npmjs.org/@openai/codex/-/$CODEX_ARCHIVE}"
CODEX_SHA256="${CODEX_SHA256:-439c0dd0d6923f607b4e5cd1e3079c12f0b86f6e5007f07e377d6ad25e2d7bb9}"

ALPINE_MIRROR="${ALPINE_MIRROR:-https://dl-cdn.alpinelinux.org/alpine/v3.21}"
ALPINE_ARCH=aarch64

mkdir -p "$DOWNLOADS"

download_apk() {
    local repo="$1" pkg="$2"
    local index_file="$DOWNLOADS/${repo}_APKINDEX"

    if [ ! -f "$index_file" ]; then
        echo "  fetching ${repo} index"
        curl -fsSL "${ALPINE_MIRROR}/${repo}/${ALPINE_ARCH}/APKINDEX.tar.gz" \
            | tar xzOf - APKINDEX > "$index_file"
    fi

    local filename
    filename=$(awk -v pkg="$pkg" '
        /^P:/{name=$0; sub(/^P:/,"",name)}
        /^V:/{ver=$0; sub(/^V:/,"",ver)}
        /^$/{if(name==pkg) print name "-" ver ".apk"}
    ' "$index_file")

    if [ -z "$filename" ]; then
        return 1
    fi

    local local_file="$DOWNLOADS/${filename}"
    if [ ! -f "$local_file" ]; then
        echo "  downloading ${filename}"
        curl -fsSL -o "$local_file" \
            "${ALPINE_MIRROR}/${repo}/${ALPINE_ARCH}/${filename}"
    fi

    echo "  extracting ${filename}"
    tar xzf "$local_file" -C "$STAGING" 2>/dev/null
    rm -f "$STAGING/.PKGINFO" "$STAGING/.SIGN"* "$STAGING/.trigger"* \
        "$STAGING/.post-"* 2>/dev/null || true
}

echo "=== staging Codex CLI ${CODEX_VERSION} for $ALPINE_ARCH ==="
if [ ! -f "$DOWNLOADS/$CODEX_ARCHIVE" ]; then
    echo "  downloading $CODEX_ARCHIVE"
    curl -fL --retry 3 -o "$DOWNLOADS/$CODEX_ARCHIVE" "$CODEX_URL"
fi

actual_sha256=$(shasum -a 256 "$DOWNLOADS/$CODEX_ARCHIVE" | awk '{print $1}')
if [ "$actual_sha256" != "$CODEX_SHA256" ]; then
    echo "Codex package checksum mismatch" >&2
    echo "  expected: $CODEX_SHA256" >&2
    echo "  actual:   $actual_sha256" >&2
    exit 1
fi

rm -rf "$STAGING" "$PACKAGE_DIR"
mkdir -p "$STAGING" "$PACKAGE_DIR"
tar xzf "$DOWNLOADS/$CODEX_ARCHIVE" -C "$PACKAGE_DIR"

UPSTREAM_PACKAGE="$PACKAGE_DIR/package/vendor/aarch64-unknown-linux-musl"
if [ ! -x "$UPSTREAM_PACKAGE/bin/codex" ]; then
    echo "Codex package does not contain the ARM64/musl executable" >&2
    exit 1
fi

CODEX_ROOT="$STAGING/usr/lib/codex"
mkdir -p "$CODEX_ROOT" "$STAGING/usr/bin" "$STAGING/root"
cp -a "$UPSTREAM_PACKAGE/." "$CODEX_ROOT/"

# Codex's ARM64/musl npm package currently carries glibc builds of its bundled
# rg and zsh helpers. Replace them with Alpine's musl builds, including their
# dynamic loader and shared dependencies, so every executable in the staged
# package is usable on Vinix.
ALPINE_PKGS=(
    musl
    ca-certificates-bundle
    libgcc
    pcre2
    ripgrep
    libcap2
    libncursesw
    ncurses-terminfo-base
    zsh
)
for pkg in "${ALPINE_PKGS[@]}"; do
    download_apk main "$pkg" || download_apk community "$pkg" || {
        echo "Alpine package not found: $pkg" >&2
        exit 1
    }
done

install -m755 "$STAGING/usr/bin/rg" "$CODEX_ROOT/codex-path/rg"
install -m755 "$STAGING/bin/zsh" "$CODEX_ROOT/codex-resources/zsh/bin/zsh"
install -m644 "$SCRIPT_DIR/tests/codex/smoke.py" "$STAGING/root/codex-smoke.py"

# Make absolute package symlinks self-contained in the staging tree.
find "$STAGING" -type l | while IFS= read -r link; do
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

# Use tiny launchers rather than copying another 270 MiB into the initramfs.
# They also make /proc/self/exe identify the executable inside its package;
# Codex uses that location to discover codex-package.json and its helpers.
cat > "$STAGING/usr/bin/codex" <<'EOF'
#!/bin/sh
# Shell snapshots currently depend on Linux process details Vinix does not yet
# provide, and telemetry adds background workers without affecting CLI use.
exec /usr/lib/codex/bin/codex \
    "$@" \
    -c 'features.shell_snapshot=false' \
    -c 'analytics.enabled=false'
EOF
cat > "$STAGING/usr/bin/codex-code-mode-host" <<'EOF'
#!/bin/sh
exec /usr/lib/codex/bin/codex-code-mode-host "$@"
EOF
chmod +x "$STAGING/usr/bin/codex" "$STAGING/usr/bin/codex-code-mode-host"

echo
echo "staged: $(du -sh "$STAGING" | cut -f1)"
file "$CODEX_ROOT/bin/codex" "$CODEX_ROOT/bin/codex-code-mode-host" \
    "$CODEX_ROOT/codex-path/rg" "$CODEX_ROOT/codex-resources/zsh/bin/zsh"
