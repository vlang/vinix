@[has_globals]
module ext2

import errno
import fs as vfs
import klock
import memory
import pagecache
import resource as resource_mod
import stat

__global (
	// Where transfers between the caches and their devices are staged: a run
	// of max_run_pages, physically contiguous, set aside when the first volume
	// is found. Allocated per transfer, it was a run of up to 32 pages asked
	// for with a cache's lock held, when that cache had filled memory and was
	// the one thing the reclaimers could not free: no run was left, and the
	// allocator stopped the kernel.
	ext2_bounce      voidptr
	ext2_bounce_lock klock.Lock
)

fn bounce_pages() u64 {
	return (pagecache.max_run_pages * pagecache.page_bytes + page_size - 1) / page_size
}

fn reserve_bounce() {
	ext2_bounce_lock.acquire()
	defer { ext2_bounce_lock.release() }
	if ext2_bounce != unsafe { nil } {
		return
	}
	physical := memory.pmm_alloc_fallible(bounce_pages())
	if physical != unsafe { nil } {
		ext2_bounce = voidptr(u64(physical) + higher_half)
	}
}

// Cache keys are offsets in the backing resource, not inode-relative offsets.
// Metadata and data therefore share one coherent cache, including byte-sized
// bitmap updates and sub-sector inode writes. All instances of a detected
// filesystem share the cache created by ext2_init.
// Preserve the old raw-I/O adapter's physically contiguous, page-aligned
// buffers. Cached bytes themselves live in heap allocations and must not be
// handed straight to a DMA backend, so misses and write-backs are staged in
// ext2_bounce.
// A write-back sends a run of consecutive pages in one transfer.
fn device_transfer(context voidptr, buf voidptr, loc u64, count u64, writing bool) ?i64 {
	if count == 0 {
		return 0
	}
	if count > pagecache.max_run_pages * pagecache.page_bytes {
		errno.set(errno.einval)
		return none
	}
	ext2_bounce_lock.acquire()
	defer { ext2_bounce_lock.release() }
	mut bounce := ext2_bounce
	mut physical := voidptr(unsafe { nil })
	pages := (count + page_size - 1) / page_size
	if bounce == unsafe { nil } {
		// None could be set aside: take one for this transfer, failing it
		// rather than the kernel when there is none. The cache keeps what it
		// could not write and tries again.
		physical = memory.pmm_alloc_nozero_fallible(pages)
		if physical == unsafe { nil } {
			errno.set(errno.enomem)
			return none
		}
		bounce = voidptr(u64(physical) + higher_half)
	}
	defer {
		if physical != unsafe { nil } {
			memory.pmm_free(physical, pages)
		}
	}
	// Keep the VFS node as the opaque callback context. A V interface is two
	// words (the object pointer and its method table); converting the interface
	// itself to voidptr loses the method table and makes the indirect read/write
	// call jump through address zero on real block devices.
	backing_device := unsafe { &vfs.VFSNode(context) }
	mut device := backing_device.resource
	if writing {
		unsafe { C.memcpy(bounce, buf, count) }
		return device.write(0, bounce, loc, count)
	}
	ret := device.read(0, bounce, loc, count) or { return none }
	if ret < 0 || u64(ret) > count {
		errno.set(errno.eio)
		return none
	}
	unsafe { C.memcpy(buf, bounce, u64(ret)) }
	return ret
}

fn device_read(context voidptr, buf voidptr, loc u64, count u64) ?i64 {
	return device_transfer(context, buf, loc, count, false)
}

fn device_write(context voidptr, buf voidptr, loc u64, count u64) ?i64 {
	return device_transfer(context, buf, loc, count, true)
}

fn device_flush(context voidptr) ? {
	backing_device := unsafe { &vfs.VFSNode(context) }
	mut device := backing_device.resource
	resource_mod.sync_resource(mut device, unsafe { nil })?
}

fn (mut filesystem EXT2Filesystem) enable_large_files() ? {
	if filesystem.superblock.non_supported_features & ext2_feature_ro_compat_large_file != 0 { return }
	filesystem.superblock.non_supported_features |= ext2_feature_ro_compat_large_file
	filesystem.write_superblock() or {
		filesystem.superblock.non_supported_features &= ~ext2_feature_ro_compat_large_file
		return none
	}
	// A journaled transaction publishes the capability with the inode and
	// its data, under one durable commit rather than a separate cache flush.
	if filesystem.journal != unsafe { nil } { return }
	// Publish the format capability durably before publishing an inode that
	// needs it. This is a one-time transition, not a barrier per file write.
	filesystem.cache.sync(voidptr(filesystem.backing_device), device_write) or {
		filesystem.superblock.non_supported_features &= ~ext2_feature_ro_compat_large_file
		return none
	}
	device_flush(voidptr(filesystem.backing_device)) or {
		filesystem.superblock.non_supported_features &= ~ext2_feature_ro_compat_large_file
		return none
	}
}

