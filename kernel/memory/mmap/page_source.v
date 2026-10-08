module mmap

import errno
import memory
import numa
import resource
import pager

// Captured with the pagemap lock held. Nothing here borrows a VMA/global
// pointer after that lock is released: identities are compared, never read.
// The independent handle/resource pin makes every raced page return safe.
struct RangePageSource {
mut:
	local_identity voidptr
	local_generation u64
	global_serial u64
	file_page u64
	resource &resource.Resource = unsafe { nil }
	handle voidptr
	handle_unref fn (voidptr) = unsafe { nil }
	owns_resource bool
	owns_range bool
	offset u64
	length u64
	flags int
	cached_private bool
	direct bool
	data_begin u64
	data_end u64 = page_size
	backing voidptr
}

fn range_page_source(local &MmapRangeLocal, virt u64) RangePageSource {
	global := local.global
	mut source := RangePageSource{
		local_identity: voidptr(local)
		local_generation: local.generation
		global_serial: global.serial
		file_page: u64(local.offset) / page_size + (virt - local.base) / page_size
		resource: global.resource
		handle: global.handle
		handle_unref: global.handle_unref
		offset: u64(global.offset)
		length: global.length
		flags: local.flags
		cached_private: global.private_cow
		direct: local.flags & map_anonymous != 0
			|| (global.segmented_file && !range_page_has_file_data(global, virt))
	}
	mut owner := unsafe { global }
	owner.shadow_pagemap.l.acquire()
	node := paged_find(owner.paged_pages, shadow_address(local, virt))
	if node != unsafe { nil } {
		source.backing = voidptr(node.backing)
		pager.retain(node.backing)
	}
	owner.shadow_pagemap.l.release()
	if !source.direct {
		if source.handle != unsafe { nil } && global.handle_ref != unsafe { nil } {
			global.handle_ref(source.handle)
		} else {
			mut res := source.resource
			resource.retain_resource(mut res)
			source.owns_resource = true
		}
		if global.segmented_file {
			relative := virt - global.base
			if global.file_data_start > relative {
				source.data_begin = global.file_data_start - relative
			}
			absolute_end := global.file_data_start + global.file_data_length
			if absolute_end < relative + page_size {
				source.data_end = absolute_end - relative
			}
		}
	}
	return source
}

// Driver mapping-lifetime callbacks can take driver/usercopy locks. Pin the
// optional storage range outside pagemap.l; it may safely refuse a range
// already destroyed before this pin was acquired.
fn (mut source RangePageSource) prepare() bool {
	if source.direct { return true }
	mut res := source.resource
	if !resource.retain_mapping_range(mut res, source.handle, source.offset, source.length, source.flags) {
		return false
	}
	source.owns_range = true
	return true
}

fn (source RangePageSource) close() {
	pager.release(unsafe { &pager.Backing(source.backing) })
	if source.direct { return }
	mut res := source.resource
	if source.owns_range {
		resource.release_mapping_range(mut res, source.handle, source.offset, source.length, source.flags)
	}
	if source.owns_resource {
		resource.release_resource(mut res)
	} else if source.handle_unref != unsafe { nil } {
		source.handle_unref(source.handle)
	}
}

fn (source RangePageSource) give_back(file_page u64, physical voidptr) {
	if source.direct {
		memory.pmm_free(physical, 1)
		return
	}
	mut res := source.resource
	resource.release_mapping(mut res, source.handle, file_page, physical, source.flags)
}

fn (source RangePageSource) give_back_cow(physical voidptr) {
	if !source.direct && source.cached_private {
		source.give_back(source.file_page, physical)
		return
	}
	// fork retained ordinary private pages itself. Device resources without
	// a per-page release callback must still drop that extra PMM reference.
	memory.pmm_free(physical, 1)
}

// One call owns exactly one source pin. Keeping the defer out of population
// loops also keeps thousands of faults from retaining pins until mmap returns.
fn fill_range_page(mut pagemap memory.Pagemap, _source RangePageSource,
	virt u64, file_page u64) ? {
	mut source := _source
	for _ in 0 .. 8 {
		if !source.prepare() { source.close(); return none }
		page := acquire_range_page(source, file_page) or { source.close(); return none }
		install_range_page(mut pagemap, source, virt, file_page, page) or {
			failure := errno.get()
			source.close()
			if failure != errno.eagain { return none }
			pagemap.l.acquire()
			current, _, current_page := addr2range(&pagemap, virt) or {
				pagemap.l.release(); return none
			}
			if current.global.serial != source.global_serial || current_page != file_page {
				pagemap.l.release(); return none
			}
			source = range_page_source(current, virt)
			pagemap.l.release()
			continue
		}
		source.close()
		return
	}
	source.close()
	errno.set(errno.eagain)
	return none
}

fn acquire_range_page(source RangePageSource, file_page u64) ?voidptr {
	if source.backing != unsafe { nil } { return pager.load(unsafe { &pager.Backing(source.backing) }) }
	if source.direct {
		page := numa.alloc_user_page()
		if page == unsafe { nil } {
			errno.set(errno.enomem)
			return none
		}
		return page
	}
	mut res := source.resource
	mut page := res.mmap(source.handle, file_page, source.flags)
	if page == unsafe { nil } { return none }
	if source.data_begin != 0 || source.data_end < page_size {
		// ELF edge zero-fill belongs to this segment, not the cached vnode
		// page or another segment/process mapping the same file page.
		if source.flags & map_shared == 0 && memory.pmm_refcount(page) > 1 {
			copy := numa.alloc_user_page_nozero()
			if copy == unsafe { nil } {
				source.give_back(file_page, page)
				errno.set(errno.enomem)
				return none
			}
			unsafe { C.memcpy(voidptr(u64(copy) + higher_half), voidptr(u64(page) + higher_half), page_size) }
			source.give_back(file_page, page)
			page = copy
		}
		if source.data_begin != 0 {
			unsafe { C.memset(voidptr(u64(page) + higher_half), 0, source.data_begin) }
		}
		if source.data_end < page_size {
			unsafe { C.memset(voidptr(u64(page) + higher_half + source.data_end), 0, page_size - source.data_end) }
		}
	}
	return page
}
