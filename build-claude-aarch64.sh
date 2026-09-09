#!/bin/bash
# Stage the official Claude Code CLI ARM64/musl package for Vinix.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${VINIX_CLAUDE_BUILD_DIR:-$SCRIPT_DIR/build-aarch64-claude}"
DOWNLOADS="$BUILD_DIR/downloads"
STAGING="$BUILD_DIR/staging"
PACKAGE_DIR="$BUILD_DIR/package"

CLAUDE_VERSION="${CLAUDE_VERSION:-2.1.266}"
CLAUDE_ARCHIVE="claude-code-linux-arm64-musl-${CLAUDE_VERSION}.tgz"
CLAUDE_URL="${CLAUDE_URL:-https://registry.npmjs.org/@anthropic-ai/claude-code-linux-arm64-musl/-/$CLAUDE_ARCHIVE}"
CLAUDE_SHA256="${CLAUDE_SHA256:-2db7557a5d89d23e4bd56b42d0bd24628c9924c54463cd755e5ced4e64337cd3}"

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

echo "=== staging Claude Code CLI ${CLAUDE_VERSION} for $ALPINE_ARCH ==="
if [ ! -f "$DOWNLOADS/$CLAUDE_ARCHIVE" ]; then
    echo "  downloading $CLAUDE_ARCHIVE"
    curl -fL --retry 3 -o "$DOWNLOADS/$CLAUDE_ARCHIVE" "$CLAUDE_URL"
fi

actual_sha256=$(shasum -a 256 "$DOWNLOADS/$CLAUDE_ARCHIVE" | awk '{print $1}')
if [ "$actual_sha256" != "$CLAUDE_SHA256" ]; then
    echo "Claude Code package checksum mismatch" >&2
    echo "  expected: $CLAUDE_SHA256" >&2
    echo "  actual:   $actual_sha256" >&2
    exit 1
fi

rm -rf "$STAGING" "$PACKAGE_DIR"
mkdir -p "$STAGING" "$PACKAGE_DIR"
tar xzf "$DOWNLOADS/$CLAUDE_ARCHIVE" -C "$PACKAGE_DIR"

UPSTREAM_PACKAGE="$PACKAGE_DIR/package"
if [ ! -x "$UPSTREAM_PACKAGE/claude" ]; then
    echo "Claude Code package does not contain the ARM64/musl executable" >&2
    exit 1
fi

CLAUDE_ROOT="$STAGING/usr/lib/claude-code"
mkdir -p "$CLAUDE_ROOT" "$STAGING/usr/bin" "$STAGING/root"
install -m755 "$UPSTREAM_PACKAGE/claude" "$CLAUDE_ROOT/claude"
install -m644 "$UPSTREAM_PACKAGE/LICENSE.md" "$CLAUDE_ROOT/LICENSE.md"
install -m644 "$UPSTREAM_PACKAGE/README.md" "$CLAUDE_ROOT/README.md"

# Anthropic's native musl build requires these Alpine packages and recommends
# selecting the system ripgrep instead of its non-musl bundled helper.
ALPINE_PKGS=(
    musl
    ca-certificates-bundle
    libgcc
    libstdc++
    pcre2
    ripgrep
)
for pkg in "${ALPINE_PKGS[@]}"; do
    download_apk main "$pkg" || download_apk community "$pkg" || {
        echo "Alpine package not found: $pkg" >&2
        exit 1
    }
done

install -m644 "$SCRIPT_DIR/tests/claude/smoke.py" \
    "$STAGING/root/claude-smoke.py"

# Keep update and telemetry workers out of the compatibility surface. The CLI
# still makes the model requests and tool calls explicitly requested by users.
printf '%s\n' '#!/bin/sh' "claude_code_version='$CLAUDE_VERSION'" \
    > "$STAGING/usr/bin/claude"
cat >> "$STAGING/usr/bin/claude" <<'EOF'

# Claude queues several writes when its generated first-run fields are absent.
# On Vinix the embedded Bun event loop can become idle between those writes,
# before the CLI is ready. Seed only the generated bookkeeping fields; Claude
# owns the file from this point onward and performs normal migrations.
claude_bootstrap_config() {
    claude_home_dir=${HOME:-/root}
    claude_config_file="$claude_home_dir/.claude.json"
    if [ -e "$claude_config_file" ] || [ ! -d "$claude_home_dir" ]; then
        return
    fi

    claude_machine_id=$(/bin/busybox od -An -N32 -tx1 /dev/urandom 2>/dev/null \
        | /bin/busybox tr -d ' \n')
    claude_user_id=$(/bin/busybox od -An -N32 -tx1 /dev/urandom 2>/dev/null \
        | /bin/busybox tr -d ' \n')
    if [ "${#claude_machine_id}" -ne 64 ] || [ "${#claude_user_id}" -ne 64 ]; then
        return
    fi

    claude_started_at=$(/bin/busybox date -u '+%Y-%m-%dT%H:%M:%S.000Z' 2>/dev/null) \
        || claude_started_at=1970-01-01T00:00:00.000Z
    claude_config_tmp="$claude_config_file.vinix.$$"
    umask 077
    if ! printf '{\n  "firstStartTime": "%s",\n  "firstStartVersion": "%s",\n  "machineID": "%s",\n  "userID": "%s",\n  "opusProMigrationComplete": true,\n  "sonnet1m45MigrationComplete": true,\n  "seenNotifications": {},\n  "hasResetAutoModeOptInForDefaultOffer": true,\n  "migrationVersion": 14\n}\n' \
        "$claude_started_at" "$claude_code_version" "$claude_machine_id" \
        "$claude_user_id" > "$claude_config_tmp"; then
        return
    fi

    # A hard link installs the seed atomically without replacing a config that
    # another Claude process may have created concurrently.
    /bin/busybox ln "$claude_config_tmp" "$claude_config_file" 2>/dev/null || true
    /bin/busybox rm -f "$claude_config_tmp"
}

case "${1:-}" in
    --help|-h|--version|-v) ;;
    *) claude_bootstrap_config ;;
esac

export USE_BUILTIN_RIPGREP=0
export DISABLE_AUTOUPDATER=1
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
exec /usr/lib/claude-code/claude "$@"
EOF
chmod +x "$STAGING/usr/bin/claude"

echo
echo "staged: $(du -sh "$STAGING" | cut -f1)"
file "$CLAUDE_ROOT/claude" "$STAGING/usr/bin/rg"
