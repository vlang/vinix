#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
for suite in test_runner test_prepare test_recovery; do
    sh "$repo/build-support/run-v-tool.sh" "$repo/tests/desktop-bootstrap/$suite.v" "$@"
done
