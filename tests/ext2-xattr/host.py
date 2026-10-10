#!/usr/bin/env python3
"""Exercise the production ext2 EA codec, including malformed disk blocks."""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]

with tempfile.TemporaryDirectory(prefix="vinix-xattr-codec-") as directory:
    work = Path(directory)
    (work / "ext2").mkdir()
    for module in ("errno", "memory", "time", "fs", "resource", "posix_acl"):
        (work / module).mkdir()
    (work / "v.mod").write_text("Module { name: 'vinix_xattr_tests' }\n")
    source = (ROOT / "kernel/fs/ext2/xattr_block.v").read_text()
    (work / "ext2/codec.v").write_text(source + "\nfn C.memcpy(voidptr, voidptr, usize) voidptr\n")
    codec_tests = (ROOT / "tests/ext2-xattr/codec_test.v").read_text()
    helper, tests = codec_tests.split("fn test_sorted_entries", 1)
    (work / "ext2/helper.v").write_text(helper)
    (work / "ext2/codec_test.v").write_text("module ext2\n\nfn test_sorted_entries" + tests)
    (work / "ext2/xattr.v").write_text((ROOT / "kernel/fs/ext2/xattr.v").read_text())
    (work / "ext2/persistence_test.v").write_text((ROOT / "tests/ext2-xattr/persistence_test.v").read_text())
    (work / "errno/errno.v").write_text("@[has_globals]\nmodule errno\n__global current_errno = int(0)\npub const enospc = 28\npub const enodata = 61\npub const enotsup = 95\npub const eio = 5\npub const enomem = 12\npub const eexist = 17\npub const einval = 22\npub fn set(value int) { current_errno = value }\npub fn get() int { return current_errno }\n")
    (work / "time/time.v").write_text("module time\npub struct TimeSpec { pub mut: tv_sec i64 }\n")
    (work / "memory/memory.v").write_text("""@[has_globals]
module memory
__global live_buffers = int(0)
pub fn calloc(size u64, count u64) voidptr {
 live_buffers++
 data := unsafe { malloc(int(size * count)) }
 unsafe { C.memset(data, 0, usize(size * count)) }
 return data
}
pub fn free(data voidptr) {
 if data == unsafe { nil } { return }
 live_buffers--
 unsafe { C.free(data) }
}
pub fn outstanding() int { return live_buffers }
fn C.memset(voidptr, int, usize) voidptr
fn C.free(voidptr)
""")
    (work / "ext2/model.v").write_text("""module ext2
import errno
import time
struct Lock {}
fn (mut lock Lock) acquire() {}
fn (mut lock Lock) release() {}
const ext2_feature_ro_compat_sparse_super = u32(1)
fn mkfs_has_backup(group u64) bool { return group <= 1 }
struct Superblock { mut: sb_block u32 block_cnt u32 opt_features u32 non_supported_features u32 blocks_per_group u32 = 64 inodes_per_group u32 = 32 inode_size u16 = 128 }
struct EXT2BlockGroupDescriptor { mut: block_addr_bitmap u32 = 60 block_addr_inode u32 = 61 inode_table_block u32 = 62 }
fn (mut bgd EXT2BlockGroupDescriptor) read_entry(mut fs EXT2Filesystem, _ u32) int { return 0 }
struct EXT2Inode { mut: eab u32 sector_cnt u32 creation_time u32 permissions u16 user_id u16 group_id u16 access_time u32 mod_time u32 flags u32 }
struct Journal {}
struct EXT2Filesystem {
mut:
 l Lock
 journal &Journal = unsafe { nil }
 block_size u64
 bgd_cnt u64 = 1
 superblock Superblock
 inode EXT2Inode
 blocks [][]u8
 allocated []bool
 fail_block_write bool
 fail_header_write bool
 fail_inode_write bool
}
struct Stat { mut: ino u64 blocks i64 ctim time.TimeSpec mode u32 uid u32 gid u32 atim time.TimeSpec mtim time.TimeSpec }
struct EXT2Resource { mut: l Lock filesystem &EXT2Filesystem stat Stat attr_bits u32 }
fn fixture() EXT2Filesystem {
 return EXT2Filesystem{block_size: 4096, superblock: Superblock{block_cnt: 64, opt_features: 8},
 blocks: [][]u8{len: 64, init: []u8{len: 4096}}, allocated: []bool{len: 64}}
}
fn (mut inode EXT2Inode) read_entry(mut fs EXT2Filesystem, _ u32) ?int { inode = fs.inode; return 0 }
fn (mut inode EXT2Inode) write_entry(mut fs EXT2Filesystem, _ u32) ?int {
 fs.inode = inode
 if fs.fail_inode_write { errno.set(errno.eio); return none }
 return 0
}
fn (mut fs EXT2Filesystem) raw_device_read(buf voidptr, loc u64, count u64) ?i64 {
 block := int(loc / 4096)
 offset := int(loc % 4096)
 unsafe { C.memcpy(buf, &fs.blocks[block][offset], count) }
 return i64(count)
}
fn (mut fs EXT2Filesystem) raw_device_write(buf voidptr, loc u64, count u64) ?i64 {
 if fs.fail_block_write || (fs.fail_header_write && count == 32) { errno.set(errno.eio); return none }
 block := int(loc / 4096)
 offset := int(loc % 4096)
 unsafe { C.memcpy(&fs.blocks[block][offset], buf, count) }
 return i64(count)
}
fn (mut fs EXT2Filesystem) allocate_block() ?u32 {
 for i in 2 .. fs.allocated.len { if !fs.allocated[i] { fs.allocated[i] = true; return u32(i) } }
 return none
}
fn (mut fs EXT2Filesystem) free_block(block u32) ?int { fs.allocated[int(block)] = false; return 0 }
fn (mut fs EXT2Filesystem) write_superblock() ? {}
// This fixture models legacy EXT2. Journal ownership and recovery are
// exercised separately against the production engine in tests/fs-journal.
fn (mut fs EXT2Filesystem) begin_transaction() ? {}
fn (mut fs EXT2Filesystem) commit_transaction() ? {}
fn (mut fs EXT2Filesystem) abort_transaction() {}
fn ext2_now() u32 { return 1 }
fn stat_seconds(value time.TimeSpec) u32 { return u32(value.tv_sec) }
fn flush_on_return() {}
""")
    copy_source = (ROOT / "kernel/fs/xattr.v").read_text()
    copy_source = copy_source.split("fn copy_one_xattr", 1)[1].split("// Called when a tmpfs file goes.", 1)[0]
    (work / "fs/copy.v").write_text("module fs\nimport errno\nimport resource\nfn copy_one_xattr" + copy_source)
    (work / "fs/copy_test.v").write_text((ROOT / "tests/ext2-xattr/copy_test.v").read_text())
    (work / "resource/resource.v").write_text("""module resource
import errno
pub const attributes_kept = u32(0)
pub const acl_clear_setgid = 4
pub struct PermissionMetadata { pub: mode u32 uid u32 gid u32 }
pub struct Resource { pub mut:
 names []u8
 value []u8
 missing string
 list_error int
 get_error int
 set_error int
 copied_names []string
 copied_values [][]u8
}
pub fn xattr_names(mut res Resource, mut names []u8) ? {
 if res.list_error != 0 { errno.set(res.list_error); return none }
 for c in res.names { names << c }
}
pub fn get_xattr(mut res Resource, name string, mut value []u8) ? {
 if name == res.missing { errno.set(errno.enodata); return none }
 if res.get_error != 0 { errno.set(res.get_error); return none }
 for c in res.value { value << c }
}
pub fn set_xattr(mut res Resource, name string, value []u8, _ int) ? {
 if res.set_error != 0 { errno.set(res.set_error); return none }
 res.copied_names << name.clone()
 res.copied_values << value.clone()
}
""")
    (work / "posix_acl/acl.v").write_text((ROOT / "kernel/posix_acl/acl.v").read_text())
    (work / "posix_acl/acl_test.v").write_text((ROOT / "tests/ext2-xattr/acl_test.v").read_text())
    subprocess.run([os.environ.get("V", "v"), "-enable-globals", "-gc", "none", "test", "ext2", "fs", "posix_acl"], cwd=work, check=True)
