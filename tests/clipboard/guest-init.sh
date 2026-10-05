#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
export HOME=/root TERM=linux USER=root LOGNAME=root SHELL=/bin/zsh
export LD_LIBRARY_PATH=/usr/lib:/usr/lib/xorg/modules
mkdir -p /tmp /run/user/0 /dev/shm /root/.config /root/.cache /var/log
chmod 1777 /tmp /dev/shm
export XDG_RUNTIME_DIR=/run/user/0
printf 'version=1\nname=436c6970626f617264\nkdf=scrypt\nn=16384\nr=8\np=1\nsalt=00112233445566778899aabbccddeeff\nhash=00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff\n' >/root/.vinix-user
chmod 600 /root/.vinix-user
rm -f /root/.vinix-first-run-apps /root/notes.txt /tmp/terminal-paste /tmp/x11-paste

fail() { echo "CLIPBOARD FAIL: $*"; while :; do sleep 10; done; }
stop_desktop() { kill -TERM "$desktop_pid"; wait "$desktop_pid"; }
launch() {
    rm -f /run/vinix-desktop-ready
    /usr/bin/vinix-desktop --open="$1" </dev/console &
    desktop_pid=$!
    for attempt in $(seq 1 60); do
        [ ! -s /run/vinix-desktop-ready ] || break
        sleep 1
    done
    [ -s /run/vinix-desktop-ready ] || fail "desktop did not open $1"
    sleep 2
    echo "CLIPBOARD READY: $2"
}
check_file() {
    for attempt in $(seq 1 60); do
        if [ -f "$1" ] && cmp -s "$1" /opt/clipboard/expected; then
            echo "CLIPBOARD PASS: $2"
            return
        fi
        sleep 1
    done
    fail "$2 did not receive complete text"
}

# The controller supplies fixture text through the same loopback handler.
cp /opt/clipboard/url /etc/vinix/host-clipboard-url
url=$(cat /opt/clipboard/url)
for attempt in $(seq 1 30); do
    /usr/bin/curl --noproxy '*' --fail --silent --max-time 3 "${url%clipboard}health" && break
    sleep 1
done
launch 'Text Editor' editor
check_file /root/notes.txt editor
stop_desktop
launch Terminal terminal
check_file /tmp/terminal-paste terminal
stop_desktop
launch Firefox x11
check_file /tmp/x11-paste x11
stop_desktop
echo 'CLIPBOARD TEST: PASS'
while :; do sleep 10; done
