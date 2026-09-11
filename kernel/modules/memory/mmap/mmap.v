module mmap

import memory
import resource
import proc
import errno
import lib

pub const prot_none = 0x00
pub const prot_read = 0x01
pub const prot_write = 0x02
pub const prot_exec = 0x04
pub const map_private = 0x02
pub const map_shared = 0x01
pub const map_fixed = 0x10
pub const map_fixed_noreplace = 0x100000
pub const map_anon = 0x20
pub const map_anonymous = 0x20

const ms_async = 1
const ms_invalidate = 2
const ms_sync = 4

// Private bookkeeping flag for the one large brk arena.  Only the committed
// portion up to brk_current is charged to RLIMIT_AS; the inaccessible reserve
// exists solely to keep unrelated mappings out of future heap addresses.
const map_brk_reservation = 0x20000000

// Runtimes such as JavaScriptCore reserve multi-gigabyte anonymous arenas but
// commit only a small fraction of them. Keep large reservations sparse and let
// the existing page-fault path allocate the pages that are actually touched.
const lazy_anonymous_threshold = u64(64 * 1024 * 1024)

// Resources that need uncached page table mappings (e.g., framebuffers).
// On ARM64, device memory must be Non-Cacheable so writes reach hardware.
__global (
	uncached_resources     [8]voidptr
	uncached_resources_cnt = u32(0)
)

pub fn register_uncached_resource(res voidptr) {
	if uncached_resources_cnt >= 8 {
		return
	}
	uncached_resources[uncached_resources_cnt] = res
	uncached_resources_cnt++
}

// Extract the underlying object pointer from a V interface value.
// V interfaces are stored as { _object voidptr, _interface_idx int }.
fn interface_object_ptr(iface voidptr) voidptr {
	return unsafe { *&voidptr(iface) }
}

fn is_uncached_resource(iface_ptr voidptr) bool {
	obj := interface_object_ptr(iface_ptr)
	for i := u32(0); i < uncached_resources_cnt; i++ {
		if uncached_resources[i] == obj {
			return true
		}
	}
	return false
}

pub struct MmapRangeLocal {
pub mut:
	pagemap &memory.Pagemap = unsafe { nil }
	global  &MmapRangeGlobal = unsafe { nil }
	base    u64
	length  u64
	offset  i64
	prot    int
	flags   int
	cow     bool
}

pub struct MmapRangeGlobal {
pub mut:
	shadow_pagemap memory.Pagemap
	locals         []&MmapRangeLocal
	resource       &resource.Resource = unsafe { nil }
	handle         voidptr
	handle_ref     fn (voidptr) = unsafe { nil }
	handle_unref   fn (voidptr) = unsafe { nil }
	base           u64
	length         u64
	offset         i64
	pte_extra      u64 // Extra PTE flags (e.g., pte_uncached for device memory)
}

pub fn list_ranges(pagemap &memory.Pagemap) {
	C.printf(c'Ranges for %llx:\n', voidptr(pagemap))
	for i := u64(0); i < pagemap.mmap_ranges.len; i++ {
		r := unsafe { &MmapRangeLocal(pagemap.mmap_ranges[i]) }
		C.printf(c'                                Base: %p  Length: %p  Offset: %p\n', r.base, r.length, r.offset)
		C.printf(c'    Global: %p  Base: %p  Length: %p  Offset: %p\n', r.global, r.global.base, r.global.length, r.global.offset)
	}
}

fn addr2range(pagemap &memory.Pagemap, addr u64) ?(&MmapRangeLocal, u64, u64) {
	for i := u64(0); i < pagemap.mmap_ranges.len; i++ {
		r := unsafe { &MmapRangeLocal(pagemap.mmap_ranges[i]) }
		if addr >= r.base && addr < r.base + r.length {
			memory_page := addr / page_size
			file_page := u64(r.offset) / page_size + (memory_page - r.base / page_size)
			return r, memory_page, file_page
		}
	}
	return none
}

// The caller must hold pagemap.l. MAP_FIXED_NOREPLACE and non-fixed address
// hints need this check to reserve Windows' preferred image addresses without
// destroying an existing mapping.
fn range_is_free_unlocked(pagemap &memory.Pagemap, base u64, length u64) bool {
	end := base + length
	if end < base {
		return false
	}
	for ptr in pagemap.mmap_ranges {
		range_local := unsafe { &MmapRangeLocal(ptr) }
		range_end := range_local.base + range_local.length
		if base < range_end && end > range_local.base {
			return false
		}
	}
	return true
}

