module memory

import klock

__global (
	page_size = u64(0x1000)
)

__global (
	higher_half = u64(0xffff800000000000)
)

pub struct Pagemap {
	l         klock.Lock
	top_level &u64
}

pub fn new_pagemap() Pagemap {
	top_level := pmm_alloc(1)
	if top_level == 0 {
		panic('new_pagemap() allocation failure')
	}
	return Pagemap{klock.new(), top_level}
}

pub fn new_pagemap_from_current() Pagemap {
	mut top_level := &u64(0)
	asm volatile amd64 {
		mov top_level, cr3
		; =r (top_level)
		; ; memory
	}
	return Pagemap{klock.new(), top_level}
}

pub fn (pagemap Pagemap) switch_to() {
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
		mut entry := &current_level[index]

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

pub fn (pagemap Pagemap) map_page(virt u64, phys u64, flags u64) {
	pml4_entry := (virt & (u64(0x1ff) << 39)) >> 39
	pml3_entry := (virt & (u64(0x1ff) << 30)) >> 30
	pml2_entry := (virt & (u64(0x1ff) << 21)) >> 21
	pml1_entry := (virt & (u64(0x1ff) << 12)) >> 12

	pml4 := pagemap.top_level
	pml3 := get_next_level(pml4, pml4_entry)
	pml2 := get_next_level(pml3, pml3_entry)
	mut pml1 := get_next_level(pml2, pml2_entry)

	unsafe {
		pml1[pml1_entry] = phys | flags
	}
}
