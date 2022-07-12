#! /bin/sh

set -e

./jinx sysroot
for i in $(find ./sysroot/usr/lib -name '*.so*'); do readelf -d $i 2>/dev/null | grep NEEDED | grep libc.so.6 && echo $i; done
