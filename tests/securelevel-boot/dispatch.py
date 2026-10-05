#!/usr/bin/env python3
"""Check generated C for allocations in the production append dispatch helper."""
import os
from pathlib import Path
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
compiler = os.environ.get('V', '/Users/alex/code/v/v')
source = (root / 'kernel/resource/cache.v').read_text()
first = source.index('pub struct AppendResult')
last = source.index('// Optional capabilities', first)
model = '''module main
import errno
struct Stat {
 size i64
}
interface Resource {
 stat Stat
mut:
 write(handle voidptr, buf voidptr, location u64, count u64) ?i64
}
struct Backing {
 stat Stat
}
fn (mut backing Backing) write(_handle voidptr, _buf voidptr, _loc u64, count u64) ?i64 {
 return i64(count)
}
fn (mut backing Backing) append_data(_handle voidptr, _buf voidptr, count u64, _limit u64, end &u64) ?i64 {
 unsafe { *end = count }
 return i64(count)
}
fn main() {
 mut backing := Backing{}
 mut res := Resource(backing)
 result := append_write(mut res, unsafe { nil }, unsafe { nil }, 5, 100) or { panic('failed') }
 assert result.written == 5 && result.end == 5
}
'''
with tempfile.TemporaryDirectory(prefix='vinix-append-dispatch-') as temporary:
    work = Path(temporary)
    (work / 'v.mod').write_text("Module { name: 'vinix_append_dispatch' }\n")
    (work / 'errno').mkdir()
    (work / 'errno/errno.v').write_text('module errno\npub const efbig = 27\npub fn set(_value int) {}\n')
    (work / 'main.v').write_text(model + source[first:last])
    subprocess.run([compiler, '-gc', 'none', '-manualfree', '-o', str(work / 'out.c'), str(work / 'main.v')],
                   env=dict(os.environ, VEXE=compiler), check=True)
    generated = (work / 'out.c').read_text()
    definition = re.search(r'^[^\n]+ (?:main__)?append_write\([^\n]+\) \{', generated, re.MULTILINE)
    if not definition:
        raise SystemExit('Generated append dispatch definition is missing')
    first = definition.end() - 1
    last, depth = first + 1, 1
    while depth:
        depth += (generated[last] == '{') - (generated[last] == '}')
        last += 1
    body = generated[first:last]
    if any(marker in body for marker in ('memdup', 'malloc', 'new_array', 'string__substr')):
        raise SystemExit('Generated append dispatch allocates on its repeated path')
print('APPEND DISPATCH STACK PASS')
