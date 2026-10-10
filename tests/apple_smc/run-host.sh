#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026 Alexander Medvednikov
#
# Host tests of the SMC client: the protocol core, what it finds on an SMC and
# what it makes of the values, against the simulated SMC.
#
# tests/apple_smc/core is the kernel's module `core` (kernel/apple/smc/core)
# without the kernel: links to its files, none of which imports anything,
# beside the tests of them and a clock that moves only when it is read. See
# README.md.
#
#   tests/apple_smc/run-host.sh
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$here/../../build-support/find-v.sh"
exec "$V" -cc cc test "$here/core"
