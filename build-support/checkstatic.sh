#! /bin/sh

set -e

rm -rf sysroot
./jinx sysroot
find ./sysroot/ -name '*.a'
