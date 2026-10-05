#!/bin/sh
# Compile and boot the security MAC regression against an already-built kernel.
set -eu
repo=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
arch=${1:-aarch64}
case "$arch" in
  aarch64) ;;
  amd64|x86_64) arch=x86_64 ;;
  *) echo "usage: $0 [aarch64|x86_64]" >&2; exit 2 ;;
esac
kernel=${VINIX_KERNEL_DIR:-"$repo/kernel"}
if [ -n "${VINIX_MAC_STATE_DIR:-}" ]; then
  exec python3 "$repo/tests/kernel-gaps/run.py" \
    --source "$repo/tests/security-mac/test.c" --arch "$arch" \
    --kernel-dir "$kernel" --state-dir "$VINIX_MAC_STATE_DIR" --no-network \
    --expect 'SECURITY MAC PASS' --fail 'SECURITY MAC FAIL' \
    --timeout "${VINIX_QEMU_TIMEOUT:-300}"
fi
exec python3 "$repo/tests/kernel-gaps/run.py" \
  --source "$repo/tests/security-mac/test.c" --arch "$arch" \
  --kernel-dir "$kernel" --no-network \
  --expect 'SECURITY MAC PASS' --fail 'SECURITY MAC FAIL' \
  --timeout "${VINIX_QEMU_TIMEOUT:-300}"
