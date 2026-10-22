#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
set -eu
support=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
exec sh "$support/run-v-tool.sh" "$support/native-compat-tools/main.v" x11-build "$@"
