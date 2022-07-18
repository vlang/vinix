#! /bin/sh

set -e

./jinx sysroot
find ./sysroot/ -name '*.a'
