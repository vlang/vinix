#!/bin/sh
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)

# gpu.agx.fw pulls in klock/katomic, which carry one file per architecture.
case $(uname -m) in
    arm64|aarch64)
        exec v -exclude "$repo/kernel/modules/klock/klock_amd64.v" \
            -exclude "$repo/kernel/modules/katomic/katomic_amd64.v" \
            -path "$repo/kernel/modules|@vlib|@vmodules" run \
            "$repo/tests/agx-t8103-opp/test.v"
        ;;
    x86_64|amd64)
        exec v -exclude "$repo/kernel/modules/klock/klock_arm64.v" \
            -exclude "$repo/kernel/modules/katomic/katomic_arm64.v" \
            -path "$repo/kernel/modules|@vlib|@vmodules" run \
            "$repo/tests/agx-t8103-opp/test.v"
        ;;
    *)
        echo "unsupported host architecture for the t8103 OPP test" >&2
        exit 1
        ;;
esac
