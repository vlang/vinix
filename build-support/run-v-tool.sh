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
# Use the platform C compiler: TCC cannot resolve Boehm dlopen wrappers on macOS.
if [ "$(uname -s)" = Darwin ]; then
    # A Rosetta shell can pass its architecture preference to cc even when V
    # itself is ARM. Select the compiler binary's architecture for its children.
    case "$(file -b "$V")" in
        "Mach-O 64-bit executable arm64"*)
            arch -arm64 "$V" -cc cc -o "$tool_temp_dir/tool" "$tool_source" ;;
        "Mach-O 64-bit executable x86_64"*)
            arch -x86_64 "$V" -cc cc -o "$tool_temp_dir/tool" "$tool_source" ;;
        *) "$V" -cc cc -o "$tool_temp_dir/tool" "$tool_source" ;;
    esac
else
    "$V" -cc cc -o "$tool_temp_dir/tool" "$tool_source"
fi

# Keep the caller's working directory and pass tool arguments without parsing.
set +e
"$tool_temp_dir/tool" "$@"
tool_exit=$?
set -e
exit "$tool_exit"
