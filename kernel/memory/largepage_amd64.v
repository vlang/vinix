// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module memory

import katomic

const amd64_large_page = u64(1) << 7
const direct_large_size = u64(1) << 21
const large_pat = u64(1) << 12

__global (
	direct_large_entries u64
	largepage_fail_split bool
)

fn small_leaf_flags(large u64) u64 {
	flags := (large & ~pte_flags_mask) & ~amd64_large_page
	return flags | if large & large_pat != 0 { amd64_large_page } else { u64(0) }
}

fn large_leaf_phys(large u64, virt u64) u64 {
	return (large & pte_flags_mask & ~(direct_large_size - 1)) | (virt & (direct_large_size - page_size))
}

// Only kernel direct-map leaves use PS. User/shadow tables retain their
// existing base-page COW, paging, accounting and reclamation contracts.
fn amd64_leaf_level(owner &Pagemap, table &u64, index u64, virt u64, make bool) ?&u64 {
	mut entry := unsafe { &u64(u64(table) + higher_half + index * 8) }
	old := unsafe { *entry }
	if old & (pte_present | amd64_large_page) != pte_present | amd64_large_page {
		return get_next_level(owner, table, index, make)
	}
	if !make || virt < user_address_limit() { return none }
	mut pagemap := unsafe { owner }
	if !reserve_table_page(mut pagemap) { return none }
	$if largepage_selftest ? {
		if largepage_fail_split { release_table_page(mut pagemap); return none }
	}
	physical := pmm_alloc_fallible(1)
	if physical == unsafe { nil } {
		release_table_page(mut pagemap)
		return none
	}
	mut leaves := unsafe { &u64(u64(physical) + higher_half) }
	base := old & pte_flags_mask & ~(direct_large_size - 1)
	flags := small_leaf_flags(old)
	for i := u64(0); i < 512; i++ {
		unsafe { leaves[i] = (base + i * page_size) | flags }
	}
	// Equivalent children are initialized before a single descriptor publish.
	// The shootdown completes before a caller changes or removes one child.
	katomic.store(mut entry, u64(physical) | pte_present | pte_writable | (old & pte_user))
	if vmm_initialised { pagemap.invalidate(virt) }
	katomic.dec(mut &direct_large_entries)
	return physical
}

fn (pagemap &Pagemap) kernel_pde(virt u64, make bool) ?&u64 {
	if virt < user_address_limit() { return none }
	root := if la57 {
		get_next_level(pagemap, pagemap.top_level, (virt >> 48) & 0x1ff, make) or { return none }
	} else { pagemap.top_level }
	l3 := get_next_level(pagemap, root, (virt >> 39) & 0x1ff, make) or { return none }
	l2 := get_next_level(pagemap, l3, (virt >> 30) & 0x1ff, make) or { return none }
	return unsafe { &u64(u64(l2) + higher_half + ((virt >> 21) & 0x1ff) * 8) }
}

fn (pagemap &Pagemap) kernel_block_matches(virt u64, physical u64, flags u64) bool {
	entry := pagemap.kernel_pde(virt, false) or { return false }
	old := unsafe { *entry }
	if old & (pte_present | amd64_large_page) != pte_present | amd64_large_page { return false }
	activity := page_accessed | page_dirty
	return large_leaf_phys(old, virt) == physical
		&& small_leaf_flags(old) & ~activity == flags & ~activity
}

fn (pagemap &Pagemap) split_kernel_leaf(virt u64) ? {
	if virt < user_address_limit() { return }
	entry := pagemap.kernel_pde(virt, false) or { return none }
	if unsafe { *entry } & amd64_large_page != 0 {
		pagemap.virt2pte(virt, true)?
	}
}

// Preserve virt2phys's base-page-address contract, including an address in a
// large leaf. Queries allocate nothing and never descend through a PS entry.
fn (pagemap &Pagemap) kernel_leaf_phys(virt u64) ?u64 {
	entry := pagemap.kernel_pde(virt, false) or { return none }
	value := unsafe { *entry }
	if value & pte_present == 0 { return none }
	if value & amd64_large_page != 0 { return large_leaf_phys(value, virt) }
	leaves := unsafe { &u64((value & pte_flags_mask) + higher_half) }
	leaf := unsafe { leaves[(virt >> 12) & 0x1ff] }
	if leaf & pte_present == 0 { return none }
	return leaf & pte_flags_mask
}

