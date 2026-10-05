#!/bin/sh
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM

python3 "$repo/tests/agx-fake-g17/run.py"
. "$repo/build-support/find-v.sh"

# Check the V-side native descriptor bridge at its recovered member offsets.
case $(uname -m) in
    arm64|aarch64)
        "$V" -exclude "$repo/kernel/klock/klock_amd64.v" \
            -exclude "$repo/kernel/katomic/katomic_amd64.v" \
            -path "$repo/kernel|@vlib|@vmodules" run \
            "$repo/tests/agx-fake-g17/test_descriptor.v"
        ;;
    x86_64|amd64)
        "$V" -exclude "$repo/kernel/klock/klock_arm64.v" \
            -exclude "$repo/kernel/katomic/katomic_arm64.v" \
            -path "$repo/kernel|@vlib|@vmodules" run \
            "$repo/tests/agx-fake-g17/test_descriptor.v"
        ;;
    *)
        echo "unsupported host architecture for V descriptor test" >&2
        exit 1
        ;;
esac
