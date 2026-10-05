#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
set -eu
exec python3 "$(dirname "$0")/run.py"
