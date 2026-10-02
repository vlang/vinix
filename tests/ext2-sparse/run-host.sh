#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
v=${V:-v}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir -p "$work/modules/ext2" "$work/modules/errno" "$work/modules/memory" "$work/modules/stat" "$work/modules/lib"
cp "$root/kernel/fs/ext2/blocks.v" "$root/tests/ext2-sparse/blocks_test.v" "$work/modules/ext2/"
python3 - "$root" "$work/modules/ext2/io.v" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
source = (root / 'kernel/fs/ext2/ext2.v').read_text()
start = source.index('fn (mut inode EXT2Inode) read(mut filesystem')
end = source.index('fn (mut inode EXT2Inode) free_entry(', start)
result = 'module ext2\nimport stat\nimport memory\nimport errno\nimport lib\n' + source[start:end]
source = (root / 'kernel/fs/ext2/pagecache.v').read_text()
start = source.index('fn (mut filesystem EXT2Filesystem) enable_large_files(')
end = source.index('\n}\n', start) + 3
Path(sys.argv[2]).write_text(result + source[start:end])
PY
cat > "$work/v.mod" <<'EOF'
Module { name: 'ext2_sparse_host_tests' }
EOF
cat > "$work/modules/errno/errno.v" <<'EOF'
module errno
pub const enomem = 12
pub const efbig = 27
pub fn set(_value int) {}
EOF
cat > "$work/modules/memory/memory.v" <<'EOF'
module memory
pub fn calloc(count u64, size u64) voidptr { return unsafe { C.calloc(count, size) } }
pub fn free(value voidptr) { unsafe { C.free(value) } }
EOF
cat > "$work/modules/stat/stat.v" <<'EOF'
module stat
pub fn isreg(mode u32) bool { return mode & 0xf000 == 0x8000 }
pub fn islnk(mode u32) bool { return mode & 0xf000 == 0xa000 }
EOF
cat > "$work/modules/lib/lib.v" <<'EOF'
module lib
pub fn div_roundup(value u64, divisor u64) u64 { return value / divisor + u64(value % divisor != 0) }
EOF
if [ "${VINIX_HOST_SANITIZE:-0}" = 1 ]; then
    VMODULES="$work/modules" "$v" -cc clang -cflags '-fsanitize=address,undefined' -ldflags '-fsanitize=address,undefined' -enable-globals -gc none test "$work/modules/ext2"
else
    VMODULES="$work/modules" "$v" -enable-globals -gc none test "$work/modules/ext2"
fi
