#! /bin/sh

set -e

rm -rf sysroot
./jinx sysroot
for i in $(find ./sysroot/ -name '*.so*'); do readelf -d $i 2>/dev/null | grep NEEDED | grep libc.so.6 && echo $i; done