fn map_direct_span(base u64, top u64) {
	mut phys := base
	flags := pte_present | pte_noexec | pte_writable
	for phys < top {
		virt := phys + higher_half
		if phys % direct_large_size == 0 && virt % direct_large_size == 0
			&& top - phys >= direct_large_size && direct_large_eligible(phys) {
			mut entry := kernel_pagemap.kernel_pde(virt, true) or { panic('direct-map table allocation') }
			if unsafe { *entry } == 0 {
				unsafe { *entry = phys | flags | amd64_large_page }
				direct_large_entries++
				phys += direct_large_size
				continue
			}
		}
		kernel_pagemap.map_page(virt, phys, flags) or { panic('direct-map leaf allocation') }
		phys += page_size
	}
}

// Run after activation but before SMP: equivalent split, exact child remap,
// neighbor preservation, partial unmap, and allocation failure rollback.
fn largepage_selftest() {
	const_test_virt := u64(0xffff_d000_0000_0000)
	mut entry := kernel_pagemap.kernel_pde(const_test_virt, true) or { panic('large-page self-test table') }
	if unsafe { *entry } != 0 { panic('large-page self-test address collision') }
	unsafe { *entry = pte_present | pte_writable | pte_noexec | amd64_large_page }
	direct_large_entries++
	largepage_fail_split = true
	if _ := kernel_pagemap.map_page(const_test_virt + page_size, page_size, pte_present | pte_noexec) {
		panic('large-page self-test failed allocation accepted')
	}
	largepage_fail_split = false
	if unsafe { *entry } & amd64_large_page == 0 { panic('large-page self-test failed split changed descriptor') }
	if kernel_pagemap.virt2phys(const_test_virt + 123 * page_size + 19) or { ~u64(0) } != 123 * page_size {
		panic('large-page self-test translation')
	}
	kernel_pagemap.map_page(const_test_virt + page_size, page_size, pte_present | pte_noexec) or { panic('large-page self-test split') }
	neighbor := kernel_pagemap.virt2pte(const_test_virt + 2 * page_size, false) or { panic('large-page self-test neighbor') }
	changed := kernel_pagemap.virt2pte(const_test_virt + page_size, false) or { panic('large-page self-test changed') }
	if unsafe { *neighbor } & pte_writable == 0 || unsafe { *changed } & pte_writable != 0 {
		panic('large-page self-test split protection')
	}
	kernel_pagemap.unmap_page(const_test_virt + page_size) or { panic('large-page self-test unmap') }
	if _ := kernel_pagemap.virt2phys(const_test_virt + page_size) { panic('large-page self-test hole') }
	if kernel_pagemap.virt2phys(const_test_virt + 2 * page_size) or { ~u64(0) } != 2 * page_size {
		panic('large-page self-test neighbor lost')
	}
	for i := u64(0); i < 512; i++ {
		if i != 1 { kernel_pagemap.unmap_page(const_test_virt + i * page_size) or { panic('large-page self-test cleanup') } }
	}
	C.kprintf(c'VMM: direct map has %llu large leaves; each replaces 512 base leaves\n', direct_large_entries)
	tlb_test_report('VMM: large-page translation, split, protection, rollback and partial unmap PASS')
}

// The SMP fixture supplies an owned, aligned RAM allocation. This helper
// publishes a fresh supervisor-only alias under the production map lock.
pub fn largepage_test_alias(virt u64, physical u64) bool {
	$if largepage_selftest ? {
		if virt % direct_large_size != 0 || physical % direct_large_size != 0
			|| !direct_large_eligible(physical) { return false }
		kernel_pagemap.l.acquire()
		defer { kernel_pagemap.l.release() }
		mut entry := kernel_pagemap.kernel_pde(virt, true) or { return false }
		if unsafe { *entry } != 0 { return false }
		katomic.store(mut entry, physical | pte_present | pte_writable | pte_noexec | amd64_large_page)
		katomic.inc(mut &direct_large_entries)
		kernel_pagemap.invalidate(virt)
		return true
	}
	return false
}