fn overlap_length(first_base u64, first_length u64, second_base u64, second_length u64) u64 {
	first_end := first_base + first_length
	second_end := second_base + second_length
	start := if first_base > second_base { first_base } else { second_base }
	end := if first_end < second_end { first_end } else { second_end }
	return if end > start { end - start } else { 0 }
}

fn address_space_bytes_unlocked(pagemap &memory.Pagemap, process &proc.Process) u64 {
	mut total := u64(0)
	for ptr in pagemap.mmap_ranges {
		range_local := unsafe { &MmapRangeLocal(ptr) }
		mut charged := range_local.length
		if range_local.flags & map_brk_reservation != 0 {
			if process.brk_base == 0 || process.brk_current <= process.brk_base {
				charged = 0
			} else {
				charged = overlap_length(range_local.base, range_local.length, process.brk_base, lib.align_up(process.brk_current - process.brk_base, page_size))
			}
		}
		if charged > u64(-1) - total {
			return u64(-1)
		}
		total += charged
	}
	return total
}

fn charged_overlap(range_local &MmapRangeLocal, process &proc.Process, base u64, length u64) u64 {
	if range_local.flags & map_brk_reservation == 0 {
		return overlap_length(range_local.base, range_local.length, base, length)
	}
	if process.brk_base == 0 || process.brk_current <= process.brk_base {
		return 0
	}
	heap_length := lib.align_up(process.brk_current - process.brk_base, page_size)
	heap_overlap_base := if range_local.base > process.brk_base {
		range_local.base
	} else {
		process.brk_base
	}
	heap_end := if range_local.base + range_local.length < process.brk_base + heap_length {
		range_local.base + range_local.length
	} else {
		process.brk_base + heap_length
	}
	if heap_end <= heap_overlap_base {
		return 0
	}
	return overlap_length(heap_overlap_base, heap_end - heap_overlap_base, base, length)
}

pub fn address_space_bytes(pagemap &memory.Pagemap, process &proc.Process) u64 {
	mut locked := unsafe { pagemap }
	locked.l.acquire()
	defer { locked.l.release() }
	return address_space_bytes_unlocked(pagemap, process)
}

fn mapping_fits_address_limit(pagemap &memory.Pagemap, process &proc.Process, base u64, length u64, replacing bool, charged_length u64, credit u64) bool {
	limit := proc.soft_limit(process, proc.rlimit_as)
	if limit == proc.rlim_infinity {
		return true
	}
	mut current := address_space_bytes_unlocked(pagemap, process)
	if credit < current {
		current -= credit
	} else {
		current = 0
	}
	if replacing {
		for ptr in pagemap.mmap_ranges {
			range_local := unsafe { &MmapRangeLocal(ptr) }
			replaced := charged_overlap(range_local, process, base, length)
			if replaced < current {
				current -= replaced
			} else {
				current = 0
			}
		}
	}
	return charged_length <= limit && current <= limit - charged_length
}

// Find a hole at or above start. The guard page retained between ordinary
// allocations matches the old monotonic mmap cursor's behaviour.
fn find_free_base_unlocked(pagemap &memory.Pagemap, start u64, length u64) ?u64 {
	mut base := lib.align_up(start, page_size)
	for {
		if base + length < base {
			errno.set(errno.enomem)
			return none
		}
		mut next := u64(0)
		for ptr in pagemap.mmap_ranges {
			range_local := unsafe { &MmapRangeLocal(ptr) }
			range_end := range_local.base + range_local.length
			if base < range_end && base + length > range_local.base && range_end > next {
				next = range_end
			}
		}
		if next == 0 {
			return base
		}
		base = lib.align_up(next + page_size, page_size)
	}
	return none
}

pub fn delete_pagemap(mut pagemap memory.Pagemap) ? {
	pagemap.l.acquire()

	// munmap_unlocked() removes entries from pagemap.mmap_ranges. Always consume
	// the current first entry instead of iterating a shallow copy of the array:
	// deleting while iterating that copy skipped ranges, retained stale pointers,
	// and then freed the same backing allocation twice.
	for pagemap.mmap_ranges.len != 0 {
		local_range := unsafe { &MmapRangeLocal(pagemap.mmap_ranges[0]) }
		old_len := pagemap.mmap_ranges.len
		munmap_unlocked(mut pagemap, voidptr(local_range.base), local_range.length) or {
			pagemap.l.release()
			return none
		}
		if pagemap.mmap_ranges.len >= old_len {
			pagemap.l.release()
			errno.set(errno.einval)
			return none
		}
	}

	top_level := pagemap.top_level
	pagemap.l.release()

	unsafe {
		pagemap.mmap_ranges.free()
	}
	memory.pmm_free(top_level, 1)
	unsafe { free(pagemap) }
}

