#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
exec "$repo/tests/disk-no-sync/run_vm" --build-fixture "$@"
