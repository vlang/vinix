module memory

// Between the direct map and the kernel image, in 4- and 5-level paging alike.
// The top-level entries above the user half are made at boot and copied into
// every page map, so the tables made under them here are every page map's.
// See vmap.v.
const vmap_base = u64(0xffff_e000_0000_0000)

// The last-level entry for `virt` in the kernel's tables, or nil. With `make`
// the tables it needs are made, from free pages only; nil then means there
// were none, and the caller reclaims some with vmap_table_lock let go. Called
// with vmap_table_lock held.
fn vmap_leaf(virt u64, make bool) &u64 {
	mut table := u64(kernel_pagemap.top_level)
	top_shift := if la57 { u64(48) } else { u64(39) }
	for shift := top_shift; shift > 12; shift -= 9 {
		mut entry := unsafe { &u64(table + higher_half + ((virt >> shift) & 0x1ff) * 8) }
		if unsafe { *entry } & 1 == 0 {
			if !make {
				return unsafe { nil }
			}
			next := u64(try_alloc_nozero(1))
			if next == 0 {
				return unsafe { nil }
			}
			unsafe { C.memset(voidptr(next + higher_half), 0, page_size) }
			unsafe {
				*entry = next | pte_present | pte_writable
			}
		}
		table = unsafe { *entry } & pte_flags_mask
	}
	return unsafe { &u64(table + higher_half + ((virt >> 12) & 0x1ff) * 8) }
}

// Map one physical page at `virt`. An entry that was not present is in no TLB,
// so there is nothing to invalidate.
fn vmap_install(virt u64, phys u64) bool {
	mut reclaimed := false
	for {
		vmap_table_lock.acquire()
		mut entry := vmap_leaf(virt, true)
		if entry != unsafe { nil } {
			unsafe {
				*entry = phys | pte_present | pte_writable | pte_noexec
			}
			vmap_table_lock.release()
			return true
		}
		vmap_table_lock.release()
		if reclaimed {
			return false
		}
		reclaim_pages(1)
		reclaimed = true
	}
	return false
}

// Unmap the page at `virt` and return the physical page that was there, or 0.
// Every CPU has dropped the translation by the time this returns: a kernel
// mapping is shot down everywhere.
fn vmap_remove(virt u64) u64 {
	vmap_table_lock.acquire()
	defer {
		vmap_table_lock.release()
	}
	mut entry := vmap_leaf(virt, false)
	if entry == unsafe { nil } || unsafe { *entry } & 1 == 0 {
		return 0
	}
	phys := unsafe { *entry } & pte_flags_mask
	unsafe {
		*entry = 0
	}
	kernel_pagemap.invalidate(virt)
	return phys
}

// The physical address `addr` in the region is mapped to, or 0.
fn vmap_translate(addr u64) u64 {
	vmap_table_lock.acquire()
	entry := vmap_leaf(addr, false)
	pte := if entry == unsafe { nil } { u64(0) } else { unsafe { *entry } }
	vmap_table_lock.release()
	if pte & 1 == 0 {
		return 0
	}
	return (pte & pte_flags_mask) | (addr & (page_size - 1))
}

fn kernel_stack_protected(addr u64) bool {
	vmap_table_lock.acquire()
	entry := vmap_leaf(addr, false)
	pte := if entry == unsafe { nil } { u64(0) } else { unsafe { *entry } }
	vmap_table_lock.release()
	return pte & (pte_present | pte_writable | pte_noexec) == (pte_present | pte_writable | pte_noexec)
		&& pte & pte_user == 0
}
