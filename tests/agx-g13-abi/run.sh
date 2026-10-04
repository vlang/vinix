#!/bin/sh
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)

# gpu.agx.fw pulls in klock/katomic, which carry one file per architecture.
case $(uname -m) in
    arm64|aarch64)
        exec v -exclude "$repo/kernel/klock/klock_amd64.v" \
            -exclude "$repo/kernel/katomic/katomic_amd64.v" \
            -path "$repo/kernel|@vlib|@vmodules" run \
            "$repo/tests/agx-g13-abi/test.v"
        ;;
    x86_64|amd64)
        exec v -exclude "$repo/kernel/klock/klock_arm64.v" \
            -exclude "$repo/kernel/katomic/katomic_arm64.v" \
            -path "$repo/kernel|@vlib|@vmodules" run \
            "$repo/tests/agx-g13-abi/test.v"
        ;;
    *)
        echo "unsupported host architecture for the G13 ABI test" >&2
        exit 1
        ;;
esac
