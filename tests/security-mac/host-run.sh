#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
state=$(mktemp -d "${TMPDIR:-/tmp}/vinix-mac-cli.XXXXXX")
trap 'rm -rf "$state"' EXIT HUP INT TERM
${CC:-cc} -std=c11 -O2 -Wall -Wextra -Werror "$root/tests/security-mac/cli_test.c" -o "$state/test"
"$state/test"
