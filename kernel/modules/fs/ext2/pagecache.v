module ext2

import errno
import memory
import pagecache
import resource as resource_mod
import stat

// Cache keys are offsets in the backing resource, not inode-relative offsets.
// Metadata and data therefore share one coherent cache, including byte-sized
// bitmap updates and sub-sector inode writes. All instances of a detected
// filesystem share the cache created by ext2_init.
// Preserve the old raw-I/O adapter's physically contiguous, page-aligned
// buffers. Cached bytes themselves live in heap allocations and must not be
// handed straight to a DMA backend. Only misses/writeback allocate a bounce.
fn device_transfer(context voidptr, buf voidptr, loc u64, count u64, writing bool) ?i64 {
	if count == 0 {
		return 0
	}
	if count > pagecache.page_bytes {
		errno.set(errno.einval)
		return none
	}
	physical := memory.pmm_alloc(1)
	if physical == unsafe { nil } {
		errno.set(errno.enomem)
		return none
	}
	bounce := voidptr(u64(physical) + higher_half)
	defer { memory.pmm_free(physical, 1) }
	mut device := unsafe { &resource_mod.Resource(context) }
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

fn (mut filesystem EXT2Filesystem) raw_device_read(buf voidptr, loc u64, count u64) ?i64 {
	ret := filesystem.cache.read(voidptr(filesystem.backing_device.resource), device_read, device_write, buf, loc, count, u64(filesystem.backing_device.resource.stat.size)) or {
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
	ret := filesystem.cache.write(voidptr(filesystem.backing_device.resource), device_read, device_write, buf, loc, count, u64(filesystem.backing_device.resource.stat.size)) or {
		return none
	}
	if ret != i64(count) {
		errno.set(errno.eio)
		return none
	}
	return ret
}

fn (mut this EXT2Resource) sync(_handle voidptr) ? {
	// Shared mmap pages sit above the common backing-device cache. Fold them
	// into the inode first, then flush metadata and data through the same cache.
	this.sync_mapping(_handle, 0, u64(-1))?
	mut device := this.filesystem.backing_device.resource
	this.filesystem.cache.sync(voidptr(device), device_write) or { return none }
	// Drivers may additionally implement a hardware cache/barrier operation.
	// Without one, success means completion at the backing Resource, not a
	// promise that volatile controller caches survive loss of power.
	resource_mod.sync_resource(mut device, unsafe { nil }) or { return none }
}

fn (mut this EXT2Resource) advise(_handle voidptr, offset u64, length u64, advice int) ? {
	if advice != pagecache.willneed && advice != pagecache.dontneed {
		return
	}
	if !stat.isreg(this.stat.mode) {
		return
	}
	mut inode := EXT2Inode{}
	inode.read_entry(mut this.filesystem, u32(this.stat.ino)) or { return none }
	size := u64(inode.size32l)
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
	context := voidptr(this.filesystem.backing_device.resource)
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
