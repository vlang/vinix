#!/bin/sh
# Execute the production dynamic scan and final-range freeze with host fixtures.
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
. "$repo/build-support/find-v.sh"
work=$(mktemp -d "${TMPDIR:-/tmp}/vinix-elf-text.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir -p "$work/elf" "$work/resource" "$work/mmap" "$work/memory"
printf 'Module { name: "elf_text_tests" }\n' > "$work/v.mod"
python3 - "$repo" "$work" <<'PY'
from pathlib import Path
import sys
root, work = map(Path, sys.argv[1:])
source = (root / 'kernel/elf/elf.v').read_text()
output = 'module elf\nimport resource\n'
for line in source.splitlines():
    if line.startswith(('const dt_', 'const df_textrel', 'const dynamic_scan_limit')):
        output += line + '\n'
for name in ('DynamicEntry', 'ProgramHdr'):
    start = source.index('struct ' + name + ' {')
    output += source[start:source.index('\n}', start)+2] + '\n'
for name in ('requires_text_relocation', 'dynamic_textrel', 'read_exact'):
    start = source.index('fn ' + name + '(')
    output += source[start:source.index('\n}', start)+2] + '\n'
(work / 'elf/production.v').write_text(output)
source = (root / 'kernel/memory/mmap/immutable.v').read_text()
start = source.index('pub fn mimmutable_executable(')
(work / 'mmap/production.v').write_text('module mmap\nimport memory\n' + source[start:source.index('\n}', start)+2] + '\n')
PY
cat > "$work/resource/resource.v" <<'VEOF'
module resource
pub struct Stat { pub: size i64 }
pub struct Resource { pub: stat Stat data []u8 }
pub fn (mut res Resource) read(_handle voidptr, output voidptr, offset u64, length u64) ?i64 {
    if offset > u64(res.data.len) || length > u64(res.data.len) - offset { return none }
    unsafe { C.memcpy(output, &res.data[int(offset)], length) }
    return i64(length)
}
VEOF
cat > "$work/memory/memory.v" <<'VEOF'
module memory
pub struct Lock {
pub mut:
 held bool
}
pub fn (mut l Lock) acquire() { assert !l.held; l.held = true }
pub fn (mut l Lock) release() { assert l.held; l.held = false }
pub struct Range {
pub mut:
 base u64
 length u64
 prot int
 immutable bool
}
pub struct Pagemap {
pub mut:
 l Lock
 ranges []&Range
}
VEOF
cat > "$work/mmap/fixture.v" <<'VEOF'
module mmap
import memory
const prot_exec = 4
const prot_write = 2
fn range_lower_bound(pagemap &memory.Pagemap, address u64) &memory.Range {
    assert pagemap.l.held
    for range in pagemap.ranges { if range.base >= address { return range } }
    return unsafe { nil }
}
VEOF
cp "$repo/tests/elf-text/dynamic_test.v" "$work/elf/"
cp "$repo/tests/elf-text/immutable_test.v" "$work/mmap/"
"$V" -prod -gc none test "$work/elf"
"$V" -prod -gc none test "$work/mmap"
