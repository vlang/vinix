#!/bin/sh
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
exec "$repo/build-support/run-v-tool.sh" "$repo/tests/apple_display_hotplug/run.v" "$@"
