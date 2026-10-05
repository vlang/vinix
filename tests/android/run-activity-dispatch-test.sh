#!/bin/sh
# Native Linux test of the unchanged production dispatcher with checked JNI doubles.
set -eu
if [ "$#" -ne 1 ]; then
    echo "usage: $0 /path/to/atl/src/api-impl-jni/app/android_app_Activity.c" >&2
    exit 2
fi
ATL_DISPATCH_SOURCE=$(realpath "$1")
ATL_TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ATL_JNI_INCLUDE=${ATL_JNI_INCLUDE:-$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")/include}
ATL_CC=${CC:-cc}
actual=$(sha256sum "$ATL_DISPATCH_SOURCE")
case "$actual" in
    ca0ef493f108d13a1b8223781cbfe210616730a4eae410133f248933eb181ed3\ *) ;;
    *) echo "production dispatcher input mismatch" >&2; exit 1 ;;
esac
ATL_TEST_OUTPUT=$(mktemp -d)
trap 'rm -rf "$ATL_TEST_OUTPUT"' EXIT HUP INT TERM
"$ATL_CC" -std=gnu11 -O0 -g -ffunction-sections -fdata-sections -Wl,--gc-sections \
    -Wall -Wextra -Werror -Wno-unused-parameter \
    -I"$ATL_JNI_INCLUDE" -I"$ATL_JNI_INCLUDE/linux" \
    $(pkg-config --cflags gtk4 libportal) \
    -DATL_ACTIVITY_DISPATCHER_FILE=\""$ATL_DISPATCH_SOURCE"\" \
    "$ATL_TEST_DIR/atl-activity-dispatch-test.c" -o "$ATL_TEST_OUTPUT/atl-activity-dispatch-test" \
    $(pkg-config --libs gtk4 libportal)
"$ATL_TEST_OUTPUT/atl-activity-dispatch-test"
