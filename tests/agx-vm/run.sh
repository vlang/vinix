#!/bin/sh
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
exec v -path "$repo/kernel/modules|@vlib|@vmodules" run "$repo/tests/agx-vm/test.v"