pub fn fork_pagemap(_old_pagemap &memory.Pagemap) ?&memory.Pagemap {
	memory.register_cow_resolver(resolve_cow_fault)
	mut old_pagemap := unsafe { _old_pagemap }
	mut new_pagemap := memory.new_pagemap()
	mut old_private_globals := []voidptr{}
	mut new_private_globals := []&MmapRangeGlobal{}
	defer {
		unsafe {
			old_private_globals.free()
			new_private_globals.free()
		}
	}

	old_pagemap.l.acquire()
	defer {
		old_pagemap.l.release()
	}

	for ptr in old_pagemap.mmap_ranges {
		mut local_range := unsafe { &MmapRangeLocal(ptr) }
		mut global_range := local_range.global

		mut new_local_range := &MmapRangeLocal{
			pagemap: unsafe { nil }
			global: unsafe { nil }
		}
		unsafe {
			*new_local_range = *local_range
		}
		new_local_range.pagemap = new_pagemap

		if local_range.flags & map_shared != 0 {
			global_range.locals << new_local_range
			for i := local_range.base; i < local_range.base + local_range.length; i += page_size {
				old_pte := old_pagemap.virt2pte(i, false) or { continue }
				new_pte := new_pagemap.virt2pte(i, true) or { return none }
				unsafe {
					*new_pte = *old_pte
				}
			}
		} else {
			// Private resident pages start shared and read-only in both address
			// spaces.  Their original writable protection remains in the range;
			// the write-fault path uses it to distinguish COW from a real fault.
			local_range.cow = true
			new_local_range.cow = true
			mut new_global_range := &MmapRangeGlobal(unsafe { nil })
			global_index := old_private_globals.index(voidptr(global_range))
			if global_index >= 0 {
				new_global_range = new_private_globals[global_index]
			} else {
				new_global_range = &MmapRangeGlobal{
					resource: global_range.resource
					handle: global_range.handle
					handle_ref: global_range.handle_ref
					handle_unref: global_range.handle_unref
					base: global_range.base
					length: global_range.length
					offset: global_range.offset
					pte_extra: global_range.pte_extra
					locals: []&MmapRangeLocal{}
					shadow_pagemap: memory.Pagemap{
						top_level: unsafe { &u64(0) }
					}
				}
				new_global_range.shadow_pagemap.top_level = &u64(memory.pmm_alloc(1))
				if new_global_range.handle != unsafe { nil }
					&& new_global_range.handle_ref != unsafe { nil } {
					new_global_range.handle_ref(new_global_range.handle)
				}
				old_private_globals << voidptr(global_range)
				new_private_globals << new_global_range
			}
			new_local_range.global = new_global_range
			new_global_range.locals << new_local_range

			for i := local_range.base; i < local_range.base + local_range.length; i += page_size {
				old_pte := old_pagemap.virt2pte(i, false) or { continue }
				if unsafe { *old_pte } & 1 == 0 {
					continue
				}
				phys := unsafe { *old_pte } & memory.pte_flags_mask
				if !memory.pmm_retain(voidptr(phys), 1) {
					return none
				}
				new_pte := new_pagemap.virt2pte(i, true) or { return none }
				new_spte := new_global_range.shadow_pagemap.virt2pte(i, true) or { return none }
				unsafe {
					*new_pte = *old_pte
					*new_spte = *new_pte
				}
				cow_flags := page_table_flags(local_range.prot, global_range.pte_extra, false)
				old_pagemap.flag_page(i, cow_flags) or { return none }
				new_pagemap.flag_page(i, cow_flags) or { return none }
			}
		}

		new_pagemap.mmap_ranges << voidptr(new_local_range)
	}

	return new_pagemap
}

fn page_table_flags(prot int, extra u64, writable bool) u64 {
	mut flags := memory.pte_present | extra
	if prot != prot_none {
		flags |= memory.pte_user
	}
	if writable && prot & prot_write != 0 {
		flags |= memory.pte_writable
	}
	if prot & prot_exec == 0 {
		flags |= memory.pte_noexec
	}
	return flags
}

