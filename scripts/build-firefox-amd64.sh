#!/bin/bash
# The amd64 build of build-firefox-aarch64.sh's layer, staged in build-amd64-firefox/.
VINIX_ARCH=x86_64 exec "$(dirname "$0")/build-firefox-aarch64.sh" "$@"
