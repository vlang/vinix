module ext2

import errno
import fs.journal
import fs as vfs
import resource as resource_mod
import memory
import lib
import pagecache
import klock

// Distinct from EXT2/EXT3: foreign drivers must not bypass this redo journal.
const journaled_signature = u16(0x4a56)
const truncate_pending = u32(0x56544e31)

__global (
	journal_volumes [16]&EXT2Filesystem
	journal_volumes_count int
	journal_volumes_lock klock.Lock
	journal_sync_registered bool
)

fn (mut filesystem EXT2Filesystem) journal_healthy() bool {
	filesystem.l.acquire()
	defer { filesystem.l.release() }
	return filesystem.journal == unsafe { nil } || !filesystem.journal.failed
}

fn sync_journal_volumes() bool {
	journal_volumes_lock.acquire()
	count := journal_volumes_count
	journal_volumes_lock.release()
	mut ok := true
	for i in 0 .. count {
		mut filesystem := journal_volumes[i]
		if !filesystem.journal_healthy() { ok = false }
	}
	return ok
}

fn (mut filesystem EXT2Filesystem) register_volume_cache() bool {
	if filesystem.journal == unsafe { nil } {
		return pagecache.register_cache(filesystem.cache, voidptr(filesystem.backing_device), device_write, device_flush)
	}
	journal_volumes_lock.acquire()
	defer { journal_volumes_lock.release() }
	if journal_volumes_count == journal_volumes.len { return false }
	if !journal_sync_registered {
		if !pagecache.register_sync_hook(sync_journal_volumes) { return false }
		journal_sync_registered = true
	}
	if !pagecache.register_cache(filesystem.cache, voidptr(filesystem.backing_device), device_write, device_flush) { return false }
	// Both registries own mount-lifetime pointers. Publish only after the
	// last fallible registration, so initialization cleanup cannot dangle.
	journal_volumes[journal_volumes_count] = filesystem
	journal_volumes_count++
	return true
}

fn journal_load(context voidptr, buffer voidptr, offset u64, bytes u64) ?i64 {
	filesystem := unsafe { &EXT2Filesystem(context) }
	return device_read(voidptr(filesystem.backing_device), buffer, offset, bytes)
}

fn journal_store(context voidptr, buffer voidptr, offset u64, bytes u64) ?i64 {
	filesystem := unsafe { &EXT2Filesystem(context) }
	return device_write(voidptr(filesystem.backing_device), buffer, offset, bytes)
}

fn journal_barrier(context voidptr) ? {
	filesystem := unsafe { &EXT2Filesystem(context) }
	device_flush(voidptr(filesystem.backing_device))?
}

fn journal_publish(context voidptr, buffer voidptr, offset u64, bytes u64) {
	mut filesystem := unsafe { &EXT2Filesystem(context) }
	if !filesystem.cache.publish_durable(buffer, offset, bytes) && filesystem.journal != unsafe { nil } {
		filesystem.journal.failed = true
	}
}

fn journal_base_load(context voidptr, buffer voidptr, offset u64, bytes u64) ?i64 {
	mut filesystem := unsafe { &EXT2Filesystem(context) }
	return filesystem.cache.read(voidptr(filesystem.backing_device), device_read, device_write,
		buffer, offset, bytes, u64(filesystem.backing_device.resource.stat.size))
}

// Every mutation runs under the shared volume lock. Home cache pages stay
// clean and unchanged until commit; abort restores the in-memory superblock.
fn (mut filesystem EXT2Filesystem) begin_transaction() ? {
	if filesystem.read_only { errno.set(errno.erofs); return none }
	if filesystem.journal == unsafe { nil } { return }
	filesystem.journal.begin()?
	filesystem.saved_superblock = unsafe { *filesystem.superblock }
	filesystem.transaction_pending = true
}

fn (mut filesystem EXT2Filesystem) abort_transaction() {
	if !filesystem.transaction_pending { return }
	filesystem.journal.abort()
	unsafe { *filesystem.superblock = filesystem.saved_superblock }
	filesystem.transaction_pending = false
}

