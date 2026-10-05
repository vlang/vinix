#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
arch=${1:-aarch64}
kernel=${2:-"$root/kernel"}
case "$arch" in
    aarch64) v_arch=arm64; native_cc=${CC:-clang} ;;
    x86_64) v_arch=amd64; native_cc=${CC_AMD64:-x86_64-linux-musl-gcc} ;;
    *) echo 'usage: run-native.sh {aarch64|x86_64} [kernel-directory]' >&2; exit 1 ;;
esac
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir "$work/src"
cp "$root/desktop/app_sandbox.c.v" "$work/src/"
cp "$root/tests/application-sandbox/native_guest.v" "$work/src/main.v"
"${V:-v}" -new-compiler -os linux -arch "$v_arch" -gc none -manualfree \
    -o "$work/native.c" "$work/src"
# The production V backend emits runtime C with warnings unrelated to this
# test. Match the desktop's -w C compilation; handwritten launcher tests keep
# the harness's -Wall -Wextra -Werror checks.
cat > "$work/cc" <<'EOF'
#!/bin/sh
exec "$VINIX_NATIVE_TEST_CC" "$@" -w
EOF
chmod +x "$work/cc"
VINIX_NATIVE_TEST_CC="$native_cc" CC="$work/cc" CC_AMD64="$work/cc" \
python3 "$root/tests/kernel-gaps/run.py" --source "$work/native.c" \
    --arch "$arch" --kernel-dir "$kernel" \
    --expect 'APPLICATION NATIVE SANDBOX GUEST PASS' \
    --fail 'APPLICATION NATIVE SANDBOX FAIL'