pub fn map_page_in_range(_g &MmapRangeGlobal, virt_addr u64, phys_addr u64, prot int) ? {
	mut g := unsafe { _g }

	// Shadow pagemap always gets full access (kernel tracking only)
	shadow_flags := memory.pte_present | memory.pte_writable | memory.pte_noexec
	g.shadow_pagemap.map_page(virt_addr, phys_addr, shadow_flags) or { return none }

	// Process pagemap: PROT_NONE → no pte_user (EL0 cannot access).
	// Page remains valid (EL1 can still access) so flag_page can
	// extract the physical address later if mprotect restores access.
	pt_flags := page_table_flags(prot, g.pte_extra, true)

	for i := u64(0); i < g.locals.len; i++ {
		mut l := g.locals[i]
		if virt_addr < l.base || virt_addr >= l.base + l.length {
			continue
		}
		l.pagemap.map_page(virt_addr, phys_addr, pt_flags) or { return none }
	}
}

// Resolve a write to a private page shared by fork().  A range retains its
// requested PROT_WRITE bit while its PTE is read-only, so no software-only PTE
// bit is needed and both architectures use exactly the same state machine.
pub fn resolve_cow_fault(_pagemap &memory.Pagemap, address u64) bool {
	mut pagemap := unsafe { _pagemap }
	virt := lib.align_down(address, page_size)
	pagemap.l.acquire()
	defer { pagemap.l.release() }

	mut local_range, _, _ := addr2range(pagemap, virt) or { return false }
	if !local_range.cow || local_range.flags & map_shared != 0
		|| local_range.prot & prot_write == 0 {
		return false
	}
	old_phys := pagemap.virt2phys(virt) or { return false }
	flags := page_table_flags(local_range.prot, local_range.global.pte_extra, true)
	if memory.pmm_refcount(voidptr(old_phys)) <= 1 {
		pagemap.flag_page(virt, flags) or { return false }
		return true
	}

	new_page := memory.pmm_alloc_nozero_fallible(1)
	if new_page == unsafe { nil } {
		return false
	}
	unsafe {
		C.memcpy(voidptr(u64(new_page) + higher_half), voidptr(old_phys + higher_half), page_size)
	}
	shadow_flags := memory.pte_present | memory.pte_writable | memory.pte_noexec
	local_range.global.shadow_pagemap.map_page(virt, u64(new_page), shadow_flags) or {
		memory.pmm_free(new_page, 1)
		return false
	}
	pagemap.map_page_unlocked(virt, u64(new_page), flags) or {
		memory.pmm_free(new_page, 1)
		return false
	}
	memory.pmm_free(voidptr(old_phys), 1)
	return true
}

pub fn map_range(mut pagemap memory.Pagemap, _virt_addr u64, phys_addr u64, _length u64, prot int, _flags int) ? {
	flags := _flags | map_anonymous

	virt_addr := lib.align_down(_virt_addr, page_size)
	length := lib.align_up(_length + (_virt_addr - virt_addr), page_size)

	mut range_local := &MmapRangeLocal{
		pagemap: unsafe { pagemap }
		base: virt_addr
		length: length
		prot: prot
		flags: flags
		global: unsafe { nil }
	}

	mut range_global := &MmapRangeGlobal{
		locals: []&MmapRangeLocal{}
		base: virt_addr
		length: length
		resource: unsafe { nil }
		shadow_pagemap: memory.Pagemap{
			top_level: unsafe { &u64(0) }
		}
	}

	range_local.global = range_global

	range_global.locals << range_local
	range_global.shadow_pagemap.top_level = &u64(memory.pmm_alloc(1))

	pagemap.l.acquire()
	pagemap.mmap_ranges << voidptr(range_local)
	pagemap.l.release()

	for i := u64(0); i < length; i += page_size {
		map_page_in_range(range_global, virt_addr + i, phys_addr + i, prot) or { return none }
	}
}

// map_pages creates one virtual range backed by an arbitrary list of physical
// pages. Large executable images do not require physically contiguous RAM;
// keeping one range also lets munmap/mprotect treat the mapping normally.
pub fn map_pages(mut pagemap memory.Pagemap, virt_addr u64, phys_pages []u64, prot int, _flags int) ? {
	if phys_pages.len == 0 || virt_addr != lib.align_down(virt_addr, page_size) {
		return none
	}

	flags := _flags | map_anonymous
	length := u64(phys_pages.len) * page_size
	mut range_local := &MmapRangeLocal{
		pagemap: unsafe { pagemap }
		base: virt_addr
		length: length
		prot: prot
		flags: flags
		global: unsafe { nil }
	}
	mut range_global := &MmapRangeGlobal{
		locals: []&MmapRangeLocal{}
		base: virt_addr
		length: length
		resource: unsafe { nil }
		shadow_pagemap: memory.Pagemap{
			top_level: unsafe { &u64(0) }
		}
	}

	range_local.global = range_global
	range_global.locals << range_local
	range_global.shadow_pagemap.top_level = &u64(memory.pmm_alloc(1))

	pagemap.l.acquire()
	pagemap.mmap_ranges << voidptr(range_local)
	pagemap.l.release()

	for i, phys in phys_pages {
		map_page_in_range(range_global, virt_addr + u64(i) * page_size, phys, prot) or {
			return none
		}
	}
}

