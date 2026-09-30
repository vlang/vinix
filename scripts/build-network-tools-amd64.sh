#!/bin/bash
# The amd64 build of build-network-tools-aarch64.sh's layer, staged in build-amd64-network-tools/.
VINIX_ARCH=x86_64 exec "$(dirname "$0")/build-network-tools-aarch64.sh" "$@"
