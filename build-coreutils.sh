#!/bin/sh
# Build vlang/coreutils for the Vinix aarch64 target.
#
# Runs the Vinix-cross-built V under qemu-aarch64 user-mode emulation. That V is
# a static aarch64-linux-musl binary installed with a `v-command` wrapper that
# defaults every build to `-os vinix -arch arm64 -musl -cc tcc`, so running it is
# enough to produce Vinix output - and because it is static and for the guest's
# own architecture, no VM is involved. QEMU_LD_PREFIX and -L point at the musl
# sysroot for the libraries the compiled *output* needs.
set -eu

VINIX=/work/vinix
STAGING="$VINIX/build-aarch64-v/staging"
SYSROOT="$VINIX/build-aarch64-userland/staging"

QEMU_AARCH64=$(command -v qemu-aarch64 || command -v qemu-aarch64-static || true)
if [ -z "$QEMU_AARCH64" ]; then
    echo "ERROR: no qemu-aarch64 on PATH" >&2
    exit 1
fi
for f in "$STAGING/usr/lib/vlang/v" "$STAGING/usr/bin/v" "$SYSROOT/usr/lib/libc.a"; do
    if [ ! -e "$f" ]; then
        echo "ERROR: missing $f - did build-v-aarch64.sh run?" >&2
        exit 1
    fi
done

echo "=== the compiler Vinix produced ==="
file "$STAGING/usr/lib/vlang/v" | cut -c1-110
echo "=== the sysroot it was linked against ==="
file "$SYSROOT/usr/lib/libc.a" | cut -c1-110

# Run the Vinix compiler as an x86_64 process. The wrapper sets the Vinix
# defaults in VFLAGS; QEMU_LD_PREFIX and -L supply the musl userland for
# anything the compiled output links against.
vinix_v() {
    QEMU_LD_PREFIX="$STAGING" \
        "$QEMU_AARCH64" -L "$STAGING" -L "$SYSROOT" "$STAGING/usr/bin/v" "$@"
}

echo "=== does it respond? ==="
vinix_v version

echo "=== compile a program for the Vinix target ==="
printf 'module main\n\nfn main() {\n\tprintln("coreutils on vinix: " + (2 + 2))\n}\n' > /tmp/probe.v
if ! vinix_v -o /tmp/probe_vinix /tmp/probe.v; then
    echo "COMPILE_FAILED"
    exit 1
fi

echo "=== what was produced ==="
ls -la /tmp/probe_vinix
file /tmp/probe_vinix | cut -c1-130

echo
echo "=== now coreutils itself, via its own build script ==="
cd /work/coreutils
# VEXE is what coreutils' build.vsh invokes; it has to be reachable as an
# executable, so it goes through the same qemu wrapper.
cat >/tmp/coreutils-v <<EOF
#!/bin/sh
QEMU_LD_PREFIX="$STAGING" \\
    exec "$QEMU_AARCH64" -L "$STAGING" -L "$SYSROOT" "$STAGING/usr/bin/v" "\$@"
EOF
chmod +x /tmp/coreutils-v
export VEXE=/tmp/coreutils-v

if v build.vsh >/tmp/coreutils-build.log 2>&1; then
    echo "COREUTILS_BUILD_OK"
else
    echo "COREUTILS_BUILD_FAILED - last 40 lines:"
    tail -40 /tmp/coreutils-build.log
    exit 1
fi

echo "=== the first coreutils binaries, and what they are ==="
found=0
for d in /work/coreutils/src/*; do
    [ -d "$d" ] || continue
    for b in "$d"/*; do
        [ -f "$b" ] && [ -x "$b" ] || continue
        file "$b" | grep -q 'ARM aarch64' || continue
        echo "  $(basename "$b"): $(file -b "$b" | cut -c1-70)"
        found=$((found + 1))
        [ "$found" -ge 8 ] && break 2
    done
done
[ "$found" -gt 0 ] || echo "  (no aarch64 executables found under src/)"

echo "BUILD_COREUTILS_DONE"
