#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
exec sh "$root/build-support/run-v-tool.sh" "$root/tests/ext-mount/run-host.v" "$@"
