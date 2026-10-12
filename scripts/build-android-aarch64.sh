#!/bin/sh
# Stage native ARM64 Android Translation Layer and ART for Vinix.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
exec "$SCRIPT_DIR/build-support/android/build" "$@"