fn (mut filesystem EXT2Filesystem) commit_transaction() ? {
	if !filesystem.transaction_pending { return }
	filesystem.write_superblock()?
	filesystem.journal.commit()?
	if filesystem.journal.failed { errno.set(errno.eio); return none }
	filesystem.transaction_pending = false
}

// Each batch ends after a complete pointer detach and bitmap release, with
// the inode's updated sector count in the same commit. Remaining pointers
// stay owned by the persistent orphan or pending-truncate inode on a crash.
fn (mut filesystem EXT2Filesystem) checkpoint_cleanup(mut inode EXT2Inode) ? {
	if !filesystem.cleanup_in_progress || filesystem.journal == unsafe { nil }
		|| filesystem.journal.staged_pages() < journal.max_pages - 16 { return }
	inode.write_entry(mut filesystem, filesystem.cleanup_inode_index)?
	filesystem.commit_transaction()?
	filesystem.begin_transaction()?
}

fn (mut filesystem EXT2Filesystem) cleanup_inode(mut inode EXT2Inode, index u32) ? {
	filesystem.cleanup_in_progress = true
	filesystem.cleanup_inode_index = index
	defer { filesystem.cleanup_in_progress = false }
	if inode.hard_link_cnt == 0 { inode.free_entry(mut filesystem, index)?; return }
	inode.truncate_blocks(mut filesystem, index, lib.div_roundup(inode.size(), filesystem.block_size))?
	inode.oss1 = 0
	inode.write_entry(mut filesystem, index)?
}

// A crash drops all open descriptions. Zero-link allocated inodes are then
// persistent orphans, including removed directories and rename destinations.
fn (mut filesystem EXT2Filesystem) recover_orphans() ? {
	if filesystem.journal == unsafe { nil } || filesystem.read_only { return }
	bitmap := memory.calloc(filesystem.block_size, 1) @[freed]
	if bitmap == unsafe { nil } { errno.set(errno.enomem); return none }
	defer { memory.free(bitmap) }
	mut descriptor := unsafe { &EXT2BlockGroupDescriptor(C.__builtin_alloca(sizeof(EXT2BlockGroupDescriptor))) }
	mut inode := unsafe { &EXT2Inode(C.__builtin_alloca(sizeof(EXT2Inode))) }
	first := if filesystem.superblock.first_inode < 11 { u32(11) } else { filesystem.superblock.first_inode }
	for group in 0 .. filesystem.bgd_cnt {
		unsafe { *descriptor = EXT2BlockGroupDescriptor{} }
		if descriptor.read_entry(mut filesystem, u32(group)) < 0 { errno.set(errno.eio); return none }
		filesystem.raw_device_read(bitmap, u64(descriptor.block_addr_inode) * filesystem.block_size, filesystem.block_size)?
		for bit in 0 .. filesystem.superblock.inodes_per_group {
			index := group * u64(filesystem.superblock.inodes_per_group) + u64(bit) + 1
			if index < first || index > filesystem.superblock.inode_cnt
				|| unsafe { *(&u8(u64(bitmap) + u64(bit / 8))) } & (u8(1) << (bit % 8)) == 0 { continue }
			unsafe { *inode = EXT2Inode{} }
			inode.read_entry(mut filesystem, u32(index))?
			if inode.hard_link_cnt != 0 && inode.oss1 != truncate_pending { continue }
			filesystem.begin_transaction()?
			filesystem.cleanup_inode(mut inode, u32(index)) or { filesystem.abort_transaction(); return none }
			filesystem.commit_transaction() or { filesystem.abort_transaction(); return none }
		}
	}
}

fn format_journal_store(context voidptr, buffer voidptr, offset u64, bytes u64) ?i64 {
	mut device := unsafe { &vfs.VFSNode(context) }.resource
	return device.write(unsafe { nil }, buffer, offset, bytes)
}

fn format_journal_barrier(context voidptr) ? {
	mut device := unsafe { &vfs.VFSNode(context) }.resource
	resource_mod.sync_resource(mut device, unsafe { nil })?
}
