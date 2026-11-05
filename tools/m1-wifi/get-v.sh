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
#
# V's own bootstrap compiler ("vc") is pinned too, not left to `make`'s
# default `latest_vc` target: without `local=1`, a clean destination runs
# `fresh_vc`, which clones vlang/vc with no revision pinned at all, so the
# V pin above could silently get built by a different, later vc snapshot
# on a later clean run -- and a later vc can become incompatible with
# these historical V sources with nothing here to explain why the build
# suddenly stopped working. Clone vc ourselves at a revision already
# confirmed to build this exact V pin successfully, and pass local=1 so
# V's own make leaves it alone instead of pulling a fresh one.
set -eu
DEST=${1:-build-tools/v-m1-wifi}
HOST_CC=${HOST_CC:-clang}
PIN=1f4d705322714d6ab35a712db9d1b93db9fbcc03
VC_PIN=0a3c639cf475a0c5e19f3b5cdf6683ed4c9a3189
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
git init "$DEST/vc"
git -C "$DEST/vc" remote add origin https://github.com/vlang/vc.git
git -C "$DEST/vc" fetch --depth=1 origin "$VC_PIN"
git -C "$DEST/vc" checkout --detach FETCH_HEAD
test "$(git -C "$DEST/vc" rev-parse HEAD)" = "$VC_PIN"
# Supply Boehm before make: V's post-build tools and the Vinix host generator
# link it, and a failed detect_tcc aborts make even when the compiler itself
# built. Build the one object from V's own bundled libgc sources.
mkdir -p "$DEST/thirdparty/tcc/lib"
"$HOST_CC" -O2 -D_GNU_SOURCE -DUSE_MMAP=1 -DUSE_MUNMAP=1 \
    -DGC_THREADS=1 -DTHREAD_LOCAL_ALLOC=1 -DGC_BUILTIN_ATOMIC=1 \
    -DALL_INTERIOR_POINTERS=1 -I "$DEST/thirdparty/libgc/include" \
    -c "$DEST/thirdparty/libgc/gc.c" -o "$DEST/thirdparty/tcc/lib/gc.o"
llvm-ar rcs "$DEST/thirdparty/tcc/lib/libgc.a" "$DEST/thirdparty/tcc/lib/gc.o" \
    || ar rcs "$DEST/thirdparty/tcc/lib/libgc.a" "$DEST/thirdparty/tcc/lib/gc.o"

# env -u: an inherited VEXE/VFLAGS can redirect make's output to a different
# compiler tree. _GNU_SOURCE supplies the host's `environ` declaration.
env -u VEXE -u VFLAGS SOURCE_DATE_EPOCH=0 V_MACOS_V3_NO_FALLBACK=1 \
    CC="$HOST_CC" make -C "$DEST" local=1 VEXE="$DEST/v" \
    VFLAGS="-w -cc $HOST_CC -cflags -D_GNU_SOURCE -no-parallel"
"$DEST/v" version
printf 'Compiler ready: %s/v\n' "$DEST"
