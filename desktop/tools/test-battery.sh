#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
v=${V:-v}
command -v "$v" >/dev/null 2>&1 || { echo 'ERROR: V is required.' >&2; exit 1; }
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
for name in device_io.v platform.c.v backlight_client.v battery_client.v; do
    cp "$root/desktop/$name" "$work/"
done
cp "$root/desktop/tools/tests/device_io_mock.v" "$root/desktop/tools/tests/battery_client_test.v" "$work/"
"$v" -gc none -enable-globals -stats "$work/battery_client_test.v"
