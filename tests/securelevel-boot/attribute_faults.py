#!/usr/bin/env python3
"""Exercise the production ext2 attribute publisher with failing inode I/O."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
compiler = os.environ.get('V', '/Users/alex/code/v/v')
source = (root/'kernel/fs/ext2/ext2.v').read_text()
first = source.index('fn (mut this EXT2Resource) set_attribute_bits(')
last = source.index('\nfn ', first + 4)
cache_source = (root/'kernel/fs/ext2/pagecache.v').read_text()
cache_first = cache_source.index('fn (mut filesystem EXT2Filesystem) raw_device_write(')
cache_last = cache_source.index('\nfn ', cache_first + 4)
with tempfile.TemporaryDirectory(prefix='vinix-attribute-publish-') as temporary:
    work = Path(temporary)
    for module in ('ext2', 'errno', 'katomic', 'resource'):
        (work/module).mkdir()
    (work/'v.mod').write_text("Module { name: 'vinix_attributes' }\n")
    (work/'ext2/production.v').write_text('module ext2\nimport errno\nimport katomic\nimport resource as resource_mod\n' + source[first:last] + '\n' + cache_source[cache_first:cache_last] + '\nfn C.memset(voidptr, int, usize) voidptr\nfn C.__builtin_alloca(usize) voidptr\n')
    (work/'errno/errno.v').write_text('module errno\npub const ebusy = 16\npub const eio = 5\npub fn set(_ int) {}\n')
    (work/'katomic/katomic.v').write_text('module katomic\npub fn store[T](mut value T, wanted T) { value = wanted }\n')
    (work/'resource/resource.v').write_text('module resource\npub const attributes_kept = u32(0x30)\n')
    (work/'ext2/model.v').write_text('''module ext2
struct Lock {
mut:
 depth int
}
fn (mut guard Lock) acquire() { assert guard.depth == 0; guard.depth = 1 }
fn (mut guard Lock) release() { assert guard.depth == 1; guard.depth = 0 }
struct Stat {
 ino u32
 size i64
}
struct BackingResource {
 stat Stat
}
struct BackingNode {
 resource BackingResource
}
type IO = fn (voidptr, voidptr, u64, u64) ?i64
struct FakeCache {
 result i64
}
fn (_cache FakeCache) write(_context voidptr, _load IO, _store IO, _buffer voidptr,
 _location u64, _count u64, _size u64) ?i64 {
 return _cache.result
}
fn device_read(_context voidptr, _buffer voidptr, _location u64, _count u64) ?i64 { return none }
fn device_write(_context voidptr, _buffer voidptr, _location u64, _count u64) ?i64 { return none }
struct EXT2Filesystem {
mut:
 l Lock
 inode_flags u32
 fail_read bool
 fail_write bool
 publish_on_failure bool
 short_write bool
 cache FakeCache
 backing_device &BackingNode = unsafe { nil }
}
struct EXT2Resource {
mut:
 l Lock
 filesystem &EXT2Filesystem
 stat Stat
 attr_bits u32
 shared_mapping_ranges u64
}
struct EXT2Inode {
mut:
 flags u32
}
fn (mut inode EXT2Inode) read_entry(mut filesystem EXT2Filesystem, _ino u32) ? {
 assert filesystem.l.depth == 1
 if filesystem.fail_read { return none }
 inode.flags = filesystem.inode_flags
}
fn (mut inode EXT2Inode) write_entry(mut filesystem EXT2Filesystem, _ino u32) ? {
 assert filesystem.l.depth == 1
 if !filesystem.fail_write || filesystem.publish_on_failure { filesystem.inode_flags = inode.flags }
 if filesystem.short_write {
  filesystem.raw_device_write(unsafe { voidptr(&inode) }, 0, sizeof(EXT2Inode))?
 }
 if filesystem.fail_write { return none }
}
fn flush_on_return() {}
''')
    shutil.copy2(Path(__file__).with_name('attribute_fault_test.v'), work/'ext2/attribute_fault_test.v')
    environment = os.environ.copy()
    environment['VEXE'] = compiler
    subprocess.run([compiler, '-gc', 'none', 'test', 'ext2'], cwd=work, env=environment, check=True)
print('ATTRIBUTE PUBLICATION FAULTS PASS')
