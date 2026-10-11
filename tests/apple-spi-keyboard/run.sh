#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
exec "$root/build-support/run-v-tool.sh" "$root/tests/apple-spi-keyboard/run.v" "$@"