pub fn mmap(_pagemap &memory.Pagemap, addr voidptr, _length u64, prot int, flags int, _resource &resource.Resource, offset i64, handle voidptr, handle_ref fn (voidptr), handle_unref fn (voidptr)) ?voidptr {
	return mmap_with_credit(_pagemap, addr, _length, prot, flags, _resource, offset, handle, handle_ref, handle_unref, 0)
}

// mremap builds the destination before dropping the source. Credit the bytes
// which the same operation is about to unmap so RLIMIT_AS applies to its final
// footprint instead of the harmless temporary overlap.
fn mmap_with_credit(_pagemap &memory.Pagemap, addr voidptr, _length u64, prot int, flags int, _resource &resource.Resource, offset i64, handle voidptr, handle_ref fn (voidptr), handle_unref fn (voidptr), limit_credit u64) ?voidptr {
	mut pagemap := unsafe { _pagemap }
	mut resource_ := unsafe { _resource }

	if _length == 0 {
		C.printf(c'mmap: length is 0\n')
		errno.set(errno.einval)
		return none
	}
	if flags & map_anonymous == 0 && (offset < 0 || offset % i64(page_size) != 0) {
		errno.set(errno.einval)
		return none
	}

	length := lib.align_up(_length, page_size)
	fixed := flags & map_fixed != 0
	fixed_noreplace := flags & map_fixed_noreplace != 0
	user_limit := memory.user_address_limit()
	requested := u64(addr)
	if (fixed || fixed_noreplace)
		&& (requested >= user_limit || length > user_limit - requested) {
		errno.set(errno.enomem)
		return none
	}

	if flags & map_anonymous == 0 && resource_.can_mmap == false {
		errno.set(errno.enodev)
		return none
	}

	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	mut base := u64(0)
	mut hint := lib.align_down(requested, page_size)
	if !fixed && !fixed_noreplace
		&& (hint >= user_limit || length > user_limit - hint) {
		hint = 0
	}
	if (fixed || fixed_noreplace) && (u64(addr) == 0 || u64(addr) != hint) {
		errno.set(errno.einval)
		return none
	}

	mut range_local := &MmapRangeLocal{
		pagemap: pagemap
		base: base
		length: length
		offset: offset
		prot: prot
		flags: flags
		global: unsafe { nil }
	}

	// Device memory (framebuffers) needs uncached mapping on ARM64 so
	// writes reach physical RAM instead of staying in CPU cache.
	mut extra_pte := u64(0)
	if flags & map_anonymous == 0 && voidptr(resource_) != unsafe { nil }
		&& is_uncached_resource(voidptr(resource_)) {
		extra_pte = memory.pte_uncached
		// Device memory mapped with Non-Cacheable attribute
	}
	mut range_handle := voidptr(0)
	if flags & map_anonymous == 0 {
		range_handle = handle
	}

	mut range_global := &MmapRangeGlobal{
		locals: []&MmapRangeLocal{}
		base: base
		length: length
		resource: resource_
		handle: range_handle
		handle_ref: handle_ref
		handle_unref: handle_unref
		offset: offset
		pte_extra: extra_pte
		shadow_pagemap: memory.Pagemap{
			top_level: unsafe { &u64(0) }
		}
	}

	range_local.global = range_global

	range_global.locals << range_local
	range_global.shadow_pagemap.top_level = &u64(memory.pmm_alloc(1))

	// Choose and claim the virtual span as one locked operation. Wine first
	// probes preferred PE addresses with MAP_FIXED_NOREPLACE, while POSIX mmap
	// callers commonly pass the same addresses as best-effort hints.
	pagemap.l.acquire()
	charged_length := if flags & map_brk_reservation != 0 { u64(0) } else { length }
	if fixed_noreplace {
		base = hint
		if !range_is_free_unlocked(pagemap, base, length) {
			pagemap.l.release()
			memory.pmm_free(range_global.shadow_pagemap.top_level, 1)
			unsafe {
				range_global.locals.free()
				free(range_global)
				free(range_local)
			}
			errno.set(errno.eexist)
			return none
		}
		if voidptr(pagemap) == voidptr(process.pagemap)
			&& !mapping_fits_address_limit(pagemap, process, base, length, false, charged_length, limit_credit) {
			pagemap.l.release()
			memory.pmm_free(range_global.shadow_pagemap.top_level, 1)
			unsafe {
				range_global.locals.free()
				free(range_global)
				free(range_local)
			}
			errno.set(errno.enomem)
			return none
		}
	} else if fixed {
		base = u64(addr)
		if voidptr(pagemap) == voidptr(process.pagemap)
			&& !mapping_fits_address_limit(pagemap, process, base, length, true, charged_length, limit_credit) {
			pagemap.l.release()
			memory.pmm_free(range_global.shadow_pagemap.top_level, 1)
			unsafe {
				range_global.locals.free()
				free(range_global)
				free(range_local)
			}
			errno.set(errno.enomem)
			return none
		}
		munmap_unlocked(mut pagemap, addr, length) or {
			pagemap.l.release()
			memory.pmm_free(range_global.shadow_pagemap.top_level, 1)
			unsafe {
				range_global.locals.free()
				free(range_global)
				free(range_local)
			}
			return none
		}
	} else if hint != 0 && range_is_free_unlocked(pagemap, hint, length) {
		base = hint
	} else {
		base = find_free_base_unlocked(pagemap, process.mmap_anon_non_fixed_base, length) or {
			pagemap.l.release()
			memory.pmm_free(range_global.shadow_pagemap.top_level, 1)
			unsafe {
				range_global.locals.free()
				free(range_global)
				free(range_local)
			}
			return none
		}
		process.mmap_anon_non_fixed_base = base + length + page_size
	}
	if !fixed && voidptr(pagemap) == voidptr(process.pagemap)
		&& !mapping_fits_address_limit(pagemap, process, base, length, false, charged_length, limit_credit) {
		pagemap.l.release()
		memory.pmm_free(range_global.shadow_pagemap.top_level, 1)
		unsafe {
			range_global.locals.free()
			free(range_global)
			free(range_local)
		}
		errno.set(errno.enomem)
		return none
	}
	range_local.base = base
	range_global.base = base
	pagemap.mmap_ranges << voidptr(range_local)
	pagemap.l.release()

	if range_handle != unsafe { nil } && handle_ref != unsafe { nil } {
		handle_ref(range_handle)
	}

	// PROT_NONE and large anonymous mappings are address-space reservations, not
	// committed memory. Large runtimes reserve far more virtual memory than they
	// will ever touch, so let the page-fault path commit accessible pages on
	// demand. mprotect() commits a PROT_NONE subset before making it accessible.
	//
	// Pre-fault smaller and file-backed mappings to avoid demand-paging faults.
	// On QEMU+HVF, LDP/STP instructions on unmapped pages cause data aborts
	// without ISV bit set, which crashes HVF.
	lazy_anonymous := flags & map_anonymous != 0 && length >= lazy_anonymous_threshold
	if prot != prot_none && !lazy_anonymous {
		for i := u64(0); i < length; i += page_size {
			mut page := unsafe { nil }
			if flags & map_anonymous != 0 {
				page = memory.pmm_alloc(1)
			} else if voidptr(resource_) != unsafe { nil } {
				file_page := u64((offset + i64(i)) / i64(page_size))
				page = resource_.mmap(handle, file_page, flags)
			}
			if flags & map_anonymous == 0 && page == unsafe { nil } {
				munmap(mut pagemap, voidptr(base), length) or {}
				errno.set(errno.einval)
				return none
			}
			if page != unsafe { nil } {
				map_page_in_range(range_global, base + i, u64(page), prot) or {
					if flags & map_anonymous != 0 {
						memory.pmm_free(page, 1)
					} else {
						resource.release_mapping(mut resource_, handle, u64((offset + i64(i)) / i64(page_size)), page, flags)
					}
					munmap(mut pagemap, voidptr(base), length) or {}
					errno.set(errno.enomem)
					return none
				}
			}
		}
	}

	return voidptr(base)
}

