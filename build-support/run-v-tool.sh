#!/bin/sh
# Run a maintained host tool with the same compiler selection as kernel builds.
set -eu

if [ "$#" -eq 0 ]; then
    printf 'Usage: %s TOOL.v [arguments...]\n' "$0" >&2
    exit 2
fi

tool_source=$1
shift
support_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$support_dir/find-v.sh"

# Keep the caller's working directory and pass tool arguments without parsing.
exec "$V" run "$tool_source" "$@"
