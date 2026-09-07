#!/bin/sh
# Bootstrap the exact V1 compiler used for the Wi-Fi build milestone.
# Refuse an existing destination; never reset/clean a user's compiler checkout.
set -eu
DEST=${1:-build-tools/v-m1-wifi}
HOST_CC=${HOST_CC:-clang}
if [ -e "$DEST" ]; then
    echo "Destination already exists: $DEST (set V to its v executable instead)" >&2
    exit 1
fi
mkdir -p "$DEST"
DEST=$(CDPATH= cd -- "$DEST" && pwd)
git -C "$DEST" init
git -C "$DEST" remote add origin https://github.com/vlang/v.git
git -C "$DEST" fetch --depth=1 origin 71437d263bfc57f99e27588781f34bfc91746910
git -C "$DEST" checkout --detach FETCH_HEAD
test "$(git -C "$DEST" rev-parse HEAD)" = 71437d263bfc57f99e27588781f34bfc91746910
git -C "$DEST" init vc
git -C "$DEST/vc" remote add origin https://github.com/vlang/vc.git
git -C "$DEST/vc" fetch --depth=1 origin 99e94ae6099edabce1c6d621eca4c4904e3c2324
git -C "$DEST/vc" checkout --detach FETCH_HEAD
test "$(git -C "$DEST/vc" rev-parse HEAD)" = 99e94ae6099edabce1c6d621eca4c4904e3c2324
VFLAGS='-old-compiler -gc none' make -C "$DEST" local=1 CC="$HOST_CC"
"$DEST/v" version
printf 'Compiler ready: %s/v\n' "$DEST"
