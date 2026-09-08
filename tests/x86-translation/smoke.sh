#!/bin/sh
set -eu

echo "VINIX X86_64 TRANSLATION TEST"
output="$(/usr/bin/run-x86-64 /usr/share/vinix/x86-translation-smoke)"
if [ "$output" != "VINIX X86_64 TRANSLATION: PASS" ]; then
    echo "unexpected translated program output: $output" >&2
    exit 1
fi

# This second check covers the x86-64 musl loader and shared libc, not just
# instruction and syscall translation in the static fixture above.
dynamic="$(/usr/bin/run-x86-64 busybox echo DYNAMIC-X86_64-PASS)"
if [ "$dynamic" != "DYNAMIC-X86_64-PASS" ]; then
    echo "unexpected translated dynamic program output: $dynamic" >&2
    exit 1
fi

echo "VINIX X86_64 TRANSLATION TEST: PASS"
