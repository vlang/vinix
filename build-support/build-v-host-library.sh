#!/bin/sh
# Build an optional V library against the calling CPython's public object API.
set -eu

if [ "$#" -lt 2 ]; then
    printf 'Usage: %s SOURCE.v OUTPUT [V compiler flags...]\n' "$0" >&2
    exit 2
fi
host_library_source=$1
host_library_output=$2
shift 2
support_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$support_dir/find-v.sh"
host_python=${VINIX_HOST_PYTHON:-python3}
host_python_headers=$("$support_dir/source-tools/run" cpython-headers "$host_python")
host_library_cflags="-I$host_python_headers"
if [ "$(uname -s)" = Darwin ]; then
    host_library_cflags="$host_library_cflags -undefined dynamic_lookup"
    case "$(file -b "$V")" in
        "Mach-O 64-bit executable arm64"*)
            exec arch -arm64 "$V" -shared -enable-globals -d cpython_host -cc cc \
                -cflags "$host_library_cflags" -o "$host_library_output" "$@" "$host_library_source" ;;
        "Mach-O 64-bit executable x86_64"*)
            exec arch -x86_64 "$V" -shared -enable-globals -d cpython_host -cc cc \
                -cflags "$host_library_cflags" -o "$host_library_output" "$@" "$host_library_source" ;;
    esac
fi
exec "$V" -shared -enable-globals -d cpython_host -cc cc \
    -cflags "$host_library_cflags" -o "$host_library_output" "$@" "$host_library_source"
