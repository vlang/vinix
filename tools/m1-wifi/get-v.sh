#!/bin/sh
# Bootstrap a pinned, known-working V compiler for the Wi-Fi build.
# Refuse an existing destination; never reset/clean a user's compiler checkout.
#
# Previously pinned to 71437d263bfc57f99e27588781f34bfc91746910 (V1-era) via
# a manual two-repo (v + vc) bootstrap with `-old-compiler`. That pin predates
# vinix's kernel Makefile requiring -target-libc-headers (added once V's own
# V1 fallback backend was retired), so it fails outright with "Unknown
# argument `-target-libc-headers`" on every build from that point on -- not a
# transient CI flake, a permanent mismatch between this pin and what the
# kernel build now unconditionally passes. This repoints to a verified-
# working commit and drops the manual vc bootstrap: V's own `make` already
# performs the equivalent v1/v2 bootstrap internally (confirmed against this
# exact commit), so replicating it by hand here was solving an already-solved
# problem and only needed updating in one more place when it broke.
set -eu
DEST=${1:-build-tools/v-m1-wifi}
HOST_CC=${HOST_CC:-clang}
PIN=7490a8ff04d91dc60eec12b0d9923b4d1bc87960
if [ -e "$DEST" ]; then
    echo "Destination already exists: $DEST (set V to its v executable instead)" >&2
    exit 1
fi
mkdir -p "$DEST"
DEST=$(CDPATH= cd -- "$DEST" && pwd)
git -C "$DEST" init
git -C "$DEST" remote add origin https://github.com/vlang/v.git
git -C "$DEST" fetch --depth=1 origin "$PIN"
git -C "$DEST" checkout --detach FETCH_HEAD
test "$(git -C "$DEST" rev-parse HEAD)" = "$PIN"
CC="$HOST_CC" make -C "$DEST"
"$DEST/v" version
printf 'Compiler ready: %s/v\n' "$DEST"
