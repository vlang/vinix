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
# The tool runs on this host, so it must not inherit the flags of a target
# build that calls it: V hands CFLAGS and LDFLAGS to the C compiler, and the
# X11 builder exports Xorg's include directory, whose gc.h then shadows the
# Boehm header V's runtime includes.
host_compile() {
    (unset CFLAGS CPPFLAGS LDFLAGS; "$@")
}
# Use the platform C compiler: TCC cannot resolve Boehm dlopen wrappers on macOS.
# Compiler messages, including cache status on stdout, belong on stderr so
# first-use compilation cannot corrupt the tool's manifest or binary output.
if [ "$(uname -s)" = Darwin ]; then
    # A Rosetta shell can pass its architecture preference to cc even when V
    # itself is ARM. Select the compiler binary's architecture for its children.
    case "$(file -b "$V")" in
        "Mach-O 64-bit executable arm64"*)
            host_compile arch -arm64 "$V" -cc cc -o "$tool_temp_dir/tool" "$tool_source" >&2 ;;
        "Mach-O 64-bit executable x86_64"*)
            host_compile arch -x86_64 "$V" -cc cc -o "$tool_temp_dir/tool" "$tool_source" >&2 ;;
        *) host_compile "$V" -cc cc -o "$tool_temp_dir/tool" "$tool_source" >&2 ;;
    esac
else
    host_compile "$V" -cc cc -o "$tool_temp_dir/tool" "$tool_source" >&2
fi

# Keep the caller's working directory and pass tool arguments without parsing.
set +e
"$tool_temp_dir/tool" "$@"
tool_exit=$?
set -e
exit "$tool_exit"
