#!/bin/sh
set -eu
repo=$(cd "$(dirname "$0")/../.." && pwd)
exec python3 "$repo/tests/network-options/run-host.py" ipv6-multicast host.c
