// virtual.v: Virtual mapping management.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

module memory

import lib
import limine
import klock
import x86.cpu

fn C.text_start()
fn C.text_end()
fn C.rodata_start()
fn C.rodata_end()
fn C.data_start()
fn C.data_end()

pub const pte_present = u64(1) << 0
pub const pte_writable = u64(1) << 1
pub const pte_user = u64(1) << 2
pub const pte_noexec = u64(1) << 63
pub const pte_flags_mask = ~(u64(0xfff) | pte_present | pte_writable | pte_user | pte_noexec)

__global (
	page_size       = u64(0x1000)
	la57            = bool(false)
	kernel_pagemap  Pagemap
	vmm_initialised = bool(false)
)

pub struct Pagemap {
pub mut:
	l           klock.Lock
	top_level   &u64 = unsafe { nil }
	mmap_ranges []voidptr
}

fn C.get_kernel_end_addr() u64

pub fn new_pagemap() &Pagemap {
	mut top_level := &u64(pmm_alloc(1))
	if top_level == 0 {
		panic('new_pagemap() allocation failure')
	}

	// Import higher half from kernel pagemap
	mut p1 := &u64(u64(top_level) + higher_half)
	p2 := &u64(u64(kernel_pagemap.top_level) + higher_half)
	for i := u64(256); i < 512; i++ {
		unsafe {
			p1[i] = p2[i]
		}
	}
	return &Pagemap{
		top_level: top_level
		mmap_ranges: []voidptr{}
	}
}

pub fn (pagemap &Pagemap) virt2pte(virt u64, allocate bool) ?&u64 {
	pml5_entry := (virt & (u64(0x1ff) << 48)) >> 48
	pml4_entry := (virt & (u64(0x1ff) << 39)) >> 39
	pml3_entry := (virt & (u64(0x1ff) << 30)) >> 30
	pml2_entry := (virt & (u64(0x1ff) << 21)) >> 21
	pml1_entry := (virt & (u64(0x1ff) << 12)) >> 12

	pml5 := pagemap.top_level
	pml4 := if !la57 {
		pagemap.top_level
	} else {
		get_next_level(pml5, pml5_entry, allocate) or { return none }
	}
	pml3 := get_next_level(pml4, pml4_entry, allocate) or { return none }
	pml2 := get_next_level(pml3, pml3_entry, allocate) or { return none }
	pml1 := get_next_level(pml2, pml2_entry, allocate) or { return none }

	return unsafe { &u64(u64(&pml1[pml1_entry]) + higher_half) }
}

pub fn (pagemap &Pagemap) virt2phys(virt u64) ?u64 {
	pte_p := pagemap.virt2pte(virt, false) or { return none }
	if unsafe { *pte_p } & 1 == 0 {
		return none
	}
	return unsafe { *pte_p } & memory.pte_flags_mask
}

pub fn (mut pagemap Pagemap) switch_to() {
	top_level := pagemap.top_level

	asm volatile amd64 {
		mov cr3, top_level
		; ; r (top_level)
		; memory
	}
}

fn get_next_level(current_level &u64, index u64, allocate bool) ?&u64 {
	mut ret := &u64(0)

	mut entry := &u64(u64(current_level) + higher_half + index * 8)

	// Check if entry is present
	if unsafe { *entry } & 0x01 != 0 {
		// If present, return pointer to it
		ret = &u64(unsafe { *entry } & memory.pte_flags_mask)
	} else {
		if allocate == false {
			return none
		}

		// Else, allocate the page table
		ret = pmm_alloc(1)
		if ret == 0 {
			return none
		}
		unsafe {
			*entry = u64(ret) | 0b111
		}
	}
	return ret
}