pub fn syscall_munmap(_ voidptr, addr voidptr, length u64) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: munmap(0x%llx, 0x%llx)\n', process.name.str, addr, length)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	munmap(mut process.pagemap, addr, length) or { return errno.err, errno.get() }

	return 0, 0
}

pub fn syscall_mprotect(_ voidptr, addr voidptr, length u64, prot int) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	mprotect(mut process.pagemap, addr, length, prot) or { return errno.err, errno.get() }

	return 0, 0
}

// Synchronize shared file mappings. Without an asynchronous writeback worker,
// MS_ASYNC is conservatively completed before return just like MS_SYNC.
pub fn syscall_msync(_ voidptr, addr u64, _length u64, flags int) (u64, u64) {
	if addr % page_size != 0 || flags & ~(ms_async | ms_invalidate | ms_sync) != 0
		|| (flags & ms_async != 0 && flags & ms_sync != 0) {
		return errno.err, errno.einval
	}
	if _length == 0 {
		return 0, 0
	}
	length := lib.align_up(_length, page_size)
	if length < _length || addr >= memory.user_address_limit()
		|| length > memory.user_address_limit() - addr {
		return errno.err, errno.enomem
	}

	mut pagemap := proc.current_thread().process.pagemap
	pagemap.l.acquire()
	defer { pagemap.l.release() }
	mut current := addr
	end := addr + length
	for current < end {
		local_range, _, _ := addr2range(pagemap, current) or {
			return errno.err, errno.enomem
		}
		range_end := if local_range.base + local_range.length < end {
			local_range.base + local_range.length
		} else {
			end
		}
		if local_range.flags & map_shared != 0
			&& local_range.flags & map_anonymous == 0 {
			mut res := local_range.global.resource
			file_offset := u64(local_range.offset) + (current - local_range.base)
			resource.sync_mapping(mut res, local_range.global.handle, file_offset, range_end - current) or { return errno.err, errno.get() }
		}
		current = range_end
	}
	return 0, 0
}

