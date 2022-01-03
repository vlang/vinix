module memory

import lib
import stivale2
import klock
import x86.cpu

pub const (
	pte_present = u64(1 << 0)
	pte_writable = u64(1 << 1)
	pte_user = u64(1 << 2)
)

__global (
	page_size       = u64(0x1000)
	higher_half     = u64(0xffff800000000000)
	kernel_pagemap  Pagemap
	vmm_initialised = bool(false)
)

pub struct Pagemap {
pub mut:
	l           klock.Lock
	top_level   &u64
	mmap_ranges []voidptr
}

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
	pml4_entry := (virt & (u64(0x1ff) << 39)) >> 39
	pml3_entry := (virt & (u64(0x1ff) << 30)) >> 30
	pml2_entry := (virt & (u64(0x1ff) << 21)) >> 21
	pml1_entry := (virt & (u64(0x1ff) << 12)) >> 12

	pml4 := pagemap.top_level
	pml3 := get_next_level(pml4, pml4_entry, allocate) or { return none }
	pml2 := get_next_level(pml3, pml3_entry, allocate) or { return none }
	pml1 := get_next_level(pml2, pml2_entry, allocate) or { return none }

	return unsafe { &u64(u64(&pml1[pml1_entry]) + higher_half) }
}

pub fn (pagemap &Pagemap) virt2phys(virt u64) ?u64 {
	pte_p := pagemap.virt2pte(virt, false) or { return none }
	unsafe {
		if pte_p[0] & 1 == 0 {
			return none
		}
		return pte_p[0] & ~u64(0xfff)
	}
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

	unsafe {
		mut entry := &u64(u64(current_level) + higher_half + index * 8)

		// Check if entry is present
		if entry[0] & 0x01 != 0 {
			// If present, return pointer to it
			ret = &u64(entry[0] & ~u64(0xfff))
		} else {
			if allocate == false {
				return none
			}

			// Else, allocate the page table
			ret = pmm_alloc(1)
			if ret == 0 {
				return none
			}
			entry[0] = u64(ret) | 0b111
		}
	}
	return ret
}

pub fn (mut pagemap Pagemap) unmap_page(virt u64) ? {
	pte_p := pagemap.virt2pte(virt, false) or { return error('') }

	unsafe { *pte_p = 0 }

	current_cr3 := cpu.read_cr3()
	if current_cr3 == u64(pagemap.top_level) {
		cpu.invlpg(virt)
	}
}

pub fn (mut pagemap Pagemap) flag_page(virt u64, flags u64) ? {
	pte_p := pagemap.virt2pte(virt, false) or {
		return error('')
	}

	unsafe { *pte_p &= ~u64(0xfff) }
	unsafe { *pte_p |= flags }

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

	pml4_entry := (virt & (u64(0x1ff) << 39)) >> 39
	pml3_entry := (virt & (u64(0x1ff) << 30)) >> 30
	pml2_entry := (virt & (u64(0x1ff) << 21)) >> 21
	pml1_entry := (virt & (u64(0x1ff) << 12)) >> 12

	pml4 := pagemap.top_level
	pml3 := get_next_level(pml4, pml4_entry, true) or { return error('') }
	pml2 := get_next_level(pml3, pml3_entry, true) or { return error('') }
	mut pml1 := get_next_level(pml2, pml2_entry, true) or { return error('') }

	unsafe {
		entry := &u64(u64(pml1) + higher_half + pml1_entry * 8)
		entry[0] = phys | flags
	}
}

pub fn vmm_init(memmap &stivale2.MemmapTag, kernel_base_addr_tag &stivale2.KernelBaseAddrTag, pmr_tag &stivale2.PMRTag) {
	print('vmm: Kernel physical base: 0x${kernel_base_addr_tag.physical_base_addr:x}\n')
	print('vmm: Kernel virtual base: 0x${kernel_base_addr_tag.virtual_base_addr:x}\n')

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

	// Map kernel according to PMRs
	for i := u64(0); i < pmr_tag.entries; i++ {
		pmr := &stivale2.PMR(u64(&pmr_tag.pmrs) + sizeof(stivale2.PMR) * i)

		virt := pmr.base
		phys := kernel_base_addr_tag.physical_base_addr + (pmr.base - kernel_base_addr_tag.virtual_base_addr)
		len := pmr.length

		print('vmm: PMRs: Mapping 0x${phys:x} to 0x${virt:x}, length: 0x${len:x}\n')

		for j := u64(0); j < len; j += page_size {
			kernel_pagemap.map_page(virt + j, phys + j, 0x03) or {
				panic('vmm init failure')
			}
		}
	}

	for i := u64(0x1000); i < 0x100000000; i += page_size {
		kernel_pagemap.map_page(i, i, 0x03) or { panic('vmm init failure') }
		kernel_pagemap.map_page(i + higher_half, i, 0x03) or { panic('vmm init failure') }
	}

	entries := &memmap.entries
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
			kernel_pagemap.map_page(j, j, 0x03) or { panic('vmm init failure') }
			kernel_pagemap.map_page(j + higher_half, j, 0x03) or { panic('vmm init failure') }
		}
	}

	kernel_pagemap.switch_to()

	vmm_initialised = true
}
