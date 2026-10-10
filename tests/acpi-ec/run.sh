#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Alexander Medvednikov
#
# Host tests of the embedded controller's protocol.
#
# tests/acpi-ec/acpiec is the kernel's module `acpiec` without the kernel:
# links to the two files of kernel/x86/acpiec that import nothing -- the
# protocol, and the simulated controller a self-test kernel has in place of
# the ports -- beside the tests of them and a clock that moves only when the
# protocol waits. See README.md.
#
#   tests/acpi-ec/run.sh
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$here/../../build-support/find-v.sh"
exec "$V" -cc cc test "$here/acpiec"
