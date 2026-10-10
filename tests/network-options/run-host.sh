#!/bin/sh
set -eu
repo=$(cd "$(dirname "$0")/../.." && pwd)
exec "$repo/tests/network-options/run-host" network-options test.c
