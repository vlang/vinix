#!/bin/sh
# Run from any directory. Dependencies: ./kernel/get-deps and a V1 compiler.
# Clean builds avoid stale objects from other architectures or VFLAGS/PROD modes.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
V=${V:-v}
CC=${CC:-clang}
LD_AARCH64=${LD_AARCH64:-ld.lld}
JOBS=${JOBS:-2}
OUT=${OUT:-"$ROOT/tests/m1-wifi/out"}
VFLAGS=${VFLAGS:--old-compiler}
case "$JOBS" in ''|0|*[!0-9]*) echo 'JOBS must be a positive integer' >&2; exit 2;; esac
mkdir -p "$OUT"
OUT=$(CDPATH= cd -- "$OUT" && pwd)
# Resolve V before make changes working directory; allow an absolute path.
V=$(command -v "$V")
case "$V" in
    /*) ;;
    */*) V="$(CDPATH= cd -- "$(dirname -- "$V")" && pwd)/$(basename -- "$V")" ;;
esac
# A failed run must not leave an earlier kernel looking like a new result.
rm -f "$OUT/vinix-aarch64-debug.elf" "$OUT/vinix-aarch64-production.elf" "$OUT/SHA256SUMS"
{
    "$V" version
    "$CC" --version
    "$LD_AARCH64" --version
    printf 'VFLAGS=%s\n' "$VFLAGS"
    git -C "$ROOT" rev-parse HEAD 2>/dev/null || true
} > "$OUT/toolchain.txt"
# Unlike host tests, compile against the kernel's real freestanding headers.
for source in brcm_wifi brcm_m1; do
    "$CC" --target=aarch64-unknown-none -std=gnu99 -O2 -Wall -Wextra -Werror \
        -nostdinc -ffreestanding -fno-builtin -fno-stack-protector \
        -mgeneral-regs-only -march=armv8.4-a -D__AARCH64__ \
        -I "$ROOT/kernel/c" -isystem "$ROOT/kernel/freestnd-c-hdrs" \
        -c "$ROOT/kernel/c/$source.c" -o "$OUT/$source.aarch64.o"
done
for mode in debug production; do
    prod=true
    [ "$mode" != debug ] || prod=false
    make -C "$ROOT/kernel" clean > "$OUT/$mode.log" 2>&1
    if ! make -C "$ROOT/kernel" ARCH=aarch64 CC="$CC" V="$V" \
        VFLAGS="$VFLAGS" PROD="$prod" LD_AARCH64="$LD_AARCH64" \
        -j"$JOBS" all >> "$OUT/$mode.log" 2>&1; then
        tail -n 100 "$OUT/$mode.log" >&2
        exit 1
    fi
    cp "$ROOT/kernel/bin/vinix" "$OUT/vinix-aarch64-$mode.elf"
    python3 "$ROOT/tests/m1-wifi/verify_build.py" \
        "$OUT/vinix-aarch64-$mode.elf" "$ROOT/kernel/obj/blob.c" \
        > "$OUT/$mode-verification.txt"
    cat "$OUT/$mode-verification.txt"
done
python3 "$ROOT/tests/m1-wifi/verify_test.py" "$OUT/vinix-aarch64-production.elf" "$ROOT/kernel/obj/blob.c"
(cd "$OUT" && sha256sum vinix-aarch64-*.elf > SHA256SUMS)
printf 'PASS clean debug and production kernel builds (not a hardware test)\n'
