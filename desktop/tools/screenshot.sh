#!/bin/sh
# Capture the QEMU guest screen through its QMP socket.
# SPDX-License-Identifier: GPL-2.0-or-later
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
exec sh "$repo/build-support/run-v-tool.sh" "$repo/desktop/tools/screenshot.v" "$@"
