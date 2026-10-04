#!/bin/sh
set -eu
if [ "$#" -ne 2 ]; then
    echo "usage: $0 /path/to/candidate/main.c /path/to/complete/atl/source" >&2
    exit 2
fi
ATL_MAIN_SOURCE=$(realpath "$1")
ATL_SOURCE_ROOT=$(realpath "$2")
ATL_TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ATL_JNI_INCLUDE=${ATL_JNI_INCLUDE:-$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")/include}
ATL_TEST_OUTPUT=$(mktemp -d)
trap 'rm -rf "$ATL_TEST_OUTPUT"' EXIT HUP INT TERM
"${CC:-cc}" -std=gnu2x -O0 -g -ffunction-sections -fdata-sections -Wl,--gc-sections \
    -Wno-deprecated-declarations -I"$ATL_JNI_INCLUDE" -I"$ATL_JNI_INCLUDE/linux" \
    -iquote "$ATL_SOURCE_ROOT/src/main-executable" -I"$ATL_SOURCE_ROOT/src/api-impl-jni" \
    $(pkg-config --cflags gtk4 libportal cairo) \
    -DATL_MAIN_SOURCE=\""$ATL_MAIN_SOURCE"\" \
    "$ATL_TEST_DIR/atl-split-path-test.c" -o "$ATL_TEST_OUTPUT/atl-split-path-test" \
    $(pkg-config --libs gtk4 libportal cairo)
"$ATL_TEST_OUTPUT/atl-split-path-test"
