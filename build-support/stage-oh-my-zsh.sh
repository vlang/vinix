#!/bin/bash
# Install a verified, self-contained Oh My Zsh tree into a staged Vinix root.
set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "usage: $0 STAGING DOWNLOADS" >&2
    exit 2
fi

STAGING=$1
DOWNLOADS=$2
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Pin the source archive so creating an image never executes a moving upstream
# revision. These values can be overridden together when intentionally updating
# Oh My Zsh.
OH_MY_ZSH_REF="${OH_MY_ZSH_REF:-c6e66edee824d83e84473ec666917b58323630df}"
OH_MY_ZSH_SHA256="${OH_MY_ZSH_SHA256:-200d79c1fa0784107cd897db96c7823ecae4cec332026a7f4471568fc59db519}"
OH_MY_ZSH_URL="${OH_MY_ZSH_URL:-https://github.com/ohmyzsh/ohmyzsh/archive/$OH_MY_ZSH_REF.tar.gz}"

case "$STAGING" in
    ''|/)
        echo "ERROR: refusing unsafe staging directory: $STAGING" >&2
        exit 1
        ;;
esac
case "$OH_MY_ZSH_REF" in
    *[!0123456789abcdef]*|'')
        echo "ERROR: OH_MY_ZSH_REF must be a lowercase Git commit ID" >&2
        exit 1
        ;;
esac
if [ "${#OH_MY_ZSH_REF}" -ne 40 ]; then
    echo "ERROR: OH_MY_ZSH_REF must be a 40-character Git commit ID" >&2
    exit 1
fi
case "$OH_MY_ZSH_SHA256" in
    *[!0123456789abcdef]*|'')
        echo "ERROR: OH_MY_ZSH_SHA256 must be a SHA-256 digest" >&2
        exit 1
        ;;
esac
if [ "${#OH_MY_ZSH_SHA256}" -ne 64 ]; then
    echo "ERROR: OH_MY_ZSH_SHA256 must be a SHA-256 digest" >&2
    exit 1
fi

sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

ARCHIVE="$DOWNLOADS/oh-my-zsh-$OH_MY_ZSH_REF.tar.gz"
TARGET="$STAGING/root/.oh-my-zsh"
mkdir -p "$DOWNLOADS" "$STAGING/root"

if [ ! -f "$ARCHIVE" ]; then
    echo "==> Fetching Oh My Zsh $OH_MY_ZSH_REF..."
    curl -fL --retry 3 "$OH_MY_ZSH_URL" -o "$ARCHIVE"
fi

ARCHIVE_SHA256="$(sha256_file "$ARCHIVE")"
if [ "$ARCHIVE_SHA256" != "$OH_MY_ZSH_SHA256" ]; then
    echo "ERROR: Oh My Zsh archive checksum mismatch." >&2
    echo "Expected: $OH_MY_ZSH_SHA256" >&2
    echo "Actual:   $ARCHIVE_SHA256" >&2
    exit 1
fi

# The userland builders recreate STAGING from scratch, but clear the target so
# an intentional version override cannot leave stale plugins or themes behind.
rm -rf "$TARGET"
mkdir -p "$TARGET"
tar -xzf "$ARCHIVE" --strip-components=1 -C "$TARGET"

cat > "$STAGING/root/.zshrc" <<'EOF'
# Oh My Zsh is installed in the base Vinix image, so an interactive Zsh shell
# is ready without downloading or installing anything in the guest.
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=()

source "$ZSH/oh-my-zsh.sh"
EOF

install -m755 "$REPOSITORY_ROOT/tests/zsh/smoke.sh" \
    "$STAGING/root/zsh-smoke.sh"

test -x "$STAGING/bin/zsh"
test -r "$TARGET/oh-my-zsh.sh"
test -r "$STAGING/root/.zshrc"
test -r "$STAGING/etc/zsh/zprofile"
