#!/bin/sh
# Run Vinix's paravirtual GPU stack against KekVM's host Metal backend.
set -eu

repo=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
exec python3 "$repo/tests/virtio-gpu-virgl/run_vm.py" "$@"
