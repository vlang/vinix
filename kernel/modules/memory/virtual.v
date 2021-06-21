[manualfree] module memory

import lib
import stivale2
import klock

__global (
	page_size = u64(0x1000)
	higher_half = u64(0xffff800000000000)
	kernel_pagemap Pagemap
	vmm_initialised = bool(false)
)

struct Pagemap {
pub mut:
	l           klock.Lock
	top_level   &u64
	mmap_ranges []voidptr
}

pub fn new_pagemap() Pagemap {
	mut top_level := &u64(pmm_alloc(1))
	if top_level == 0 {
		panic('new_pagemap() allocation failure')
	}
	// Import higher half from kernel pagemap
	for i := u64(256); i < 512; i++ {
		unsafe { top_level[i] = kernel_pagemap.top_level[i] }
	}
	return Pagemap{top_level: top_level, mmap_ranges: []voidptr{}}
}

pub fn (mut pagemap Pagemap) switch_to() {
	top_level := pagemap.top_level

	asm volatile amd64 {
		mov cr3, top_level
		; ; r (top_level)
		; memory
	}
}

fn get_next_level(current_level &u64, index u64) &u64 {
	mut ret := &u64(0)

	unsafe {
		mut entry := &u64(u64(current_level) + higher_half + index * 8)

		// Check if entry is present
		if entry[0] & 0x01 != 0 {
			// If present, return pointer to it
			ret = &u64(entry[0] & ~u64(0xfff))
		} else {
			// Else, allocate the page table
			ret = pmm_alloc(1)
			if ret == 0 {
				return 0
			}
			entry[0] = u64(ret) | 0b111
		}
	}
	return ret
}

pub fn (mut pagemap Pagemap) map_page(virt u64, phys u64, flags u64) {
	pagemap.l.acquire()

	pml4_entry := (virt & (u64(0x1ff) << 39)) >> 39
	pml3_entry := (virt & (u64(0x1ff) << 30)) >> 30
	pml2_entry := (virt & (u64(0x1ff) << 21)) >> 21
	pml1_entry := (virt & (u64(0x1ff) << 12)) >> 12

	pml4 := pagemap.top_level
	pml3 := get_next_level(pml4, pml4_entry)
	pml2 := get_next_level(pml3, pml3_entry)
	mut pml1 := get_next_level(pml2, pml2_entry)

	unsafe {
		entry := &u64(u64(pml1) + higher_half + pml1_entry * 8)
		entry[0] = phys | flags
	}

	pagemap.l.release()
}

pub fn vmm_init(memmap &stivale2.MemmapTag) {
	kernel_pagemap.top_level = pmm_alloc(1)
	if kernel_pagemap.top_level == 0 {
		panic('vmm_init() allocation failure')
	}

	// Since the higher half has to be shared amongst all address spaces,
	// we need to initialise every single higher half PML3 so they can be
	// shared.
	for i := u64(256); i < 512; i++ {
		// get_next_level will allocate the PML3s for us.
		get_next_level(kernel_pagemap.top_level, i)
	}

	for i := u64(0x1000); i < 0x100000000; i += page_size {
		kernel_pagemap.map_page(i, i, 0x03)
		kernel_pagemap.map_page(i + higher_half, i, 0x03)
	}
	for i := u64(0); i < 0x80000000; i += page_size {
		kernel_pagemap.map_page(i + u64(0xffffffff80000000), i, 0x03)
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
			kernel_pagemap.map_page(j, j, 0x03)
			kernel_pagemap.map_page(j + higher_half, j, 0x03)
		}
	}

	kernel_pagemap.switch_to()

	vmm_initialised = true
}
