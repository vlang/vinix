#!/bin/sh
# Cross-build the native Vulkan client; --demo adds the original public demo.
set -eu
exec python3 "$(dirname "$0")/build-support/opengothic/build.py" "$@"