pub fn (mut pagemap Pagemap) unmap_page(virt u64) ? {
	pml5_entry := (virt & (u64(0x1ff) << 48)) >> 48
	pml4_entry := (virt & (u64(0x1ff) << 39)) >> 39
	pml3_entry := (virt & (u64(0x1ff) << 30)) >> 30
	pml2_entry := (virt & (u64(0x1ff) << 21)) >> 21
	pml1_entry := (virt & (u64(0x1ff) << 12)) >> 12

	mut pml5 := pagemap.top_level
	mut pml5_p := unsafe { &u64(u64(pml5) + higher_half) }
	mut pml4 := if !la57 {
		pagemap.top_level
	} else {
		get_next_level(pml5, pml5_entry, false) or { return none }
	}
	mut pml4_p := unsafe { &u64(u64(pml4) + higher_half) }
	mut pml3 := get_next_level(pml4, pml4_entry, false) or { return none }
	mut pml3_p := unsafe { &u64(u64(pml3) + higher_half) }
	mut pml2 := get_next_level(pml3, pml3_entry, false) or { return none }
	mut pml2_p := unsafe { &u64(u64(pml2) + higher_half) }
	mut pml1 := get_next_level(pml2, pml2_entry, false) or { return none }
	mut pml1_p := unsafe { &u64(u64(pml1) + higher_half) }

	mut pte_p := unsafe { &u64(u64(&pml1[pml1_entry]) + higher_half) }

	unsafe {
		*pte_p = 0

		mut i := u64(0)
		for ; i < 512; i++ {
			if pml1_p[i] != 0 {
				break
			}
		}
		if i == 512 {
			pmm_free(pml1, 1)
			pml2_p[pml2_entry] = 0
		}

		i = u64(0)
		for ; i < 512; i++ {
			if pml2_p[i] != 0 {
				break
			}
		}
		if i == 512 {
			pmm_free(pml2, 1)
			pml3_p[pml3_entry] = 0
		}

		i = u64(0)
		for ; i < 512; i++ {
			if pml3_p[i] != 0 {
				break
			}
		}
		if i == 512 {
			pmm_free(pml3, 1)
			pml4_p[pml4_entry] = 0
		}
		if la57 {
			for ; i < 512; i++ {
				if pml4_p[i] != 0 {
					break
				}
			}
			if i == 512 {
				pmm_free(pml4, 1)
				pml5_p[pml5_entry] = 0
			}
		}
	}
	current_cr3 := cpu.read_cr3()
	if current_cr3 == u64(pagemap.top_level) {
		cpu.invlpg(virt)
	}
}

pub fn (mut pagemap Pagemap) flag_page(virt u64, flags u64) ? {
	pte_p := pagemap.virt2pte(virt, false) or { return none }

	unsafe {
		*pte_p &= memory.pte_flags_mask
	}
	unsafe {
		*pte_p |= flags
	}
	current_cr3 := cpu.read_cr3()
	if current_cr3 == u64(pagemap.top_level) {
		cpu.invlpg(virt)
	}
}

pub fn (mut pagemap Pagemap) map_page(virt u64, phys u64, flags u64) ? {
	pagemap.l.acquire()
	defer {
		pagemap.l.release()
	}

	pml5_entry := (virt & (u64(0x1ff) << 48)) >> 48
	pml4_entry := (virt & (u64(0x1ff) << 39)) >> 39
	pml3_entry := (virt & (u64(0x1ff) << 30)) >> 30
	pml2_entry := (virt & (u64(0x1ff) << 21)) >> 21
	pml1_entry := (virt & (u64(0x1ff) << 12)) >> 12

	pml5 := pagemap.top_level
	pml4 := if !la57 {
		pagemap.top_level
	} else {
		get_next_level(pml5, pml5_entry, true) or { return none }
	}
	pml3 := get_next_level(pml4, pml4_entry, true) or { return none }
	pml2 := get_next_level(pml3, pml3_entry, true) or { return none }
	mut pml1 := get_next_level(pml2, pml2_entry, true) or { return none }

	entry := &u64(u64(pml1) + higher_half + pml1_entry * 8)

	unsafe {
		*entry = phys | flags
	}
}

