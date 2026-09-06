#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
v=${V:-v}
command -v "$v" >/dev/null 2>&1 || { echo 'ERROR: V is required.' >&2; exit 1; }
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
cp "$root/kernel/modules/gpu/dcp/backlight/core/core.v" "$root/tools/apple-backlight/core_test.v" "$work/"
"$v" -gc none -stats "$work/core_test.v"
