#!/usr/bin/env bash

set -ex

BASE_DIR="$(pwd)"

if [ -z "$1" ]; then
    echo "Usage: $0 <package dir> [<package name>] [--tool]"
    exit 1
fi

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

[ -f ports/$1.tar.gz ] || [ -f ports/$1.tar.xz ] || (
    cd build
    xbstrap install$IS_TOOL -u $PKG_NAME
)

[ -d ports/$1-workdir ] || (
    mkdir ports/$1-workdir
    tar -xf ports/$1.tar.* -C ports/$1-workdir --strip-components=1
    cd ports/$1-workdir
    [ ! -f "$BASE_DIR"/patches/$1/$1.patch ] && (
        mkdir -p "$BASE_DIR"/patches/$1
        touch "$BASE_DIR"/patches/$1/$1.patch
    )
    patch -p3 < "$BASE_DIR"/patches/$1/$1.patch
)

[ -d ports/$1-orig ] || (
    mkdir ports/$1-orig
    tar -xf ports/$1.tar.* -C ports/$1-orig --strip-components=1
)

git diff --no-index ports/$1-orig ports/$1-workdir > patches/$1/$1.patch || true

[ "$1" = "mlibc" ] && [ -d ports/mlibc ] && mv ports/mlibc/subprojects ./mlibc-subprojects
rm -rf ports/$1
[ "$1" = "mlibc" ] && mkdir ports/mlibc && mv ./mlibc-subprojects ports/mlibc/subprojects || true
cd build
xbstrap install$IS_TOOL -u $PKG_NAME
