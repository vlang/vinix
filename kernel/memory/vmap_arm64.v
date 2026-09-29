module memory

import aarch64.cpu

// Past the direct map, which starts at the top of TTBR1's range, as far as
// the region reaches. See vmap.v.
const vmap_base = u64(0xffff_8000_0000_0000)

// The last-level entry for `virt` in the kernel's tables, which keep Limine's
// 4 KiB granule, or nil. With `make` the tables it needs are made, from free
// pages only; nil then means there were none, and the caller reclaims some
// with vmap_table_lock let go. Called with vmap_table_lock held.
fn vmap_leaf(virt u64, make bool) &u64 {
	mut table := u64(kernel_pagemap.top_level)
	for shift := u64(39); shift > 12; shift -= 9 {
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
			// The walker must not find the table before its zeroes.
			cpu.dsb_ishst()
			unsafe {
				*entry = next | arm64_pte_table
			}
		}
		table = unsafe { *entry } & kernel_pte_address_mask
	}
	return unsafe { &u64(table + higher_half + ((virt >> 12) & 0x1ff) * 8) }
}

// Map one physical page at `virt`: four entries for a 16 KiB page.
fn vmap_install(virt u64, phys u64) bool {
	for offset := u64(0); offset < page_size; offset += kernel_page_size {
		mut reclaimed := false
		for {
			vmap_table_lock.acquire()
			mut entry := vmap_leaf(virt + offset, true)
			if entry != unsafe { nil } {
				unsafe {
					*entry = portable_to_arm64_pte(phys + offset, pte_present | pte_noexec | pte_writable,
						kernel_pte_address_mask)
				}
				// An invalid entry is never in a TLB, so there is nothing to
				// invalidate.
				cpu.dsb_ishst()
				cpu.isb()
				vmap_table_lock.release()
				break
			}
			vmap_table_lock.release()
			if reclaimed {
				return false
			}
			reclaim_pages(1)
			reclaimed = true
		}
	}
	return true
}

// Unmap the page at `virt` and return the physical page that was there, or 0.
// Every CPU has dropped the translation by the time this returns: TLBI VAAE1IS
// is broadcast, and cpu.tlbi_vaae1() waits for it to complete.
fn vmap_remove(virt u64) u64 {
	mut phys := u64(0)
	vmap_table_lock.acquire()
	for offset := u64(0); offset < page_size; offset += kernel_page_size {
		mut entry := vmap_leaf(virt + offset, false)
		if entry == unsafe { nil } || unsafe { *entry } & 1 == 0 {
			continue
		}
		if phys == 0 {
			phys = (unsafe { *entry } & kernel_pte_address_mask) - offset
		}
		unsafe {
			*entry = 0
		}
		cpu.tlbi_vaae1((virt + offset) >> 12)
	}
	vmap_table_lock.release()
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
	return (pte & kernel_pte_address_mask) | (addr & (kernel_page_size - 1))
}
