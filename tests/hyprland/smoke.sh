#!/bin/busybox sh
set -eu

test -x /usr/bin/Hyprland
test -x /usr/bin/start-hyprland-vinix
test -x /usr/bin/hyprland-demo
test -r /root/.config/hypr/hyprland.conf
test -r /usr/share/X11/xkb/rules/evdev
test -e /dev/fb0
test -e /dev/dri/renderD128 || test -e /dev/dri/card0

/usr/bin/Hyprland --i-am-really-stupid --verify-config \
    --config /root/.config/hypr/hyprland.conf
echo "Hyprland Vinix runtime: PASS"
