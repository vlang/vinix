module ext2
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
