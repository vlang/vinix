#!/bin/bash
# Cross-build dhewm3 and download the original Doom 3 demo data.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
exec python3 "$SCRIPT_DIR/build-support/dhewm3/build.py" "$@"
