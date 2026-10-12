#!/bin/sh
# Restore the host identity after all Alpine package layers are merged.
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec "$script_dir/run-v-tool.sh" "$script_dir/stage-identity.v" "$@"
