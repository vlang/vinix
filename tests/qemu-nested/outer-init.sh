#!/bin/sh
set -eu

export PATH=/usr/bin:/bin:/usr/sbin:/sbin
export HOME=/root
export VINIX_QEMU_STATE_DIR=/root
export VINIX_QEMU_GUEST_MEM=512

echo 'VINIX NESTED QEMU: START'
if ! vinix-qemu /root/vinix-inner.img; then
    echo 'VINIX NESTED QEMU: FAIL'
fi

sync
/sbin/poweroff -f 2>/dev/null
exec /bin/sh
