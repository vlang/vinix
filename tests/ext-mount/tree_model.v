// Host doubles for VFS publication and device I/O. read_tree.v is copied
// unchanged; ownership, traversal, validation and failure cleanup are real.
module ext2

import fs as vfs
import resource
import stat
import klock

#flag -Dvinix_stack_alloc=__builtin_alloca
fn C.vinix_stack_alloc(usize) voidptr

__global live_resources int

struct EXT2Filesystem {
mut:
	dev_id u64
	l &klock.Lock = &klock.Lock{}
	block_size u64 = 1024
	superblock &EXT2Superblock = &EXT2Superblock{req_features: 2}
	backing_device &vfs.VFSNode = unsafe { nil }
	box &vfs.FileSystem = unsafe { nil }
	read_only bool = true
	inodes []EXT2Inode
	disk []u8
	reads int
	fail_at int
}

struct EXT2Resource {
mut:
	stat stat.Stat
	filesystem &EXT2Filesystem = unsafe { nil }
	refcount int
	box &resource.Resource = unsafe { nil }
	attr_bits u32
	can_mmap bool
}

fn (mut this EXT2Resource) unref(_ voidptr) ? {
	live_resources--
	unsafe { free(this.box); free(this) }
}

fn (mut this EXT2Filesystem) as_filesystem() &vfs.FileSystem {
	if this.box == unsafe { nil } { this.box = &vfs.FileSystem(this) }
	return this.box
}

fn (mut inode EXT2Inode) read_entry(mut filesystem EXT2Filesystem, index u32) ?int {
	filesystem.reads++
	if filesystem.reads == filesystem.fail_at || index >= u32(filesystem.inodes.len) { return none }
	unsafe { *inode = filesystem.inodes[index] }
	return 0
}

fn (mut inode EXT2Inode) read(mut filesystem EXT2Filesystem, buf voidptr, off u64, count u64) ?i64 {
	filesystem.reads++
	if filesystem.reads == filesystem.fail_at { return none }
	position := u64(inode.blocks[0]) * filesystem.block_size + off
	if position > u64(filesystem.disk.len) || count > u64(filesystem.disk.len) - position { return none }
	unsafe { C.memcpy(buf, &filesystem.disk[position], count) }
	return i64(count)
}

fn (mut this EXT2Resource) boxed() &resource.Resource {
	if this.box == unsafe { nil } {
		live_resources++
		this.box = &resource.Resource(this)
	}
	return this.box
}

fn inode_type(mode u32) u8 {
	return if stat.isdir(mode) { u8(2) } else if stat.islnk(mode) { u8(7) } else { u8(1) }
}
