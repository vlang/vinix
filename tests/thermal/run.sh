#!/bin/sh
# Host tests of thermal management's decisions and register decoding.
#
# tests/thermal/thermal is the kernel's module `thermal` without the kernel:
# links to the files of kernel/thermal that import nothing, under names with
# no _amd64 in them so that they compile on whatever machine this runs on,
# beside the tests of them.
#
#   tests/thermal/run.sh
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$here/../../build-support/find-v.sh"
exec "$V" -cc cc test "$here/thermal"
