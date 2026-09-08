#!/bin/sh
set -eu

output=$(minecraft --check)
printf '%s\n' "$output"
case "$output" in
    *Minetest*"C++ client and game data are ready"*) ;;
    *)
        echo "MINECRAFT SMOKE: FAIL (client identity missing)" >&2
        exit 1
        ;;
esac
echo "MINECRAFT SMOKE: PASS"
