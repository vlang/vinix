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

echo OPENGOTHIC-START
uname -a
# The desktop reads its keyboard from standard input, and a shell without job
# control gives a background job /dev/null there.
/usr/bin/vinix-desktop --open='Gothic II' </dev/console &

log=
while [ -z "$log" ]; do
    sleep 1
    for candidate in /tmp/vinix-opengothic-*.log /run/vinix-hosted-x11/vinix-opengothic-*.log; do
        [ -f "$candidate" ] && log=$candidate
    done
done
tail -f "$log" &

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
