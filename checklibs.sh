#! /bin/sh

set -e

for i in $(find ./build/system-root/usr/lib -name '*.so*'); do readelf -d $i 2>/dev/null | grep NEEDED | grep libc.so.6 && echo $i; done
