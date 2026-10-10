module ext2

import errno
import memory
import memory.mmap as mmap_mod
import sched

@[heap]
struct EXT2MappedPage {
mut:
	page     u64
	physical voidptr
	refs     u64 // Shared global mappings; private globals have PMM refs.
	shared_dirty bool
}

fn (mut this EXT2Resource) private_mapping_cow() bool { return true }

fn (mut this EXT2Resource) mark_mapping_dirty(page u64, physical voidptr) {
	this.l.acquire()
	defer { this.l.release() }
	if mut mapped := this.mapped_page_locked(page) {
		if mapped.physical == physical { mapped.shared_dirty = true }
	}
}

// Called under a VM lock; reverse lock acquisition must never wait.
fn (mut this EXT2Resource) uncached_mapping_page(page u64, physical voidptr) bool {
	if !this.l.test_and_acquire() { return false }
	defer { this.l.release() }
	if mapped := this.mapped_page_locked(page) { return mapped.physical != physical }
	return true
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
			state := mmap_mod.file_page_state(voidptr(this.box), mapped.page, mapped.physical, false)
			if !state.ready { return }
			mapped.shared_dirty = mapped.shared_dirty || state.dirty
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
	this.filesystem.begin_transaction()?
	old_inode := unsafe { *inode }
	mut committed := false
	defer {
		if !committed && this.filesystem.journal != unsafe { nil } { unsafe { *inode = old_inode } }
		this.filesystem.abort_transaction()
	}
	written := inode.write(mut this.filesystem, voidptr(u64(mapped.physical) + higher_half), u32(this.stat.ino), page_offset, count)?
	if written != i64(count) {
		errno.set(errno.eio)
		return none
	}
	this.filesystem.commit_transaction()?
	committed = true
}

// Revoke shared writes and collect dirty evidence from every alias before
// writing a snapshot. A later write faults and makes the next sync eligible.
fn (mut this EXT2Resource) sync_mapping(_handle voidptr, offset u64, length u64) ? {
	if !this.filesystem.journal_healthy() { errno.set(errno.eio); return none }
	if length == 0 || this.filesystem.read_only {
		return
	}
	this.write_mapped_pages(offset, length)?
	if !this.filesystem.journal_healthy() { errno.set(errno.eio); return none }
	// msync(MS_SYNC) must reach the backing resource, not merely the block
	// cache. The syscall epilogue flushes after all vnode locks are released.
	// Failed or short device writeback remains dirty there for retry.
	flush_on_return()
}

// Put the shared pages mapped over [offset, offset + length) into the block
// cache, where a flush finds them.
fn (mut this EXT2Resource) write_mapped_pages(offset u64, length u64) ? {
	for _ in 0 .. 64 {
		this.write_mapped_pages_once(offset, length) or {
			if errno.get() != errno.eagain { return none }
			sched.yield(true)
			continue
		}
		return
	}
	errno.set(errno.eagain)
	return none
}

fn (mut this EXT2Resource) write_mapped_pages_once(offset u64, length u64) ? {
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
		state := mmap_mod.file_page_state(voidptr(this.box), mapped.page, mapped.physical, false)
		if !state.ready { errno.set(errno.eagain); return none }
		mapped.shared_dirty = mapped.shared_dirty || state.dirty
		if mapped.shared_dirty {
			if !inode_loaded {
				inode.read_entry(mut this.filesystem, u32(this.stat.ino))?
				inode_loaded = true
			}
			this.write_mapped_page_locked(mut inode, mapped)?
			// Writes after revocation fault and leave new dirty evidence in
			// their PTEs, independently of this completed snapshot.
			mapped.shared_dirty = false
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

fn (mut this EXT2Resource) reclaim_mapped_pages(wanted u64, foreground bool) u64 {
	return this.reclaim_mapped_span(wanted, foreground, 0, u64(-1))
}

fn (mut this EXT2Resource) pageout_mapping(page u64) u64 {
	return this.reclaim_mapped_span(1, true, page, page + 1)
}

fn (mut this EXT2Resource) reclaim_mapped_span(wanted u64, foreground bool, begin u64, end u64) u64 {
	if !this.l.test_and_acquire() { return 0 }
	if !this.filesystem.l.test_and_acquire() { this.l.release(); return 0 }
	defer {
		drop_registry := this.unregister_empty_mapped_resource()
		this.filesystem.l.release()
		this.l.release()
		if drop_registry { this.unref(unsafe { nil }) or {} }
	}
	mut reclaimed := u64(0)
	mut inode := unsafe { &EXT2Inode(C.vinix_stack_alloc(sizeof(EXT2Inode))) }
	unsafe { *inode = EXT2Inode{} }
	mut inode_loaded := false
	// The first pass ages referenced pages. Foreground recovery revisits them
	// before reporting no progress; background scanning has a fixed budget.
	passes := if foreground { 2 } else { 1 }
	mut start := this.mapped_reclaim_cursor
	filtered := begin != 0 || end != u64(-1)
	if filtered {
		mut found := false
		for i, page in this.mapped_pages {
			if page.page >= begin && page.page < end { start = i; found = true; break }
		}
		if !found { return 0 }
	}
	for _ in 0 .. passes {
		mut index := if start < this.mapped_pages.len { start } else { 0 }
		mut scanned := 0
		budget := if filtered { 1 } else if foreground { this.mapped_pages.len } else { 256 }
		limit := if this.mapped_pages.len < budget { this.mapped_pages.len } else { budget }
		for this.mapped_pages.len != 0 && scanned < limit && reclaimed < wanted {
			if foreground && scanned != 0 && scanned % 256 == 0 {
				// The sweep owns a strong vnode pin. Drop IRQ-masking locks
				// between bounded batches; keep no cached-page pointer or
				// inode snapshot across the scheduler yield.
				this.filesystem.l.release()
				this.l.release()
				sched.yield(true)
				this.l.acquire()
				this.filesystem.l.acquire()
				inode_loaded = false
				if this.mapped_pages.len == 0 { break }
			}
			if index >= this.mapped_pages.len { index = 0 }
			scanned++
			mut mapped := this.mapped_pages[index]
			if mapped.page < begin || mapped.page >= end { index++; continue }
			state := mmap_mod.file_page_state(voidptr(this.box), mapped.page, mapped.physical, true)
			if !state.ready { index++; continue }
			mapped.shared_dirty = mapped.shared_dirty || state.dirty
			assert state.shared_refs <= mapped.refs
			mapped.refs -= state.shared_refs
			if state.referenced || state.blocked { index++; continue }
			if mapped.shared_dirty && !this.filesystem.read_only {
				if !inode_loaded {
					inode.read_entry(mut this.filesystem, u32(this.stat.ino)) or { index++; continue }
					inode_loaded = true
				}
				this.write_mapped_page_locked(mut inode, mapped) or { index++; continue }
				mapped.shared_dirty = false
			}
			if this.filesystem.read_only { mapped.shared_dirty = false }
			if this.retire_clean_page_locked(index) { reclaimed++ }
			else { index++ }
		}
		this.mapped_reclaim_cursor = index
	}
	return reclaimed
}
