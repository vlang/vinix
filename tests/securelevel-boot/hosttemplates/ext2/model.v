module ext2
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
 read_only bool
 journal &Journal = unsafe { nil }
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
