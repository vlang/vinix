#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir -p "$work/journal" "$work/modules/memory" "$work/modules/errno"
cp "$root/kernel/fs/journal/journal.v" "$root/tests/fs-journal/journal_test.v" "$work/journal/"
cat > "$work/v.mod" <<'EOF'
Module { name: 'journal_host_tests' }
EOF
cat > "$work/modules/memory/memory.v" <<'EOF'
@[has_globals]
module memory
__global (pub live int pub left int = -1)
pub fn malloc_packed_fallible(bytes u64) voidptr {
    if left == 0 { return unsafe { nil } }
    if left > 0 { left-- }
    p := unsafe { C.malloc(bytes) }
    if p != unsafe { nil } { live++ }
    return p
}
pub fn free(p voidptr) { if p != unsafe { nil } { live--; unsafe { C.free(p) } } }
EOF
cat > "$work/modules/errno/errno.v" <<'EOF'
@[has_globals]
module errno
__global (last u64)
pub const eio = 5
pub const e2big = 7
pub const enomem = 12
pub const einval = 22
pub const enospc = 28
pub const erofs = 30
pub fn set(code u64) { last = code }
pub fn get() u64 { return last }
EOF
if [ "${VINIX_HOST_SANITIZE:-0}" = 1 ]; then
    VMODULES="$work/modules" "${V:-v}" -cc clang -cflags '-fsanitize=address,undefined' -ldflags '-fsanitize=address,undefined' -enable-globals test "$work/journal"
else
    VMODULES="$work/modules" "${V:-v}" -enable-globals test "$work/journal"
fi
