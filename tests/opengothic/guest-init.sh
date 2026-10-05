#!/bin/sh
# Test-only PID 1: the desktop with Gothic II open, and the game's log on the
# serial console where run.py reads it.
export PATH=/bin:/sbin:/usr/bin:/usr/sbin
export HOME=/root
export USER=root
export LOGNAME=root
export SHELL=/bin/sh
export TERM=linux
export LD_LIBRARY_PATH=/usr/lib:/usr/lib/xorg/modules

mkdir -p /tmp/.X11-unix /root/vm /run/user/0
chmod 1777 /tmp /tmp/.X11-unix
# A registered user, so the desktop starts without its first-run questions.
printf '%s\n' 'version=1' 'name=564d' 'kdf=scrypt' 'n=16384' 'r=8' 'p=1' \
    'salt=00000000000000000000000000000000' \
    'hash=0000000000000000000000000000000000000000000000000000000000000000' \
    > /root/.vinix-user
chmod 600 /root/.vinix-user

if [ -x /opt/venus/bin/venus-smoke ]; then
    /opt/venus/bin/venus-abi || echo VENUS-ABI-FAIL
    LD_LIBRARY_PATH=/opt/venus/lib:/opt/opengothic/lib:/usr/lib \
    VK_ICD_FILENAMES=/opt/venus/share/vulkan/icd.d/virtio_icd.aarch64.json \
    VN_DEBUG=init /opt/venus/bin/venus-smoke || echo VENUS-SMOKE-FAIL
fi
echo OPENGOTHIC-START
uname -a
# The desktop reads its keyboard from standard input, and a shell without job
# control gives a background job /dev/null there.
/usr/bin/vinix-desktop --open='Gothic II' --stats </dev/console &

log=
while [ -z "$log" ]; do
    sleep 1
    for candidate in /tmp/vinix-opengothic-*.log /run/vinix-hosted-x11/vinix-opengothic-*.log; do
        [ -f "$candidate" ] && log=$candidate
    done
done
tail -f "$log" &
if [ -x /opt/venus/bin/venus-smoke ]; then
    while [ ! -f /tmp/gothic-fps.csv ]; do sleep 1; done
    tail -f /tmp/gothic-fps.csv &
fi

# The engine names its main thread, so look for the path it was started by.
seen=0
while :; do
    sleep 5
    if ps | grep -q '[G]othic2Notr'; then
        seen=1
        echo OPENGOTHIC-ALIVE
    elif [ "$seen" = 1 ]; then
        echo OPENGOTHIC-GONE
    fi
done
