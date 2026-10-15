// SPDX-License-Identifier: GPL-2.0-or-later
module ext2

import errno

// A zero-link inode still owns its allocation until the last description,
// mapping or deferred pathname/socket release retires it. Detaching first
// would let a caller remove the device before those later writes complete.
// Observe the coherent metadata under its existing volume lock. Do not drain
// the global grace queue, free resources early or wait for grace under VFS locks.
fn (mut filesystem EXT2Filesystem) check_unmount() ? {
	filesystem.l.acquire()
	defer { filesystem.l.release() }
	if filesystem.read_only { return }
	if filesystem.journal != unsafe { nil } && filesystem.journal.failed {
		errno.set(errno.eio)
		return none
	}
	if filesystem.block_size > 4096 { errno.set(errno.eio); return none }
	// The validated ext2 layout supports block sizes through 4096 bytes.
	// All scratch is on the stack, including repeated EBUSY retries.
	bitmap := unsafe { &u8(C.vinix_stack_alloc(4096)) }
	mut descriptor := unsafe { &EXT2BlockGroupDescriptor(C.vinix_stack_alloc(sizeof(EXT2BlockGroupDescriptor))) }
	mut inode := unsafe { &EXT2Inode(C.vinix_stack_alloc(sizeof(EXT2Inode))) }
	first := if filesystem.superblock.first_inode < 11 { u32(11) } else { filesystem.superblock.first_inode }
	for group in 0 .. filesystem.bgd_cnt {
		unsafe { *descriptor = EXT2BlockGroupDescriptor{} }
		if descriptor.read_entry(mut filesystem, u32(group)) < 0 { errno.set(errno.eio); return none }
		if descriptor.block_addr_inode == 0 || descriptor.block_addr_inode >= filesystem.superblock.block_cnt {
			errno.set(errno.eio); return none
		}
		filesystem.raw_device_read(bitmap, u64(descriptor.block_addr_inode) * filesystem.block_size, filesystem.block_size)?
		for bit in 0 .. filesystem.superblock.inodes_per_group {
			index := group * u64(filesystem.superblock.inodes_per_group) + u64(bit) + 1
			if index < first || index > filesystem.superblock.inode_cnt
				|| unsafe { bitmap[bit / 8] } & (u8(1) << (bit % 8)) == 0 { continue }
			unsafe { *inode = EXT2Inode{} }
			inode.read_entry(mut filesystem, u32(index))?
			if inode.hard_link_cnt == 0 || (filesystem.journal != unsafe { nil } && inode.oss1 == truncate_pending) {
				errno.set(errno.ebusy)
				return none
			}
		}
	}
	// A successful retry must also finish the reclaimed inode's cached writes.
	filesystem.cache.sync(voidptr(filesystem.backing_device), device_write)?
	device_flush(voidptr(filesystem.backing_device))?
}
