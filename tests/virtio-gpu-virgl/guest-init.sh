#!/bin/sh
# Test-only PID 1, overlaid by run-aarch64.sh for one VM boot.
set -u

export PATH=/aarch64-linux-musl-native/bin:/usr/local/bin:/bin:/sbin:/usr/bin:/usr/sbin
export HOME=/root
export TERM=linux
export USER=root
export LOGNAME=root
export SHELL=/bin/sh
export LD_LIBRARY_PATH=/usr/lib:/usr/lib/xorg/modules
export LIBGL_DRIVERS_PATH=/usr/lib/xorg/modules/dri:/usr/lib/dri
export XDG_RUNTIME_DIR=/run/user/0
export XDG_CONFIG_HOME=/root/.config
export XDG_CACHE_HOME=/root/.cache
export EGL_PLATFORM=surfaceless

mkdir -p "$XDG_RUNTIME_DIR" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" /tmp
chmod 700 "$XDG_RUNTIME_DIR"

echo "VINIX_VIRGL_VM_BEGIN"
/usr/bin/run-virgl-smoke
status=$?
if [ "$status" -eq 0 ]; then
    echo "VINIX_VIRGL_VM_PASS"
else
    echo "VINIX_VIRGL_VM_FAIL:$status"
fi

# The host harness exits QEMU after observing the result. Keep PID 1 alive so
# a failed serial handoff cannot turn a successful render into an init crash.
while :; do
    sleep 60
done
