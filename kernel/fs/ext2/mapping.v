module ext2

import errno
import memory
import memory.mmap as mmap_mod

@[heap]
struct EXT2MappedPage {
mut:
	page     u64
	physical voidptr
	refs     u64
}

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
	// Every private fault gets its own disposable page. Shared pages stay
	// coherent with read(2) while mapped, then the final unmap writes and drops
	// them; a failed write leaves the page cached so fsync can retry it.
	if flags & mmap_mod.map_shared == 0 {
		memory.pmm_free(physical, 1)
		return
	}

	this.l.acquire()
	defer { this.l.release() }
	this.filesystem.l.acquire()
	defer { this.filesystem.l.release() }
	for index, _ in this.mapped_pages {
		mut mapped := this.mapped_pages[index]
		if mapped.page != _page || mapped.physical != physical {
			continue
		}
		if mapped.refs != 0 {
			mapped.refs--
		}
		if mapped.refs != 0 {
			return
		}
		mut inode := EXT2Inode{}
		inode.read_entry(mut this.filesystem, u32(this.stat.ino)) or { return }
		this.write_mapped_page_locked(mut inode, mapped) or { return }
		this.mapped_pages.delete(index)
		memory.pmm_free(mapped.physical, 1)
		unsafe { free(mapped) }
		return
	}
}

fn (mut this EXT2Resource) write_mapped_page_locked(mut inode EXT2Inode,
	mapped &EXT2MappedPage) ? {
	file_size := u64(inode.size32l) | (u64(inode.size32h) << 32)
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
	if length == 0 {
		return
	}
	end := if length > u64(-1) - offset { u64(-1) } else { offset + length }
	this.l.acquire()
	defer { this.l.release() }
	this.filesystem.l.acquire()
	defer { this.filesystem.l.release() }
	if this.mapped_pages.len == 0 {
		return
	}

	mut inode := EXT2Inode{}
	inode.read_entry(mut this.filesystem, u32(this.stat.ino))?
	mut index := 0
	for index < this.mapped_pages.len {
		mapped := this.mapped_pages[index]
		page_offset := mapped.page * page_size
		if page_offset >= end || page_offset + page_size <= offset {
			index++
			continue
		}
		this.write_mapped_page_locked(mut inode, mapped)?
		if mapped.refs == 0 {
			this.mapped_pages.delete(index)
			memory.pmm_free(mapped.physical, 1)
			unsafe { free(mapped) }
		} else {
			index++
		}
	}
	this.stat.size = i64(u64(inode.size32l) | (u64(inode.size32h) << 32))
	this.stat.blocks = inode.sector_cnt
	this.stat.mtim.tv_sec = inode.mod_time
	this.stat.mtim.tv_nsec = 0
	this.stat.ctim.tv_sec = inode.creation_time
	this.stat.ctim.tv_nsec = 0
	// msync(MS_SYNC) must reach the backing resource, not merely the block
	// cache. Failed or short device writeback remains dirty there for retry.
	this.filesystem.flush()?
}
