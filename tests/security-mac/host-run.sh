#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
state=$(mktemp -d "${TMPDIR:-/tmp}/vinix-mac-cli.XXXXXX")
trap 'rm -rf "$state"' EXIT HUP INT TERM
python3 "$root/build-support/security-tools/compile-v-core.py" mac "$state/core.c"
${CC:-cc} -std=c11 -O2 -Wall -Wextra -Werror -fsanitize=address,undefined \
    -DVINIX_V_RUNTIME -I"$root/tools/security-mac" -c "$state/core.c" -o "$state/core.o"
${CC:-cc} -std=c11 -O2 -Wall -Wextra -Werror -fsanitize=address,undefined \
    "$root/tests/security-mac/cli_test.c" "$state/core.o" -o "$state/test"
"$state/test"
