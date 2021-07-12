#!/usr/bin/env bash

set -e

BASE_DIR="$(pwd)"

if [ -z "$1" ]; then
    echo "Usage: $0 <package dir> [<package name>] [--tool]"
    exit 1
fi

set -x

if [ -z "$2" ]; then
    PKG_NAME="$1"
else
    if [ "$2" = "--tool" ]; then
        IS_TOOL="-tool"
        PKG_NAME="$1"
    else
        PKG_NAME="$2"
    fi
fi

if [ "$3" = "--tool" ]; then
    IS_TOOL="-tool"
fi

[ -f 3rdparty/$1.tar.gz ] || [ -f 3rdparty/$1.tar.xz ] || [ -f 3rdparty/$1.tar.bz2 ] || (
    cd build
    xbstrap install$IS_TOOL -u $PKG_NAME || true
)

[ -d 3rdparty/$1-workdir ] || (
    mkdir 3rdparty/$1-workdir
    tar -xf 3rdparty/$1.tar.* -C 3rdparty/$1-workdir --strip-components=1
    cd 3rdparty/$1-workdir
    [ ! -f "$BASE_DIR"/patches/$1/$1.patch ] && (
        mkdir -p "$BASE_DIR"/patches/$1
        touch "$BASE_DIR"/patches/$1/$1.patch
    )
    patch -p3 --no-backup-if-mismatch -r /dev/null < "$BASE_DIR"/patches/$1/$1.patch
)

[ -d 3rdparty/$1-orig ] || (
    mkdir 3rdparty/$1-orig
    tar -xf 3rdparty/$1.tar.* -C 3rdparty/$1-orig --strip-components=1
)

git diff --no-index 3rdparty/$1-orig 3rdparty/$1-workdir > patches/$1/$1.patch || true

[ "$1" = "mlibc" ] && [ -d 3rdparty/mlibc ] && mv 3rdparty/mlibc/subprojects ./mlibc-subprojects
[ "$1" = "limine" ] && [ -d 3rdparty/limine ] && mv 3rdparty/limine/gnu-efi 3rdparty/limine/stivale ./
rm -rf 3rdparty/$1
[ -z "$IS_TOOL" ] && rm -rf build/pkg-builds/$1
[ -z "$IS_TOOL" ] || rm -rf build/tool-builds/$PKG_NAME
[ "$1" = "mlibc" ] && mkdir 3rdparty/mlibc && mv ./mlibc-subprojects 3rdparty/mlibc/subprojects || true
[ "$1" = "limine" ] && mkdir 3rdparty/limine && mv ./gnu-efi ./stivale 3rdparty/limine/ || true
cd build
xbstrap install$IS_TOOL -u $PKG_NAME
