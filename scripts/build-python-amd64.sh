#!/bin/bash
# The amd64 build of scripts/build-python-aarch64.sh's layer, staged in build-amd64-python/.
VINIX_ARCH=x86_64 exec "$(dirname "$0")/build-python-aarch64.sh" "$@"
