#!/bin/sh
# Exercise the genuine ELF dynamic scan and final-range freeze through V.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
exec sh "$root/build-support/run-v-tool.sh" "$root/build-support/native-compat-tools/main.v" elf-text-host "$@"
