// mmap.v: mmap() implementation.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

module mmap

import memory
import resource
import proc
import errno
import x86.cpu
import x86.cpu.local as cpulocal
import lib

pub const (
	prot_none     = 0x00
	prot_read     = 0x01
	prot_write    = 0x02
	prot_exec     = 0x04
	map_private   = 0x01
	map_shared    = 0x02
	map_fixed     = 0x04
	map_anon      = 0x08
	map_anonymous = 0x08
)

pub struct MmapRangeLocal {
pub mut:
	pagemap &memory.Pagemap  = unsafe { nil }
	global  &MmapRangeGlobal = unsafe { nil }
	base    u64
	length  u64
	offset  i64
	prot    int
	flags   int
}

pub struct MmapRangeGlobal {
pub mut:
	shadow_pagemap memory.Pagemap
	locals         []&MmapRangeLocal
	resource       &resource.Resource = unsafe { nil }
	base           u64
	length         u64
	offset         i64
}

pub fn list_ranges(pagemap &memory.Pagemap) {
	C.printf(c'Ranges for %llx:\n', voidptr(pagemap))
	for i := u64(0); i < pagemap.mmap_ranges.len; i++ {
		r := unsafe { &MmapRangeLocal(pagemap.mmap_ranges[i]) }
		C.printf(c'\tBase: 0x%llx\tLength: 0x%llx\tOffset: 0x%llx\n', r.base, r.length,
			r.offset)
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

pub fn delete_pagemap(_pagemap &memory.Pagemap) ? {
	mut pagemap := unsafe { _pagemap }

	pagemap.l.acquire()

	for ptr in pagemap.mmap_ranges {
		local_range := unsafe { &MmapRangeLocal(ptr) }

		munmap(pagemap, voidptr(local_range.base), local_range.length) or { return none }
	}

	unsafe { free(pagemap) }
}

pub fn fork_pagemap(_old_pagemap &memory.Pagemap) ?&memory.Pagemap {
	mut old_pagemap := unsafe { _old_pagemap }
	mut new_pagemap := memory.new_pagemap()

	old_pagemap.l.acquire()
	defer {
		old_pagemap.l.release()
	}

	for ptr in old_pagemap.mmap_ranges {
		local_range := unsafe { &MmapRangeLocal(ptr) }
		mut global_range := local_range.global

		mut new_local_range := &MmapRangeLocal{
			pagemap: unsafe { nil }
			global: unsafe { nil }
		}
		unsafe {
			new_local_range[0] = local_range[0]
		}
		if voidptr(global_range.resource) != unsafe { nil } {
			global_range.resource.refcount++
		}

		if local_range.flags & mmap.map_shared != 0 {
			global_range.locals << new_local_range
			for i := local_range.base; i < local_range.base + local_range.length; i += page_size {
				old_pte := old_pagemap.virt2pte(i, false) or { continue }
				new_pte := new_pagemap.virt2pte(i, true) or { return none }
				unsafe {
					new_pte[0] = old_pte[0]
				}
			}
		} else {
			mut new_global_range := &MmapRangeGlobal{
				resource: unsafe { nil }
				shadow_pagemap: memory.Pagemap{
					top_level: &u64(0)
				}
			}

			new_global_range.resource = global_range.resource
			new_global_range.base = global_range.base
			new_global_range.length = global_range.length
			new_global_range.offset = global_range.offset

			new_global_range.locals = []&MmapRangeLocal{}
			new_global_range.locals << new_local_range

			new_global_range.shadow_pagemap.top_level = &u64(memory.pmm_alloc(1))

			if local_range.flags & mmap.map_anonymous != 0 {
				for i := local_range.base; i < local_range.base + local_range.length; i += page_size {
					old_pte := old_pagemap.virt2pte(i, false) or { continue }
					if unsafe { old_pte[0] & 1 } == 0 {
						continue
					}
					new_pte := new_pagemap.virt2pte(i, true) or { return none }
					new_spte := new_global_range.shadow_pagemap.virt2pte(i, true) or { return none }
					page := memory.pmm_alloc_nozero(1)
					unsafe {
						C.memcpy(voidptr(u64(page) + higher_half), voidptr(
							(old_pte[0] & ~(u64(0xfff))) + higher_half), page_size)
						new_pte[0] = (old_pte[0] & u64(0xfff)) | u64(page)
						new_spte[0] = new_pte[0]
					}
				}
			} else {
				panic('non anon fork')
			}
		}

		new_pagemap.mmap_ranges << voidptr(new_local_range)
	}

	return new_pagemap
}

pub fn map_page_in_range(_g &MmapRangeGlobal, virt_addr u64, phys_addr u64, prot int) ? {
	mut g := unsafe { _g }

	mut pt_flags := memory.pte_present | memory.pte_user
	if prot & mmap.prot_write != 0 {
		pt_flags |= memory.pte_writable
	}

	g.shadow_pagemap.map_page(virt_addr, phys_addr, pt_flags) or { return none }

	g.shadow_pagemap.map_page(virt_addr, phys_addr, pt_flags) or { return none }

	for i := u64(0); i < g.locals.len; i++ {
		mut l := g.locals[i]
		if virt_addr < l.base || virt_addr >= l.base + l.length {
			continue
		}
		l.pagemap.map_page(virt_addr, phys_addr, pt_flags) or { return none }
	}
}

pub fn map_range(_pagemap &memory.Pagemap, _virt_addr u64, phys_addr u64, _length u64, prot int, _flags int) ? {
	mut pagemap := unsafe { _pagemap }
	flags := _flags | mmap.map_anonymous

	virt_addr := lib.align_down(_virt_addr, page_size)
	length := lib.align_up(_length + (_virt_addr - virt_addr), page_size)

	mut range_local := &MmapRangeLocal{
		pagemap: pagemap
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
			top_level: &u64(0)
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

pub fn pf_handler(gpr_state &cpulocal.GPRState) ? {
	if gpr_state.err & 1 != 0 {
		// It was a protection violation, crash
		return none
	}

	mut current_thread := proc.current_thread()

	asm volatile amd64 {
		sti
	}
	defer {
		asm volatile amd64 {
			cli
		}
	}

	mut process := current_thread.process
	mut pagemap := process.pagemap

	addr := cpu.read_cr2()

	pagemap.l.acquire()

	mut range_local, memory_page, file_page := addr2range(pagemap, addr) or {
		pagemap.l.release()
		return none
	}

	pagemap.l.release()

	mut page := unsafe { nil }

	if range_local.flags & mmap.map_anonymous != 0 {
		page = memory.pmm_alloc(1)
	} else {
		page = range_local.global.resource.mmap(file_page, range_local.flags)
	}

	map_page_in_range(range_local.global, memory_page * page_size, u64(page), range_local.prot) or {
		return none
	}
}

pub fn mmap(_pagemap &memory.Pagemap, addr voidptr, _length u64, prot int, flags int, _resource &resource.Resource, offset i64) ?voidptr {
	mut pagemap := unsafe { _pagemap }
	mut resource_ := unsafe { _resource }

	if _length == 0 {
		C.printf(c'mmap: length is 0\n')
		errno.set(errno.einval)
		return none
	}

	length := lib.align_up(_length, page_size)

	if flags & mmap.map_anonymous == 0 && resource_.can_mmap == false {
		errno.set(errno.enodev)
		return none
	}

	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	mut base := u64(0)
	if flags & mmap.map_fixed != 0 {
		base = u64(addr)

		munmap(pagemap, voidptr(base), length)?
	} else {
		base = process.mmap_anon_non_fixed_base
		process.mmap_anon_non_fixed_base += length + page_size
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

	mut range_global := &MmapRangeGlobal{
		locals: []&MmapRangeLocal{}
		base: base
		length: length
		resource: resource_
		offset: offset
		shadow_pagemap: memory.Pagemap{
			top_level: &u64(0)
		}
	}

	range_local.global = range_global

	range_global.locals << range_local
	range_global.shadow_pagemap.top_level = &u64(memory.pmm_alloc(1))

	pagemap.l.acquire()
	pagemap.mmap_ranges << voidptr(range_local)
	pagemap.l.release()

	if voidptr(resource_) != unsafe { nil } {
		resource_.refcount++
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

	munmap(process.pagemap, addr, length) or { return errno.err, errno.get() }

	return 0, 0
}

pub fn syscall_mprotect(_ voidptr, addr voidptr, length u64, prot int) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: mprotect(0x%llx, 0x%llx, 0x%x)\n', process.name.str, addr,
		length, prot)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	mprotect(process.pagemap, addr, length, prot) or { return errno.err, errno.get() }

	return 0, 0
}

pub fn mprotect(_pagemap &memory.Pagemap, addr voidptr, _length u64, prot int) ? {
	mut pagemap := unsafe { _pagemap }

	if _length == 0 {
		C.printf(c'munmap: length is 0\n')
		errno.set(errno.einval)
		return none
	}

	length := lib.align_up(_length, page_size)

	for i := u64(addr); i < u64(addr) + length; i += page_size {
		mut local_range, _, _ := addr2range(pagemap, i) or { continue }

		if local_range.prot == prot {
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
				global: local_range.global
			}
			pagemap.mmap_ranges << postsplit_range
			local_range.length -= postsplit_range.length
		}

		for j := snip_begin; j < snip_end; j += page_size {
			mut pt_flags := memory.pte_present | memory.pte_user
			if prot & mmap.prot_write != 0 {
				pt_flags |= memory.pte_writable
			}
			pagemap.flag_page(j, pt_flags) or {}
		}

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
			global: local_range.global
		}
		pagemap.mmap_ranges << new_range
	}
}

pub fn munmap(_pagemap &memory.Pagemap, addr voidptr, _length u64) ? {
	mut pagemap := unsafe { _pagemap }

	if _length == 0 {
		C.printf(c'munmap: length is 0\n')
		errno.set(errno.einval)
		return none
	}

	length := lib.align_up(_length, page_size)

	for i := u64(addr); i < u64(addr) + length; i += page_size {
		mut local_range, _, _ := addr2range(pagemap, i) or { continue }

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
				global: local_range.global
			}
			pagemap.mmap_ranges << postsplit_range
			local_range.length -= postsplit_range.length
		}

		for j := snip_begin; j < snip_end; j += page_size {
			pagemap.unmap_page(j) or {}
		}

		if snip_size == local_range.length {
			pagemap.mmap_ranges.delete(pagemap.mmap_ranges.index(local_range))
		}

		if snip_size == local_range.length && global_range.locals.len == 1 {
			if local_range.flags & mmap.map_anonymous != 0 {
				for j := global_range.base; j < global_range.base + global_range.length; j += page_size {
					phys := global_range.shadow_pagemap.virt2phys(j) or { continue }
					global_range.shadow_pagemap.unmap_page(j) or {
						errno.set(errno.einval)
						return none
					}
					memory.pmm_free(voidptr(phys), 1)
				}
			} else {
				// global_range.resource.munmap(i)
			}
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