fn (mut filesystem EXT2Filesystem) raw_device_read(buf voidptr, loc u64, count u64) ?i64 {
	if filesystem.journal != unsafe { nil } {
		return filesystem.journal.read(journal_base_load, buf, loc, count)
	}
	ret := filesystem.cache.read(voidptr(filesystem.backing_device), device_read, device_write, buf, loc, count, u64(filesystem.backing_device.resource.stat.size)) or {
		return none
	}
	// EXT2's internal callers require exact transfers, unlike the Resource API.
	if ret != i64(count) {
		errno.set(errno.eio)
		return none
	}
	return ret
}

fn (mut filesystem EXT2Filesystem) raw_device_write(buf voidptr, loc u64, count u64) ?i64 {
	// Refuse before touching the coherent cache. Letting a write merely fail
	// at later writeback would leave unauthenticated data readable in RAM.
	if filesystem.read_only {
		errno.set(errno.erofs)
		return none
	}
	if filesystem.journal != unsafe { nil } {
		return filesystem.journal.write(journal_base_load, buf, loc, count)
	}
	ret := filesystem.cache.write(voidptr(filesystem.backing_device), device_read, device_write, buf, loc, count, u64(filesystem.backing_device.resource.stat.size)) or {
		return none
	}
	if ret != i64(count) {
		errno.set(errno.eio)
		return none
	}
	return ret
}

fn (mut this EXT2Resource) sync(_handle voidptr) ? {
	if !this.filesystem.journal_healthy() { errno.set(errno.eio); return none }
	// Shared mmap pages sit above the common backing-device cache. Fold them
	// into the inode first, then flush metadata and data through the same cache.
	this.write_mapped_pages(0, u64(-1))?
	mut device := this.filesystem.backing_device.resource
	this.filesystem.cache.sync(voidptr(this.filesystem.backing_device), device_write) or { return none }
	// Drivers may additionally implement a hardware cache/barrier operation.
	// Without one, success means completion at the backing Resource, not a
	// promise that volatile controller caches survive loss of power.
	resource_mod.sync_resource(mut device, unsafe { nil }) or { return none }
	if !this.filesystem.journal_healthy() { errno.set(errno.eio); return none }
}

fn (mut this EXT2Resource) advise(_handle voidptr, offset u64, length u64, advice int) ? {
	if advice != pagecache.willneed && advice != pagecache.dontneed {
		return
	}
	if !stat.isreg(this.stat.mode) {
		return
	}
	this.l.acquire()
	defer { this.l.release() }
	this.filesystem.l.acquire()
	defer { this.filesystem.l.release() }
	mut inode := unsafe { &EXT2Inode(C.vinix_stack_alloc(sizeof(EXT2Inode))) }
	unsafe { *inode = EXT2Inode{} }
	inode.read_entry(mut this.filesystem, u32(this.stat.ino)) or { return none }
	size := inode.size()
	if offset >= size {
		return
	}
	mut end := size
	if length != 0 && length < size - offset {
		end = offset + length
	}

	block_size := this.filesystem.block_size
	if block_size == 0 {
		errno.set(errno.eio)
		return none
	}
	device_size := u64(this.filesystem.backing_device.resource.stat.size)
	context := voidptr(this.filesystem.backing_device)
	// A hint may cover an enormous file. Bound both metadata walks and fills.
	mut budget := u64(pagecache.default_capacity) * pagecache.page_bytes / block_size
	mut block := offset / block_size
	mut run_start := u64(0)
	mut run_end := u64(0)
	for block * block_size < end && budget > 0 {
		disk_block := inode.get_block(mut this.filesystem, u32(block)) or { break }
		physical := u64(disk_block) * block_size
		logical := block * block_size
		// Coalesce contiguous blocks so a 1 KiB EXT2 filesystem can discard
		// complete 4 KiB cache pages. Ignore holes and partial boundary blocks.
		if disk_block != 0 && logical >= offset && block_size <= end - logical {
			if run_end != physical && run_end > run_start {
				this.advise_run(context, run_start, run_end - run_start, device_size, advice)
				run_end = 0
			}
			if run_end == 0 {
				run_start = physical
			}
			run_end = physical + block_size
		} else {
			if run_end > run_start {
				this.advise_run(context, run_start, run_end - run_start, device_size, advice)
			}
			run_start = 0
			run_end = 0
			if advice == pagecache.willneed && disk_block != 0 {
				this.advise_run(context, physical, block_size, device_size, advice)
			}
		}
		block++
		budget--
	}
	if run_end > run_start {
		this.advise_run(context, run_start, run_end - run_start, device_size, advice)
	}
}

fn (mut this EXT2Resource) advise_run(context voidptr, loc u64, count u64, size u64, advice int) {
	if advice == pagecache.willneed {
		this.filesystem.cache.prefetch(context, device_read, device_write, loc, count, size)
	} else {
		this.filesystem.cache.discard(loc, count)
	}
}
