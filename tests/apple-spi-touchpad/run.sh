#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
set -eu
exec python3 "$(dirname "$0")/../apple-spi-keyboard/run.py" "$@"
