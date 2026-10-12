#!/bin/sh
# Cross-build the native Vulkan client; --demo adds the original public demo.
set -eu
exec "$(dirname "$0")/../build-support/opengothic/build" "$@"