pub fn mprotect(mut pagemap memory.Pagemap, addr voidptr, len u64, prot int) ? {
	// mmap() deliberately leaves PROT_NONE reservations without physical pages.
	// ARM64 HVF cannot reliably resume every paired load/store page fault, so
	// populate pages here, before an application can touch a newly accessible
	// part of the reservation.
	if prot != prot_none {
		populate_missing_pages(mut pagemap, u64(addr), len, prot)?
	}

	pagemap.l.acquire()
	defer {
		pagemap.l.release()
	}

	mprotect_unlocked(mut pagemap, addr, len, prot)?
}

fn populate_missing_pages(mut pagemap memory.Pagemap, address u64, _length u64, prot int) ? {
	length := lib.align_up(_length, page_size)
	for virt := address; virt < address + length; virt += page_size {
		pagemap.l.acquire()
		local_range, _, file_page := addr2range(pagemap, virt) or {
			pagemap.l.release()
			errno.set(errno.enomem)
			return none
		}
		if _ := pagemap.virt2phys(virt) {
			pagemap.l.release()
			continue
		}

		flags := local_range.flags
		global_range := local_range.global
		mut resource_ := global_range.resource
		handle := global_range.handle
		pagemap.l.release()

		mut page := unsafe { nil }
		if flags & map_anonymous != 0 {
			page = memory.pmm_alloc(1)
		} else if voidptr(resource_) != unsafe { nil } {
			page = resource_.mmap(handle, file_page, flags)
		}
		if page == unsafe { nil } {
			errno.set(errno.enomem)
			return none
		}
		map_page_in_range(global_range, virt, u64(page), prot) or {
			if flags & map_anonymous != 0 {
				memory.pmm_free(page, 1)
			} else {
				mut res := global_range.resource
				resource.release_mapping(mut res, handle, file_page, page, flags)
			}
			errno.set(errno.enomem)
			return none
		}
	}
}

pub fn mprotect_unlocked(mut pagemap memory.Pagemap, addr voidptr, _length u64, prot int) ? {
	if _length == 0 {
		C.printf(c'mprotect: length is 0\n')
		errno.set(errno.einval)
		return none
	}

	length := lib.align_up(_length, page_size)

	mut i := u64(addr)
	for i < u64(addr) + length {
		mut local_range, _, _ := addr2range(pagemap, i) or {
			i += page_size
			continue
		}

		mut global_range := local_range.global

		if local_range.prot == prot {
			i += page_size
			continue
		}

		snip_begin := i
		for {
			i += page_size
			if i >= local_range.base + local_range.length || i >= u64(addr) + length {
				break
			}
		}
		snip_end := i
		snip_size := snip_end - snip_begin

		if snip_begin > local_range.base && snip_end < local_range.base + local_range.length {
			// Create new range for portion after snip
			mut postsplit_range := &MmapRangeLocal{
				pagemap: local_range.pagemap
				base: snip_end
				length: (local_range.base + local_range.length) - snip_end
				offset: local_range.offset + i64(snip_end - local_range.base)
				prot: local_range.prot
				flags: local_range.flags
				cow: local_range.cow
				global: local_range.global
			}
			global_range.locals << postsplit_range
			pagemap.mmap_ranges << postsplit_range
			local_range.length -= postsplit_range.length
		}

		for j := snip_begin; j < snip_end; j += page_size {
			mut writable := true
			if local_range.cow && prot & prot_write != 0 {
				phys := pagemap.virt2phys(j) or { u64(0) }
				writable = phys == 0 || memory.pmm_refcount(voidptr(phys)) <= 1
			}
			pt_flags := page_table_flags(prot, global_range.pte_extra, writable)
			pagemap.flag_page(j, pt_flags) or {}
		}

		if snip_size == local_range.length {
			local_range.prot = prot
		} else {
			new_offset := local_range.offset + i64(snip_begin - local_range.base)

			if snip_begin == local_range.base {
				local_range.offset += i64(snip_size)
				local_range.base = snip_end
			}
			local_range.length -= snip_size

			mut new_range := &MmapRangeLocal{
				pagemap: local_range.pagemap
				base: snip_begin
				length: snip_size
				offset: new_offset
				prot: prot
				flags: local_range.flags
				cow: local_range.cow
				global: local_range.global
			}
			global_range.locals << new_range
			pagemap.mmap_ranges << new_range
		}
	}
}

