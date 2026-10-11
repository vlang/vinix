#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
exec sh "$root/build-support/run-v-tool.sh" "$root/build-support/native-compat-tools/main.v" mac-host "$@"
