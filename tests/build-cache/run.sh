#!/bin/sh
# Native V fixtures for production content and desktop cache producers.
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
"$repo/build-support/run-v-tool.sh" "$repo/build-support/cachekey/tree_test.v"
"$repo/build-support/run-v-tool.sh" "$repo/build-support/cachekey/desktop_test.v"
