#!/bin/sh
# Stage Android Translation Layer for Vinix/aarch64 using its x86 translator.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec python3 "$SCRIPT_DIR/build-support/android/build.py" "$@"
