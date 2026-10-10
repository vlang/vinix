#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Alexander Medvednikov
#
# Host tests of what makes a hibernation image valid.
#
# tests/hibernate/hibernate is the kernel's module `hibernate` without the
# kernel: a link to the one file of kernel/hibernate that touches neither a
# device nor the machine -- the layout of an image on its device, its
# checksums, when a header is believed, and on what a machine is compared
# with the one an image was taken on -- beside the tests of it.
#
#   tests/hibernate/run.sh
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$here/../../build-support/find-v.sh"
exec "$V" -cc cc test "$here/hibernate"
