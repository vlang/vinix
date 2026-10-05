#!/bin/sh
# Execute the same Objective-C model using this Mac's real Foundation runtime.
set -eu
repo=$(cd "$(dirname "$0")/../.." && pwd)
output="$repo/build/ios/objc-tests"
mkdir -p "$output"
for mode in sdk minimal; do
    if [ "$mode" = minimal ]; then
        define=-DVINIX_MINIMAL_FOUNDATION
    else
        define=-DVINIX_HOST_FOUNDATION
    fi
    "${HOST_CLANG:-clang}" "$define" -fobjc-arc -O1 -g -fsanitize=address,undefined \
        -Wall -Wextra -Werror -framework Foundation \
        "$repo/examples/ios-calculator/Calculator.m" "$repo/tests/ios/objc-calculator-test.m" \
        -o "$output/calculator-test-$mode"
    "$output/calculator-test-$mode"
done
