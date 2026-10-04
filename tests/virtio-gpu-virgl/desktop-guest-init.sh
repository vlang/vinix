#!/bin/sh
# Test-only PID 1 for exercising the complete GPU desktop startup in KekVM.
set -u

export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
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
export VINIX_SYSTEM_SESSION=1

mkdir -p "$XDG_RUNTIME_DIR" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" /tmp /root/vm
chmod 700 "$XDG_RUNTIME_DIR" /root/vm

# A disposable VM should test the compositor rather than stop at the interactive
# first-boot form.  This has the exact on-disk shape produced by registration;
# no password verification takes place during an already registered startup.
printf '%s\n' \
    'version=1' \
    'name=564d' \
    'kdf=scrypt' \
    'n=16384' \
    'r=8' \
    'p=1' \
    'salt=00000000000000000000000000000000' \
    'hash=0000000000000000000000000000000000000000000000000000000000000000' \
    > /root/.vinix-user
chmod 600 /root/.vinix-user
rm -f /run/vinix-desktop-ready

echo "VINIX_GPU_DESKTOP_VM_BEGIN"
/usr/bin/vinix-desktop-gpu &
desktop_pid=$!

i=0
while [ "$i" -lt 120 ]; do
    if [ -f /run/vinix-desktop-ready ]; then
        echo "VINIX_GPU_DESKTOP_VM_PASS"
        result=pass
        break
    fi
    if ! kill -0 "$desktop_pid" 2>/dev/null; then
        wait "$desktop_pid"
        status=$?
        echo "VINIX_GPU_DESKTOP_VM_FAIL:$status"
        result=fail
        break
    fi
    sleep 1
    i=$((i + 1))
done

if [ "${result:-timeout}" = timeout ]; then
    echo "VINIX_GPU_DESKTOP_VM_FAIL:124"
fi

# The host harness exits QEMU after observing the result. Keep PID 1 alive so
# neither success nor a compositor failure is obscured by an init exit panic.
while :; do
    sleep 60
done