pub fn munmap(mut pagemap memory.Pagemap, addr voidptr, len u64) ? {
	pagemap.l.acquire()
	defer {
		pagemap.l.release()
	}

	munmap_unlocked(mut pagemap, addr, len)?
}

pub fn munmap_unlocked(mut pagemap memory.Pagemap, addr voidptr, _length u64) ? {
	if _length == 0 {
		C.printf(c'munmap: length is 0\n')
		errno.set(errno.einval)
		return none
	}

	length := lib.align_up(_length, page_size)

	mut i := u64(addr)
	for i < u64(addr) + length {
		mut local_range, _, _ := addr2range(pagemap, i) or {
			i += page_size
			continue
		}

		mut global_range := local_range.global

		snip_begin := i
		for {
			i += page_size
			if i >= local_range.base + local_range.length || i >= u64(addr) + length {
				break
			}
		}
		snip_end := i
		snip_size := snip_end - snip_begin

		if snip_begin > local_range.base && snip_end < local_range.base + local_range.length {
			// Create new range for portion after snip
			mut postsplit_range := &MmapRangeLocal{
				pagemap: local_range.pagemap
				base: snip_end
				length: (local_range.base + local_range.length) - snip_end
				offset: local_range.offset + i64(snip_end - local_range.base)
				prot: local_range.prot
				flags: local_range.flags
				cow: local_range.cow
				global: local_range.global
			}
			global_range.locals << postsplit_range
			pagemap.mmap_ranges << postsplit_range
			local_range.length -= postsplit_range.length
		}

		for j := snip_begin; j < snip_end; j += page_size {
			pagemap.unmap_page_unlocked(j) or {}
		}

		if snip_size == local_range.length {
			if global_range.locals.len == 1 {
				if local_range.flags & map_anonymous != 0 {
					for j := global_range.base; j < global_range.base + global_range.length; j += page_size {
						phys := global_range.shadow_pagemap.virt2phys(j) or { continue }
						global_range.shadow_pagemap.unmap_page(j) or {
							errno.set(errno.einval)
							return none
						}
						memory.pmm_free(voidptr(phys), 1)
					}
				} else {
					mut res := global_range.resource
					for j := global_range.base; j < global_range.base + global_range.length; j += page_size {
						phys := global_range.shadow_pagemap.virt2phys(j) or { continue }
						global_range.shadow_pagemap.unmap_page(j) or {
							errno.set(errno.einval)
							return none
						}
						file_page := u64(global_range.offset) / page_size + (j - global_range.base) / page_size
						resource.release_mapping(mut res, global_range.handle, file_page, voidptr(phys), local_range.flags)
					}
				}
				memory.pmm_free(global_range.shadow_pagemap.top_level, 1)
				if global_range.handle != unsafe { nil }
					&& global_range.handle_unref != unsafe { nil } {
					global_range.handle_unref(global_range.handle)
				}
				unsafe {
					global_range.locals.free()
					free(global_range)
				}
			} else {
				global_range.locals.delete(global_range.locals.index(local_range))
			}
			pagemap.mmap_ranges.delete(pagemap.mmap_ranges.index(local_range))
			unsafe { free(local_range) }
		} else {
			if snip_begin == local_range.base {
				local_range.offset += i64(snip_size)
				local_range.base = snip_end
			}
			local_range.length -= snip_size
		}
	}
}