@[_linker_section: '.requests']
@[cinit]
__global (
	volatile kaddr_req       = limine.LimineKernelAddressRequest{
		response: unsafe { nil }
	}
	volatile memmap_req      = limine.LimineMemmapRequest{
		response: unsafe { nil }
	}
	volatile paging_mode_req = limine.LiminePagingModeRequest{
		response: unsafe { nil }
		revision: 1
		mode: limine.limine_paging_mode_x86_64_5lvl
		max_mode: limine.limine_paging_mode_x86_64_5lvl
		min_mode: limine.limine_paging_mode_x86_64_4lvl
	}
)

fn map_kernel_span(virt u64, phys u64, len u64, flags u64) {
	aligned_len := lib.align_up(len, page_size)

	print('vmm: Kernel: Mapping 0x${phys:x} to 0x${virt:x}, length: 0x${aligned_len:x}\n')

	for i := u64(0); i < aligned_len; i += page_size {
		kernel_pagemap.map_page(virt + i, phys + i, flags) or { panic('vmm init failure') }
	}
}

pub fn vmm_init() {
	if paging_mode_req.response != unsafe { nil } {
		if paging_mode_req.response.mode == limine.limine_paging_mode_x86_64_5lvl {
			print('vmm: Using 5 level paging\n')
			la57 = true
		}
	}

	kernel_pagemap.top_level = pmm_alloc(1)
	if kernel_pagemap.top_level == 0 {
		panic('vmm_init() allocation failure')
	}

	// Since the higher half has to be shared amongst all address spaces,
	// we need to initialise every single higher half PML3 so they can be
	// shared.
	for i := u64(256); i < 512; i++ {
		// get_next_level will allocate the PML3s for us.
		get_next_level(kernel_pagemap.top_level, i, true) or { panic('vmm init failure') }
	}

	// Map kernel
	if kaddr_req.response == unsafe { nil } {
		panic('Kernel address bootloader response missing')
	}
	print('vmm: Kernel physical base: 0x${kaddr_req.response.physical_base:x}\n')
	print('vmm: Kernel virtual base: 0x${kaddr_req.response.virtual_base:x}\n')
	virtual_base := kaddr_req.response.virtual_base
	physical_base := kaddr_req.response.physical_base

	// Map kernel text
	text_virt := u64(voidptr(C.text_start))
	text_phys := (text_virt - virtual_base) + physical_base
	text_len := u64(voidptr(C.text_end)) - text_virt
	map_kernel_span(text_virt, text_phys, text_len, memory.pte_present)

	// Map kernel rodata
	rodata_virt := u64(voidptr(C.rodata_start))
	rodata_phys := (rodata_virt - virtual_base) + physical_base
	rodata_len := u64(voidptr(C.rodata_end)) - rodata_virt
	map_kernel_span(rodata_virt, rodata_phys, rodata_len, memory.pte_present | memory.pte_noexec)

	// Map kernel data
	data_virt := u64(voidptr(C.data_start))
	data_phys := (data_virt - virtual_base) + physical_base
	data_len := u64(voidptr(C.data_end)) - data_virt
	map_kernel_span(data_virt, data_phys, data_len, memory.pte_present | memory.pte_noexec | memory.pte_writable)

	for i := u64(0); i < 0x100000000; i += page_size {
		kernel_pagemap.map_page(i + higher_half, i, memory.pte_present | memory.pte_noexec | memory.pte_writable) or {
			panic('vmm init failure')
		}
	}

	memmap := memmap_req.response

	entries := memmap.entries
	for i := 0; i < memmap.entry_count; i++ {
		base := unsafe { lib.align_down(entries[i].base, page_size) }
		top := unsafe { lib.align_up(entries[i].base + entries[i].length, page_size) }
		if top <= u64(0x100000000) {
			continue
		}
		for j := base; j < top; j += page_size {
			if j < u64(0x100000000) {
				continue
			}
			kernel_pagemap.map_page(j + higher_half, j, memory.pte_present | memory.pte_noexec | memory.pte_writable) or {
				panic('vmm init failure')
			}
		}
	}

	kernel_pagemap.switch_to()

	vmm_initialised = true
}
