#!/bin/bash
# Build the amd64 X11 layer into build-amd64-x11: the arm64 script, run for x86_64.
set -euo pipefail

VINIX_ARCH=x86_64 exec "$(cd "$(dirname "$0")" && pwd)/build-x11-aarch64.sh" "$@"
