#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Use the runner's actual archive with ELF unwind metadata. This validates the
# legacy throwing helpers without implying support for Mach-O unwinding.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUTPUT="${1:-$ROOT/build/ios/fixtures}"
SYSROOT="${VINIX_AARCH64_SYSROOT:-$ROOT/build-aarch64-userland/staging}"
CXX="${VINIX_IOS_CXX_BUILD_DIR:-${VINIX_IOS_BUILD_DIR:-$ROOT/build/ios}/cxx}"
LLVM="${LLVM_BIN:-/opt/homebrew/opt/llvm/bin}"
GCCLIB=$(find "$SYSROOT/usr/lib/gcc/aarch64-alpine-linux-musl" \
    -mindepth 1 -maxdepth 1 -type d | LC_ALL=C sort | tail -n1)
mkdir -p "$OUTPUT"
"$LLVM/clang++" --target=aarch64-linux-musl --sysroot="$SYSROOT" \
    -nostdinc++ -isystem "$CXX/sysroot/usr/include/c++/v1" \
    -include "$ROOT/build-support/ios/cxx-abi.h" -D_LIBCPP_ABI_ALTERNATE_STRING_LAYOUT \
    -DIOS_CXX_NATIVE -std=c++17 -O1 -Wall -Wextra -Werror -ffixed-x18 \
    -c "$ROOT/tests/ios/cxx-extended.cpp" -o "$OUTPUT/cxx-native.o"
"$LLVM/clang++" --target=aarch64-linux-musl -static -nostdlib -fuse-ld=lld -B"$LLVM" \
    "$SYSROOT/usr/lib/crt1.o" "$SYSROOT/usr/lib/crti.o" "$GCCLIB/crtbeginT.o" \
    "$OUTPUT/cxx-native.o" -L"$SYSROOT/usr/lib" -L"$GCCLIB" \
    "$CXX/libcxx-ios.a" "$CXX/sysroot/usr/lib/libc++abi.a" "$CXX/sysroot/usr/lib/libunwind.a" \
    -lgcc_eh -lc -lgcc -lm "$GCCLIB/crtend.o" "$SYSROOT/usr/lib/crtn.o" -o "$OUTPUT/cxx-native"
