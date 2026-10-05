#!/bin/sh
set -eu
repo=$(cd "$(dirname "$0")/../.." && pwd)
exec python3 "$repo/tests/network-options/run-host.py" network-ipv6 host.c
