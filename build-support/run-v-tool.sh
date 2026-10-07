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

# V's default output name is the source's basename, which can also be the
# maintained shell entry point. Compile outside the source tree instead.
tool_temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/vinix-v-tool.XXXXXX")
trap 'rm -rf "$tool_temp_dir"' 0
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
"$V" -o "$tool_temp_dir/tool" "$tool_source"

# Keep the caller's working directory and pass tool arguments without parsing.
set +e
"$tool_temp_dir/tool" "$@"
tool_exit=$?
set -e
exit "$tool_exit"
