#!/bin/bash
# Capture the QEMU guest screen through the monitor socket.
#
#   ./desktop/tools/screenshot.sh out.png
#
# Requires the VM to have been started with a monitor socket, which
# run-aarch64.sh does when VINIX_QEMU_EXTRA names one:
#
#   VINIX_QEMU_EXTRA="-monitor unix:/tmp/vinix-monitor,server,nowait" \
#   VINIX_INITRAMFS=.../initramfs-desktop.tar ./run-aarch64.sh --no-build
set -e

OUT="${1:-/tmp/vinix-screen.png}"
SOCKET="${VINIX_MONITOR_SOCKET:-/tmp/vinix-monitor}"
PPM="$(mktemp -t vinix-screen).ppm"

if [ ! -S "$SOCKET" ]; then
    echo "ERROR: no QEMU monitor socket at $SOCKET"
    exit 1
fi

# screendump always writes PPM; the guest never sees this happen.
printf 'screendump %s\nquit_not_really\n' "$PPM" | nc -U "$SOCKET" >/dev/null 2>&1 || true

# The monitor answers before the file is flushed, so wait for it to appear.
for _ in $(seq 1 40); do
    if [ -s "$PPM" ]; then
        break
    fi
    sleep 0.25
done

if [ ! -s "$PPM" ]; then
    echo "ERROR: screendump produced nothing"
    exit 1
fi

python3 -c "
import sys
from PIL import Image
Image.open(sys.argv[1]).save(sys.argv[2])
" "$PPM" "$OUT"
rm -f "$PPM"
echo "$OUT"
