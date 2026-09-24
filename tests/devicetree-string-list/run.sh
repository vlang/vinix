#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
v=${V:-v}

exec "$v" -gc none -path "$repo/kernel|@vlib|@vmodules" run \
    "$repo/tests/devicetree-string-list/test.v"
