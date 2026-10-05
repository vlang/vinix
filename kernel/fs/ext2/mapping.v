module ext2

import errno
import memory
import memory.mmap as mmap_mod

@[heap]
struct EXT2MappedPage {
mut:
	page     u64
	physical voidptr
	refs     u64 // Shared global mappings; private globals have PMM refs.
	shared_dirty bool
}

fn (mut this EXT2Resource) private_mapping_cow() bool { return true }

// The resource lock is held while looking up pages. Shared mappings and
// descriptor I/O use the same physical page, which provides immediate
// visibility in both directions without duplicating a second file-data cache.
fn (this &EXT2Resource) mapped_page_locked(page u64) ?&EXT2MappedPage {
	for mapped in this.mapped_pages {
		if mapped.page == page {
			return mapped
		}
	}
	return none
}

fn (mut this EXT2Resource) release_mapping(_handle voidptr, _page u64,
	physical voidptr, flags int) {
	this.l.acquire()
	this.filesystem.l.acquire()
	defer {
		drop_registry := this.unregister_empty_mapped_resource()
		this.filesystem.l.release()
		this.l.release()
		// The mapping/global range still owns a separate resource reference.
		if drop_registry { this.unref(unsafe { nil }) or {} }
	}
	for index, _ in this.mapped_pages {
		mut mapped := this.mapped_pages[index]
		if mapped.page != _page || mapped.physical != physical {
			continue
		}
		if flags & mmap_mod.map_shared == 0 {
			// Return the private global's reference. The cache still owns one,
			// so fork and another private mapper may continue reading it.
			memory.pmm_free(physical, 1)
		} else if mapped.refs != 0 {
			mapped.refs--
		}
		if mapped.refs != 0 {
			return
		}
		if mapped.shared_dirty && !this.filesystem.read_only {
			mut inode := unsafe { &EXT2Inode(C.vinix_stack_alloc(sizeof(EXT2Inode))) }
			unsafe { *inode = EXT2Inode{} }
			inode.read_entry(mut this.filesystem, u32(this.stat.ino)) or { return }
			this.write_mapped_page_locked(mut inode, mapped) or { return }
			mapped.shared_dirty = false
		}
		if this.filesystem.read_only { mapped.shared_dirty = false }
		this.retire_clean_page_locked(index)
		return
	}
	// A COW copy or private page beyond EOF is not a cache-owned page.
	if flags & mmap_mod.map_shared == 0 { memory.pmm_free(physical, 1) }
}

fn (mut this EXT2Resource) retire_clean_page_locked(index int) bool {
	mapped := this.mapped_pages[index]
	if mapped.refs != 0 || mapped.shared_dirty
		|| memory.pmm_refcount(mapped.physical) != 1 { return false }
	this.mapped_pages.delete(index)
	memory.pmm_free(mapped.physical, 1)
	unsafe { free(mapped) }
	return true
}

fn (mut this EXT2Resource) write_mapped_page_locked(mut inode EXT2Inode,
	mapped &EXT2MappedPage) ? {
	if this.filesystem.read_only { return }
	file_size := inode.size()
	page_offset := mapped.page * page_size
	if page_offset >= file_size {
		return
	}
	count := if page_size < file_size - page_offset { page_size } else { file_size - page_offset }
	written := inode.write(mut this.filesystem, voidptr(u64(mapped.physical) + higher_half), u32(this.stat.ino), page_offset, count)?
	if written != i64(count) {
		errno.set(errno.eio)
		return none
	}
}

// Write every cached shared page which intersects the requested file range.
// Vinix does not expose hardware dirty bits to the common VM yet, so this is
// deliberately conservative: a page remains eligible on every later fsync or
// msync, ensuring writes made after an earlier synchronization are not lost.
fn (mut this EXT2Resource) sync_mapping(_handle voidptr, offset u64, length u64) ? {
	if length == 0 || this.filesystem.read_only {
		return
	}
	this.write_mapped_pages(offset, length)?
	// msync(MS_SYNC) must reach the backing resource, not merely the block
	// cache. It does before the call returns, but msync holds the address
	// space's lock here, so the flush waits until the thread holds nothing.
	// Failed or short device writeback remains dirty there for retry.
	flush_on_return()
}

// Put the shared pages mapped over [offset, offset + length) into the block
// cache, where a flush finds them.
fn (mut this EXT2Resource) write_mapped_pages(offset u64, length u64) ? {
	if this.filesystem.read_only { return }
	end := if length > u64(-1) - offset { u64(-1) } else { offset + length }
	this.l.acquire()
	this.filesystem.l.acquire()
	defer {
		drop_registry := this.unregister_empty_mapped_resource()
		this.filesystem.l.release()
		this.l.release()
		// Called through an open handle or a registry sweep's extra pin.
		if drop_registry { this.unref(unsafe { nil }) or {} }
	}
	if this.mapped_pages.len == 0 {
		return
	}

	mut inode := unsafe { &EXT2Inode(C.vinix_stack_alloc(sizeof(EXT2Inode))) }
	unsafe { *inode = EXT2Inode{} }
	mut inode_loaded := false
	mut index := 0
	for index < this.mapped_pages.len {
		mut mapped := this.mapped_pages[index]
		page_offset := mapped.page * page_size
		if page_offset >= end || page_offset + page_size <= offset {
			index++
			continue
		}
		if mapped.shared_dirty {
			if !inode_loaded {
				inode.read_entry(mut this.filesystem, u32(this.stat.ino))?
				inode_loaded = true
			}
			this.write_mapped_page_locked(mut inode, mapped)?
			// Existing shared mappings may write again without a fault.
			if mapped.refs == 0 { mapped.shared_dirty = false }
		}
		if !this.retire_clean_page_locked(index) { index++ }
	}
	if inode_loaded {
		this.stat.size = i64(inode.size())
		this.stat.blocks = inode.sector_cnt
		this.stat.mtim.tv_sec = inode.mod_time
		this.stat.mtim.tv_nsec = 0
		this.stat.ctim.tv_sec = inode.creation_time
		this.stat.ctim.tv_nsec = 0
	}
}
