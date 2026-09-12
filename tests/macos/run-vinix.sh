#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Cross-build the V runtime as PID 1, boot it on Vinix, and require the real
# Objective-C action path to print its PASS marker.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
v=${V:-v}
case "$v" in
    */*) ;;
    *) v=$(command -v "$v" 2>/dev/null || printf '%s' "$v") ;;
esac
llvm_bin=${LLVM_BIN:-/opt/homebrew/opt/llvm/bin}
sysroot=${VINIX_AARCH64_SYSROOT:-${VINIX_MUSL_SYSROOT:-"$root/build-aarch64-userland/staging"}}
gcclib=$(find "$sysroot/usr/lib/gcc/aarch64-alpine-linux-musl" \
    -mindepth 1 -maxdepth 1 -type d 2>/dev/null | LC_ALL=C sort | tail -n1)

for path in "$v" "$llvm_bin/clang" "$sysroot/usr/lib/libc.a" "$gcclib/libgcc.a" "$root/kernel/bin/vinix"; do
    [ -e "$path" ] || {
        echo "ERROR: missing Vinix test prerequisite: $path" >&2
        exit 1
    }
done

work=$(mktemp -d)
runner_pid=
cleanup() {
    if [ -n "$runner_pid" ] && kill -0 "$runner_pid" 2>/dev/null; then
        # run-aarch64.sh is waiting on QEMU, so stop that child first and let
        # the runner perform its own package-server and temporary-file cleanup.
        qemu_pids=$(pgrep -P "$runner_pid" -f qemu-system-aarch64 2>/dev/null || true)
        if [ -n "$qemu_pids" ]; then
            kill $qemu_pids 2>/dev/null || true
        fi
        kill "$runner_pid" 2>/dev/null || true
        wait "$runner_pid" 2>/dev/null || true
    fi
    rm -rf "$work"
}
trap cleanup EXIT HUP INT TERM

mkdir "$work/runtime" "$work/rootfs"
ln -s "$root/desktop/cocoa.v" "$work/runtime/cocoa.v"
ln -s "$root/tests/macos/runtime_test.v" "$work/runtime/main.v"
printf "Module { name: 'cocoa_vinix_test' }\n" > "$work/runtime/v.mod"

"$v" -os linux -gc none -manualfree -enable-globals -prod -d ui2_headless \
    -path "@vlib|@vmodules|$root|$root/third_party" \
    -o "$work/runtime.c" "$work/runtime"
"$llvm_bin/clang" --target=aarch64-linux-musl -static -nostdinc -nostdlib \
    -isystem "$root/build-support/aarch64-cc-shim" \
    -isystem "$gcclib/include" -isystem "$sysroot/usr/include" \
    -O2 -fno-stack-protector -w \
    "$sysroot/usr/lib/crt1.o" "$sysroot/usr/lib/crti.o" "$gcclib/crtbeginT.o" \
    "$work/runtime.c" -L"$sysroot/usr/lib" -L"$gcclib" -lc -lgcc -lm \
    "$gcclib/crtend.o" "$sysroot/usr/lib/crtn.o" \
    -fuse-ld=lld -B"$llvm_bin" -o "$work/runtime-aarch64"

"$root/compat/macos/apps/Calculator/build.sh" "$work/Calculator.app" >/dev/null
mkdir -p "$work/rootfs/sbin" "$work/rootfs/Applications"
install -m755 "$work/runtime-aarch64" "$work/rootfs/sbin/init"
cp -R "$work/Calculator.app" "$work/rootfs/Applications/"
COPYFILE_DISABLE=1 tar --format=ustar -cf "$work/initramfs.tar" -C "$work/rootfs" .

VINIX_INITRAMFS="$work/initramfs.tar" \
VINIX_BOOT_DISK="$work/boot.img" \
VINIX_EFIVARS="$work/vars.fd" \
    "$root/run-aarch64.sh" --no-build --serial --no-persist --disk=256 >"$work/vinix.log" 2>&1 &
runner_pid=$!

elapsed=0
while [ "$elapsed" -lt 90 ]; do
    if grep -q 'PASS AArch64 Mach-O Objective-C Cocoa calculator' "$work/vinix.log"; then
        if ! grep -q 'smp: 4 CPUs online' "$work/vinix.log"; then
            cat "$work/vinix.log" >&2
            echo 'FAIL: Cocoa calculator ran without all four QEMU CPUs online' >&2
            exit 1
        fi
        cat "$work/vinix.log"
        echo 'PASS Cocoa calculator executed on Vinix with four CPUs online'
        exit 0
    fi
    if ! kill -0 "$runner_pid" 2>/dev/null; then
        break
    fi
    sleep 1
    elapsed=$((elapsed + 1))
done

cat "$work/vinix.log" >&2
echo 'FAIL: Cocoa calculator did not execute on Vinix within 90 seconds' >&2
exit 1
