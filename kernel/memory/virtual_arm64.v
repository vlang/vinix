@[has_globals]
module memory

import lib
import katomic
import limine
import klock
import aarch64.cpu

fn C.vinix_arm64_switch_granule(mair u64, root u64, tcr u64)

// ARM64 output address mask for a 16 KiB granule: bits [47:14].
pub const pte_flags_mask = u64(0x0000_FFFF_FFFF_C000)
const kernel_pte_address_mask = u64(0x0000_FFFF_FFFF_F000)

// Limine enters with 4 KiB translation tables. Set the kernel's allocation
// granule before the PMM or any page-based subsystem is initialized.
pub fn configure_page_size() {
	page_size = u64(0x4000)
}

pub fn user_address_limit() u64 {
	return u64(1) << 47
}

// ARM64-internal PTE bits
const arm64_pte_valid = u64(0b11)
const arm64_pte_af = u64(1) << 10
const arm64_pte_sh_inner = u64(3) << 8
const arm64_pte_ap_ro = u64(1) << 7 // AP[2]=1 -> read-only
const arm64_pte_ap_user = u64(1) << 6 // AP[1]=1 -> EL0 access
const arm64_pte_ng = u64(1) << 11 // user translations belong to their ASID
const arm64_pte_pxn = u64(1) << 53
const arm64_pte_uxn = u64(1) << 54
const arm64_pte_attr_normal = u64(0) << 2 // MAIR index 0 (Normal Write-Back Cacheable)
const arm64_pte_attr_device = u64(1) << 2 // MAIR index 1 (Device-nGnRnE)
const arm64_pte_attr_uncached = u64(2) << 2 // MAIR index 2 (Normal Non-Cacheable)
const arm64_pte_table = u64(0b11)

// Every boot CPU can veto XOM before userspace starts. Once disabled it is
// never re-enabled: a mapping must remain safe when its process migrates.
__global arm64_execute_only = true

pub fn disable_execute_only() {
	katomic.store(mut &arm64_execute_only, false)
}

pub fn execute_only_supported() bool {
	return katomic.load(&arm64_execute_only)
}

// Translate portable flags into an ARM64 L3 page descriptor.
fn portable_to_arm64_pte(phys u64, flags u64, address_mask u64) u64 {
	mut attr := arm64_pte_attr_normal
	mut sh := arm64_pte_sh_inner
	if flags & pte_device != 0 {
		attr = arm64_pte_attr_device
		sh = u64(0) // Device memory must not be shareable
	} else if flags & pte_uncached != 0 {
		attr = arm64_pte_attr_uncached
		// Non-cacheable memory uses outer shareable for framebuffers
		sh = u64(2) << 8 // Outer Shareable
	}
	mut pte := (phys & address_mask) | arm64_pte_valid | arm64_pte_af | sh | attr

	// All TTBR0 leaves are non-global, including PROT_NONE entries that
	// intentionally lack AP[1]/pte_user. TTBR1 kernel entries remain global.
	if address_mask == pte_flags_mask {
		pte |= arm64_pte_ng
	}

	// OpenBSD marks every userspace mapping privileged-XN: EL0 executable pages
	// may still execute at EL0, but EL1 must never fetch instructions from them.
	// UXN continues to represent the userspace PROT_EXEC decision itself.
	if flags & pte_user != 0 {
		pte |= arm64_pte_pxn
		// AP=2 permits EL1 reads but no EL0 data access; UXN clear still
		// permits EL0 instruction fetch. Checked copies require AP[1], so
		// the direct-map copy path cannot disclose execute-only bytes.
		if flags & pte_execute_only == 0 {
			pte |= arm64_pte_ap_user
		}
		if flags & pte_noexec != 0 {
			pte |= arm64_pte_uxn
		}
	} else {
		// Kernel text must never be executable at EL0. ePAN also uses UXN
		// to permit EL1 data reads of kernel text and its literal pools.
		pte |= arm64_pte_uxn
		if flags & pte_noexec != 0 {
			pte |= arm64_pte_pxn
		}
	}

	// ARM64: AP[2]=0 means writable, AP[2]=1 means read-only.
	// The portable convention: pte_writable SET = writable.
	if flags & pte_writable == 0 {
		pte |= arm64_pte_ap_ro
	}

	return pte
}

pub fn new_pagemap() &Pagemap {
	mut top_level := &u64(pmm_alloc(1))
	if top_level == 0 {
		panic('new_pagemap() allocation failure')
	}

	// On ARM64, TTBR1 handles kernel space. User pagemaps (TTBR0) do
	// not need higher-half entries copied.
	mut pagemap := &Pagemap{
		top_level:   top_level
		track_residency: true
		mmap_ranges: []voidptr{}
		tlb_tag:     arm64_take_asid()
	}
	// Nothing keeps a copy of the list, so growing it can give back the
	// storage it outgrew; V keeps that for arrays that might be sliced, and
	// every fork and exec lost three blocks of it. `|=`, not flags.set():
	// V 0.5.2 compiles set() on an array's flags to nothing.
	pagemap.mmap_ranges.flags |= .noslices
	return pagemap
}

pub fn (pagemap &Pagemap) virt2pte(virt u64, allocate bool) ?&u64 {
	if virt >= user_address_limit() {
		return pagemap.kernel_virt2pte(virt, allocate)
	}
	// 16 KiB granule, 47-bit VA: L1[46:36] L2[35:25] L3[24:14].
	l1_entry := (virt >> 36) & 0x7ff
	l2_entry := (virt >> 25) & 0x7ff
	l3_entry := (virt >> 14) & 0x7ff

	l1 := pagemap.top_level
	l2 := get_next_level(l1, l1_entry, allocate) or { return none }
	l3 := get_next_level(l2, l2_entry, allocate) or { return none }

	return unsafe { &u64(u64(&l3[l3_entry]) + higher_half) }
}

// TTBR1 keeps Limine's 4 KiB, 48-bit kernel geometry. TTBR0 uses the
// independent 16 KiB, 47-bit user geometry above.
fn (pagemap &Pagemap) kernel_virt2pte(virt u64, allocate bool) ?&u64 {
	l0 := pagemap.top_level
	l1 := get_next_level(l0, (virt >> 39) & 0x1ff, allocate) or { return none }
	l2 := get_next_level(l1, (virt >> 30) & 0x1ff, allocate) or { return none }
	l3 := get_next_level(l2, (virt >> 21) & 0x1ff, allocate) or { return none }
	return unsafe { &u64(u64(&l3[(virt >> 12) & 0x1ff]) + higher_half) }
}

pub fn (pagemap &Pagemap) virt2phys(virt u64) ?u64 {
	pte_p := pagemap.virt2pte(virt, false) or { return none }
	if unsafe { *pte_p } & 1 == 0 {
		return none
	}
	mask := if virt >= user_address_limit() { kernel_pte_address_mask } else { pte_flags_mask }
	return unsafe { *pte_p } & mask
}

// Resolve one userspace page for a checked kernel copy. Callers must hold the
// pagemap lock while using the returned physical address so munmap/mprotect
// cannot invalidate the access between validation and memcpy.
pub fn (pagemap &Pagemap) user_page_phys(virt u64, write bool) ?u64 {
	if virt >= user_address_limit() {
		return none
	}
	pte_p := pagemap.virt2pte(virt, false) or { return none }
	pte := unsafe { *pte_p }
	if pte & arm64_pte_valid != arm64_pte_valid || pte & arm64_pte_ap_user == 0 {
		return none
	}
	if write && pte & arm64_pte_ap_ro != 0 {
		return none
	}
	return pte & pte_flags_mask
}

// The bytes of [start, end) that are resident, each page counted as its share:
// a page that fork left shared by three processes counts a third to each, so
// the processes of a group together count it once. What memory.max holds a
// cgroup to. A missing table skips everything it would have covered, so a
// large, mostly untouched range -- a runtime's heap reservation -- costs little
// to count. The caller holds the pagemap lock.
pub fn (pagemap &Pagemap) resident_share(start u64, end u64) u64 {
	mut total := u64(0)
	mut virt := start & ~(page_size - 1)
	for virt < end {
		l1 := unsafe { &u64(u64(pagemap.top_level) + higher_half) }
		e1 := unsafe { l1[(virt >> 36) & 0x7ff] }
		if e1 & 1 == 0 {
			virt = next_table_boundary(virt, 36) or { break }
			continue
		}
		l2 := unsafe { &u64((e1 & pte_flags_mask) + higher_half) }
		e2 := unsafe { l2[(virt >> 25) & 0x7ff] }
		if e2 & 1 == 0 {
			virt = next_table_boundary(virt, 25) or { break }
			continue
		}
		l3 := unsafe { &u64((e2 & pte_flags_mask) + higher_half) }
		table_end := next_table_boundary(virt, 25) or { u64(-1) }
		stop := if end < table_end { end } else { table_end }
		for virt < stop {
			pte := unsafe { l3[(virt >> 14) & 0x7ff] }
			if pte & 1 != 0 {
				refs := pmm_refcount_unlocked(voidptr(pte & pte_flags_mask))
				total += if refs > 1 { page_size / refs } else { page_size }
			}
			virt += page_size
		}
	}
	return total
}

// The first page at or after `start`, and before `end`, that is mapped, or
// `end` when none is. A missing table is skipped with all it would have
// covered, so walking a large reservation with little in it -- MariaDB keeps
// 8 TiB of PROT_NONE -- costs what it holds rather than its size. The caller
// holds the pagemap lock.
pub fn (pagemap &Pagemap) next_present(start u64, end u64) u64 {
	mut virt := start & ~(page_size - 1)
	for virt < end {
		l1 := unsafe { &u64(u64(pagemap.top_level) + higher_half) }
		e1 := unsafe { l1[(virt >> 36) & 0x7ff] }
		if e1 & 1 == 0 {
			virt = next_table_boundary(virt, 36) or { return end }
			continue
		}
		l2 := unsafe { &u64((e1 & pte_flags_mask) + higher_half) }
		e2 := unsafe { l2[(virt >> 25) & 0x7ff] }
		if e2 & 1 == 0 {
			virt = next_table_boundary(virt, 25) or { return end }
			continue
		}
		l3 := unsafe { &u64((e2 & pte_flags_mask) + higher_half) }
		table_end := next_table_boundary(virt, 25) or { u64(-1) }
		stop := if end < table_end { end } else { table_end }
		for virt < stop {
			if unsafe { l3[(virt >> 14) & 0x7ff] } & 1 != 0 {
				return virt
			}
			virt += page_size
		}
	}
	return end
}

// resident_share() with the shared pages told apart, for /proc/<pid>/smaps.
// The caller holds the pagemap lock.
pub fn (pagemap &Pagemap) residency(start u64, end u64) Residency {
	mut counted := Residency{}
	mut virt := start & ~(page_size - 1)
	for virt < end {
		l1 := unsafe { &u64(u64(pagemap.top_level) + higher_half) }
		e1 := unsafe { l1[(virt >> 36) & 0x7ff] }
		if e1 & 1 == 0 {
			virt = next_table_boundary(virt, 36) or { break }
			continue
		}
		l2 := unsafe { &u64((e1 & pte_flags_mask) + higher_half) }
		e2 := unsafe { l2[(virt >> 25) & 0x7ff] }
		if e2 & 1 == 0 {
			virt = next_table_boundary(virt, 25) or { break }
			continue
		}
		l3 := unsafe { &u64((e2 & pte_flags_mask) + higher_half) }
		table_end := next_table_boundary(virt, 25) or { u64(-1) }
		stop := if end < table_end { end } else { table_end }
		for virt < stop {
			pte := unsafe { l3[(virt >> 14) & 0x7ff] }
			if pte & 1 != 0 {
				refs := pmm_refcount_unlocked(voidptr(pte & pte_flags_mask))
				counted.resident += page_size
				if refs > 1 {
					counted.shared += page_size
					counted.share += page_size / refs
				} else {
					counted.share += page_size
				}
			}
			virt += page_size
		}
	}
	return counted
}

// The first address past the table level that maps `virt`, or none at the top
// of the address space.
fn next_table_boundary(virt u64, shift u64) ?u64 {
	next := (virt | ((u64(1) << shift) - 1)) + 1
	if next <= virt {
		return none
	}
	return next
}

pub fn (mut pagemap Pagemap) switch_to() {
	switch_ttbr0(pagemap.tagged_root())
}

// A tag has exactly one live page-map owner on all CPUs. Exhaustion falls
// back to ASID zero; it never recycles a tag while its owner can still run.
// Using eight bits also works on CPUs that implement sixteen ASID bits.
__global (
	arm64_asid_lock klock.Lock
	arm64_asid_used [4]u64
)

fn arm64_take_asid() u16 {
	arm64_asid_lock.acquire()
	defer { arm64_asid_lock.release() }
	for asid := u16(1); asid < 256; asid++ {
		word := asid / 64
		bit := u64(1) << (asid % 64)
		if arm64_asid_used[word] & bit == 0 {
			// Complete stale translation/walk invalidation before publishing
			// ownership. No other live map can use this ASID meanwhile.
			cpu.tlbi_aside1is(asid)
			arm64_asid_used[word] |= bit
			return asid
		}
	}
	return 0
}

pub fn (pagemap &Pagemap) tagged_root() u64 {
	return u64(pagemap.top_level) | (u64(pagemap.tlb_tag) << 48)
}

// Thread context saves the complete hardware TTBR0 value, whereas the
// Pagemap owns only the physical root and its separate ASID.
pub fn switch_ttbr0(root u64) {
	cpu.dsb_ishst()
	cpu.write_ttbr0_el1(root)
	if (root >> 48) & 0xff == 0 {
		cpu.tlbi_vmalle1()
	}
}

// Destruction starts only after every thread detached from this address
// space. Flush cached leaf/walk entries before freeing any of its tables.
pub fn (pagemap &Pagemap) prepare_tlb_teardown() {
	if pagemap.tlb_tag != 0 {
		cpu.tlbi_aside1is(pagemap.tlb_tag)
	} else {
		flush_tlb_everywhere()
	}
}

pub fn (mut pagemap Pagemap) release_tlb_tag() {
	if pagemap.tlb_tag == 0 {
		return
	}
	asid := pagemap.tlb_tag
	arm64_give_asid(asid)
	pagemap.tlb_tag = 0
}

fn arm64_give_asid(asid u16) {
	arm64_asid_lock.acquire()
	// Defensive completion before another allocator can claim this tag.
	cpu.tlbi_aside1is(asid)
	arm64_asid_used[asid / 64] &= ~(u64(1) << (asid % 64))
	arm64_asid_lock.release()
}

// The actual bounded pool, tested before any userspace map or AP can use it.
// No allocation is needed to exercise exhaustion, reuse, and zero reservation.
fn arm64_asid_selftest() {
	if cpu.read_tcr_el1() & ((u64(1) << 22) | (u64(1) << 36)) != 0 {
		panic('TLB self-test: TTBR0 must select an eight-bit ASID')
	}
	if portable_to_arm64_pte(0, pte_present | pte_noexec, pte_flags_mask) & arm64_pte_ng == 0 {
		panic('TLB self-test: PROT_NONE user leaves must be non-global')
	}
	for i := u16(1); i < 256; i++ {
		if arm64_take_asid() != i {
			panic('TLB self-test: duplicate or missing ASID')
		}
	}
	if arm64_take_asid() != 0 || arm64_asid_used[0] & 1 != 0 {
		panic('TLB self-test: pool exhaustion or zero reservation')
	}
	arm64_give_asid(127)
	if arm64_take_asid() != 127 || arm64_take_asid() != 0 {
		panic('TLB self-test: ASID reuse did not preserve live owners')
	}
	for i := u16(1); i < 256; i++ {
		arm64_give_asid(i)
	}
	for i := 0; i < 4; i++ {
		if arm64_asid_used[i] != 0 {
			panic('TLB self-test: leaked ASID ownership')
		}
	}
	for i := 0; i < 2000; i++ {
		asid := arm64_take_asid()
		if asid != 1 {
			panic('TLB self-test: repeated ASID reuse')
		}
		arm64_give_asid(asid)
	}
	println('TLB: ASID pool exhaustion and reuse PASS')
}

fn get_next_level(current_level &u64, index u64, allocate bool) ?&u64 {
	mut ret := unsafe { &u64(0) }
	mut entry := unsafe { &u64(u64(current_level) + higher_half + index * 8) }

	if unsafe { *entry } & 0x01 != 0 {
		ret = unsafe { &u64(*entry & pte_flags_mask) }
	} else {
		if allocate == false {
			return none
		}
		ret = pmm_alloc(1)
		if ret == 0 {
			return none
		}
		unsafe {
			*entry = u64(ret) | arm64_pte_table
		}
	}
	return ret
}

// Returns true if every one of the 2048 descriptors in a page-table page
// (addressed through its higher-half virtual pointer) is empty.
fn arm64_table_empty(table_p &u64) bool {
	for i := u64(0); i < page_size / 8; i++ {
		if unsafe { table_p[i] } != 0 {
			return false
		}
	}
	return true
}

pub fn (mut pagemap Pagemap) unmap_page(virt u64) ? {
	pagemap.l.acquire()
	defer {
		pagemap.l.release()
	}
	pagemap.unmap_page_unlocked(virt)?
}

// Remove one mapping while the caller holds pagemap.l.  Keeping this separate
// avoids recursively acquiring the non-recursive pagemap lock from munmap(),
// which serializes a complete range before tearing it down.
pub fn (mut pagemap Pagemap) unmap_page_unlocked(virt u64) ? {
	l1_entry := (virt >> 36) & 0x7ff
	l2_entry := (virt >> 25) & 0x7ff
	l3_entry := (virt >> 14) & 0x7ff

	// l1..l3 are physical table addresses; l1_p..l3_p are the higher-half
	// virtual pointers used to read/write descriptors.
	l1 := pagemap.top_level
	l2 := get_next_level(l1, l1_entry, false) or { return none }
	l3 := get_next_level(l2, l2_entry, false) or { return none }

	l1_p := unsafe { &u64(u64(l1) + higher_half) }
	l2_p := unsafe { &u64(u64(l2) + higher_half) }
	l3_p := unsafe { &u64(u64(l3) + higher_half) }

	// Clear the leaf entry and flush its translation first -- unless no CPU
	// runs the page map any more, when flush_tlb_everywhere() follows the
	// whole teardown instead. Two broadcast invalidations for every page made
	// an exit, and the old image's teardown in an exec, cost 10 ms.
	old := unsafe { l3_p[l3_entry] }
	unsafe {
		l3_p[l3_entry] = 0
	}
	pagemap.account_resident(virt, old & arm64_pte_valid == arm64_pte_valid, false)
	if !pagemap.dying {
		cpu.tlbi_vaae1(virt >> 12)
		cpu.dsb_sy()
	}
	mut freed_table := false

	// Reclaim now-empty tables from the leaf upward. At every level the parent
	// descriptor is unlinked (and the write made visible with a barrier) BEFORE
	// the child table's memory is returned to the PMM, so no live descriptor can
	// ever point at freed/reused memory. The L1 root table is never freed.
	if arm64_table_empty(l3_p) {
		unsafe {
			l2_p[l2_entry] = 0
		}
		cpu.dsb_sy()
		pmm_free(l3, 1)
		freed_table = true

		if arm64_table_empty(l2_p) {
			unsafe {
				l1_p[l1_entry] = 0
			}
			cpu.dsb_sy()
			pmm_free(l2, 1)
		}
	}

	// Drop any TLB caching of the intermediate walks we just tore down.
	// Intermediate translation-table walk caches can exist on any CPU which
	// ran this user pagemap. Only a table taken out needs it; the leaf's own
	// translation went above.
	if freed_table && !pagemap.dying {
		cpu.tlbi_vmalle1is()
		cpu.dsb_sy()
		cpu.isb()
	}
}

// Every CPU's translations, walk caches included, gone: the flush that
// follows tearing down a page map no CPU runs any more.
pub fn flush_tlb_everywhere() {
	cpu.tlbi_vmalle1is()
	cpu.dsb_sy()
	cpu.isb()
}

// Change the protection of a page that is mapped. One that is not is left
// alone: rewriting its empty entry would map physical page 0 in its place.
// mprotect() reaches pages of a mapping that have not been touched yet, and
// they are faulted in later with the range's new protection.
pub fn (mut pagemap Pagemap) flag_page(virt u64, flags u64) ? {
	mut pte_p := pagemap.virt2pte(virt, false) or { return none }
	if unsafe { *pte_p } & 1 == 0 {
		return none
	}
	old := unsafe { *pte_p }
	phys := old & pte_flags_mask
	new_pte := portable_to_arm64_pte(phys, flags, pte_flags_mask)
	// Tagged maps retain translations while inactive; zero-tag maps can also
	// be active on another CPU. A present user entry always requires BBM.
	install_arm64_pte(mut pte_p, virt, new_pte, true)
	pagemap.account_resident(virt, old & arm64_pte_valid == arm64_pte_valid, true)
}

// Install a page descriptor in an active page table. Replacing a valid
// descriptor with different attributes must use ARM64 break-before-make;
// otherwise a CPU may combine the old address or memory type with the new
// descriptor. During vmm_init the new table is not active yet, so the final
// whole-VM invalidation is sufficient and avoids a barrier per HHDM page.
fn install_arm64_pte(mut entry &u64, virt u64, new_pte u64, active bool) {
	old_pte := unsafe { *entry }
	if old_pte == new_pte {
		return
	}
	// ASID-zero maps flush on every switch; an inactive tagged map may still
	// have translations on any CPU and must use break-before-make as well.
	// Fresh invalid entries need only descriptor publication below.
	if !vmm_initialised || !active {
		unsafe {
			*entry = new_pte
		}
		return
	}

	if old_pte & 1 != 0 {
		unsafe {
			*entry = 0
		}
		cpu.dsb_ishst()
		cpu.tlbi_vaae1(virt >> 12)
		cpu.dsb_ish()
		cpu.isb()
	}

	unsafe {
		*entry = new_pte
	}
	cpu.dsb_ishst()
	// A translation fault cannot be cached in an Arm TLB, so making an
	// invalid descriptor valid needs no invalidation. The old valid mapping
	// was invalidated above before this descriptor was installed.
	cpu.isb()
}

pub fn (mut pagemap Pagemap) map_page(virt u64, phys u64, flags u64) ? {
	pagemap.l.acquire()
	defer {
		pagemap.l.release()
	}
	pagemap.map_page_unlocked(virt, phys, flags)?
}

pub fn (mut pagemap Pagemap) map_page_unlocked(virt u64, phys u64, flags u64) ? {
	if virt >= user_address_limit() {
		mut entry := pagemap.kernel_virt2pte(virt, true) or { return none }
		new_pte := portable_to_arm64_pte(phys, flags, kernel_pte_address_mask)
		active := cpu.read_ttbr1_el1() & pte_flags_mask == u64(pagemap.top_level) & pte_flags_mask
		install_arm64_pte(mut entry, virt, new_pte, active)
		return
	}
	l1_entry := (virt >> 36) & 0x7ff
	l2_entry := (virt >> 25) & 0x7ff
	l3_entry := (virt >> 14) & 0x7ff

	l1 := pagemap.top_level
	l2 := get_next_level(l1, l1_entry, true) or { return none }
	l3 := get_next_level(l2, l2_entry, true) or { return none }

	mut entry := unsafe { &u64(u64(l3) + higher_half + l3_entry * 8) }

	old := unsafe { *entry }
	new_pte := portable_to_arm64_pte(phys, flags, pte_flags_mask)
	install_arm64_pte(mut entry, virt, new_pte, true)
	pagemap.account_resident(virt, old & arm64_pte_valid == arm64_pte_valid, true)
}

fn remap_hhdm_span(phys u64, len u64, flags u64, failure string) u64 {
	if len == 0 || phys > u64(-1) - len || phys + len > u64(-1) - (kernel_page_size - 1) {
		panic('${failure}: invalid physical aperture')
	}
	page_base := lib.align_down(phys, kernel_page_size)
	page_top := lib.align_up(phys + len, kernel_page_size)
	for pg := page_base; pg < page_top; pg += kernel_page_size {
		kernel_pagemap.map_page(pg + higher_half, pg, pte_present | pte_noexec | pte_writable | flags) or { panic('${failure}: failed to map physical aperture') }
	}
	cpu.dsb_sy()
	cpu.isb()
	return phys + higher_half
}

// map_mmio maps a physical device (MMIO) aperture into the higher-half direct
// map with Device-nGnRnE attributes and returns its virtual address. This must
// be used by every device driver instead of assuming `phys + higher_half` is
// already valid: vmm_init only pre-maps the first 4 GiB as Device memory, so
// Apple register apertures (AIC/ASC/DART/PMGR, all far above 4 GiB) are either
// unmapped or, if they happen to fall inside a RAM memmap entry, mapped Normal
// cacheable — the wrong memory type for registers.
pub fn map_mmio(phys u64, len u64) u64 {
	return remap_hhdm_span(phys, len, pte_device, 'map_mmio')
}

// Host-visible VirtIO GPU memory is coherent with the host GPU. The direct
// alias must match the Normal cacheable user mapping used by DRM mmap.
pub fn map_shared_memory(phys u64, len u64) u64 {
	return remap_hhdm_span(phys, len, 0, 'map_shared_memory')
}

// Map reserved coprocessor shared memory as Normal Non-Cacheable. Apple maps
// the AGX uPPL handoff and TTB array with write-combining semantics; leaving
// their HHDM aliases Write-Back cacheable can hide AP stores from firmware.
pub fn map_uncached(phys u64, len u64) u64 {
	return remap_hhdm_span(phys, len, pte_uncached, 'map_uncached')
}

@[_linker_section: '.requests']
@[cinit]
__global (
	volatile paging_mode_req = limine.LiminePagingModeRequest{
		response: unsafe { nil }
		revision: 1
		mode: limine.limine_paging_mode_aarch64_4lvl
		max_mode: limine.limine_paging_mode_aarch64_4lvl
		min_mode: limine.limine_paging_mode_aarch64_4lvl
	}
)

// The framebuffer's physical span, declared by the caller before vmm_init so it
// is mapped Non-Cacheable in the kernel tables whether or not the bootloader's
// memory map carries a FRAMEBUFFER entry for it. On Apple Silicon the
// framebuffer is iBoot-carved memory outside every RAM entry, and it is also
// the first thing written after the page-table switch and the only place a
// panic can be reported, so a missed mapping there is a silent freeze.
__global (
	vmm_framebuffer_base = u64(0)
	vmm_framebuffer_len  = u64(0)
)

pub fn declare_framebuffer(phys u64, len u64) {
	vmm_framebuffer_base = phys
	vmm_framebuffer_len = len
}

// Is the page at `page` inside a memory map entry that describes memory, as
// opposed to a hole or a reserved range? `first` is the first entry that does
// not end at or below the page.
fn low_page_is_memory(entries &&limine.LimineMemmapEntry, first u64, count u64, page u64) bool {
	for k := first; k < count; k++ {
		entry := unsafe { entries[k] }
		if lib.align_down(entry.base, kernel_page_size) > page {
			return false
		}
		if lib.align_up(entry.base + entry.length, kernel_page_size) <= page {
			continue
		}
		return match entry.@type {
			limine.limine_memmap_usable, limine.limine_memmap_acpi_reclaimable,
			limine.limine_memmap_acpi_nvs, limine.limine_memmap_bootloader_reclaimable,
			limine.limine_memmap_kernel_and_modules, limine.limine_memmap_framebuffer {
				true
			}
			else {
				false
			}
		}
	}
	return false
}

pub fn vmm_init() {
	kernel_pagemap.top_level = pmm_alloc(1)
	if kernel_pagemap.top_level == 0 {
		panic('vmm_init() allocation failure')
	}

	if kaddr_req.response == unsafe { nil } {
		panic('Kernel address bootloader response missing')
	}
	C.kprintf(c'vmm: Kernel physical base: 0x%llx\n', u64(kaddr_req.response.physical_base))
	C.kprintf(c'vmm: Kernel virtual base: 0x%llx\n', u64(kaddr_req.response.virtual_base))
	virtual_base := kaddr_req.response.virtual_base
	physical_base := kaddr_req.response.physical_base

	// Map kernel text (executable, read-only)
	text_virt := u64(voidptr(C.text_start))
	text_phys := (text_virt - virtual_base) + physical_base
	text_len := u64(voidptr(C.text_end)) - text_virt
	map_kernel_span(text_virt, text_phys, text_len, pte_present)

	// Map kernel rodata (no-exec, read-only)
	rodata_virt := u64(voidptr(C.rodata_start))
	rodata_phys := (rodata_virt - virtual_base) + physical_base
	rodata_len := u64(voidptr(C.rodata_end)) - rodata_virt
	map_kernel_span(rodata_virt, rodata_phys, rodata_len, pte_present | pte_noexec)

	// Map kernel data (no-exec, read-write)
	data_virt := u64(voidptr(C.data_start))
	data_phys := (data_virt - virtual_base) + physical_base
	data_len := u64(voidptr(C.data_end)) - data_virt
	map_kernel_span(data_virt, data_phys, data_len, pte_present | pte_noexec | pte_writable)

	memmap := memmap_req.response
	entries := memmap.entries

	// Map the first 4 GiB of physical memory into the HHDM. Where RAM and the
	// device apertures sit inside it depends on the machine: QEMU's virt puts
	// RAM at 1 GiB and its devices below that, VirtualBox puts RAM at 128 MiB
	// and its devices just under 4 GiB. Map what the memory map calls memory as
	// Normal cacheable and everything else -- holes, and reserved ranges, which
	// is how UEFI reports runtime MMIO -- as Device. RAM mapped as Device takes
	// an alignment fault on the first unaligned access and makes exclusive
	// accesses unpredictable; registers mapped Normal can be merged or cached.
	mut next_entry := u64(0)
	mut low_device_pages := u64(0)
	for i := u64(0); i < 0x100000000; i += kernel_page_size {
		// The memory map is sorted by base and its entries do not overlap.
		for next_entry < memmap.entry_count
			&& unsafe { lib.align_up(entries[next_entry].base + entries[next_entry].length, kernel_page_size) } <= i {
			next_entry++
		}
		mut flags := pte_present | pte_noexec | pte_writable
		if !low_page_is_memory(entries, next_entry, memmap.entry_count, i) {
			flags |= pte_device
			low_device_pages++
		}
		kernel_pagemap.map_page(i + higher_half, i, flags) or {
			panic('vmm init failure')
		}
	}
	C.kprintf(c'vmm: HHDM 0-4GiB mapped (%llu device pages)\n', u64(low_device_pages))

	// Map remaining physical memory. On Apple Silicon this is the whole of RAM,
	// which sits above 4 GiB, so this loop (barely exercised by QEMU, whose RAM
	// is below 4 GiB) does the real work. Print how much it covered: a runaway
	// count would explain a stall here rather than at the page-table switch.
	mut high_pages := u64(0)
	for i := 0; i < memmap.entry_count; i++ {
		base := unsafe { lib.align_down(entries[i].base, kernel_page_size) }
		top := unsafe { lib.align_up(entries[i].base + entries[i].length, kernel_page_size) }
		if top <= u64(0x100000000) {
			continue
		}
		for j := base; j < top; j += kernel_page_size {
			if j < u64(0x100000000) {
				continue
			}
			kernel_pagemap.map_page(j + higher_half, j, pte_present | pte_noexec | pte_writable) or {
				panic('vmm init failure')
			}
			high_pages++
		}
	}
	C.kprintf(c'vmm: high RAM mapped (%llu pages above 4GiB)\n', u64(high_pages))

	// Every page the PMM has consumed or may hand out must be reachable
	// through the higher half once these tables are live, or the first
	// allocation afterwards faults. The bitmap lives inside a usable entry and
	// pmm_init no longer carves it out, so the loop above already covered it;
	// map it explicitly anyway, so that invariant does not depend on the PMM.
	if pmm_bitmap_size != 0 {
		for pg := pmm_bitmap_phys; pg < pmm_bitmap_phys + pmm_bitmap_size; pg += kernel_page_size {
			kernel_pagemap.map_page(pg + higher_half, pg, pte_present | pte_noexec | pte_writable) or {
				panic('vmm init failure: pmm bitmap')
			}
		}
	}
	C.kprintf(c'vmm: pmm bitmap 0x%llx +0x%llx mapped\n', u64(pmm_bitmap_phys), u64(pmm_bitmap_size))

	// Remap framebuffer regions as Non-Cacheable.
	// Normal Write-Back Cacheable (the default) causes writes to stay in CPU cache,
	// never reaching the actual display device.
	mut fb_entries := u64(0)
	for k := u64(0); k < memmap.entry_count; k++ {
		entry := unsafe { entries[k] }
		if entry.@type == limine.limine_memmap_framebuffer {
			fb_entries++
			fb_base := lib.align_down(entry.base, kernel_page_size)
			fb_top := lib.align_up(entry.base + entry.length, kernel_page_size)
			for pg := fb_base; pg < fb_top; pg += kernel_page_size {
				kernel_pagemap.map_page(pg + higher_half, pg, pte_present | pte_noexec | pte_writable | pte_uncached) or {
					panic('vmm init failure: framebuffer remap')
				}
			}
		}
	}

	// The framebuffer the caller declared, mapped from its own span rather than
	// from the memory map. Harmless when it duplicates an entry above.
	if vmm_framebuffer_len != 0 {
		fb_base := lib.align_down(vmm_framebuffer_base, kernel_page_size)
		fb_top := lib.align_up(vmm_framebuffer_base + vmm_framebuffer_len, kernel_page_size)
		for pg := fb_base; pg < fb_top; pg += kernel_page_size {
			kernel_pagemap.map_page(pg + higher_half, pg, pte_present | pte_noexec | pte_writable | pte_uncached) or {
				panic('vmm init failure: declared framebuffer')
			}
		}
	}
	C.kprintf(c'vmm: framebuffer 0x%llx +0x%llx mapped (memmap FB entries: %llu, HHDM 0x%llx)\n',
		u64(vmm_framebuffer_base), u64(vmm_framebuffer_len), u64(fb_entries), u64(higher_half))

	protect_kernel_image_alias(text_phys, u64(voidptr(C.rodata_end)) - text_virt)

	// Activate the kernel page tables. This is a live switch: the MMU is already
	// on (Limine handed off with it enabled), so the running instruction stream,
	// stack and framebuffer must stay mapped across it. The kernel's tables map
	// all three. TTBR1 keeps Limine's 4 KiB geometry while TTBR0 changes to
	// 16 KiB user pages in the same register update.
	print('vmm: activating kernel page tables\n')
	vmm_activate_on_cpu()

	// Only reached if the switch did not fault: the framebuffer alias in the
	// new tables is live and flanterm can still render. On a machine with no
	// console this line is how a successful switch is told apart from one that
	// faulted into silence.
	print('vmm: kernel page tables live\n')

	vmm_initialised = true

	println('vmm: user TLB uses 255 exclusive 8-bit ASIDs')
	$if tlb_selftest ? {
		arm64_asid_selftest()
	}

	$if vmap_selftest ? {
		vmap_selftest()
	}
}

// Put this CPU on the kernel's page tables and memory attributes.
//
// Every one of these registers is per-CPU, so a secondary CPU has to run this
// too: writing only TTBR0 leaves it translating the higher half through the
// bootloader's TTBR1, which does not have the mappings made after hand-off and
// whose MAIR indices mean something else. It got away with that for as long as
// it never ran a thread -- and stopped the moment one of its threads switched
// TTBR0 to a private address space.
pub fn vmm_activate_on_cpu() {
	// MAIR_EL1:
	//   Index 0: Normal Write-Back Cacheable (0xFF)
	//   Index 1: Device-nGnRnE (0x00)
	//   Index 2: Normal Non-Cacheable (0x44)
	// Limine's live tables use index 1 for the framebuffer with a different
	// attribute, so nothing may touch the framebuffer between this write and
	// the new tables going live.
	mair := u64(0xFF) | (u64(0x00) << 8) | (u64(0x44) << 16)

	// TCR_EL1 for 16 KiB user pages and 4 KiB kernel pages. Read physical
	// address size from
	// this CPU's ID_AA64MMFR0_EL1.PARange. PARange and TCR.IPS share an encoding.
	mmfr0 := cpu.read_id_aa64mmfr0_el1()
	asid_bits := (mmfr0 >> 4) & 0xf
	if asid_bits != 0 && asid_bits != 2 {
		panic('ARM64 CPU advertises an unsupported ASID width')
	}
	if (mmfr0 >> 20) & 0xf == 0xf {
		panic('ARM64 CPU does not support 16 KiB translation granules')
	}
	mut tcr_ips := (mmfr0 >> 0) & 0xf
	if tcr_ips > 6 {
		// Fallback to 48-bit PA if the encoding is unknown/reserved.
		tcr_ips = 5
	}
	// A1=0 selects the ASID in TTBR0, AS=0 uses its low eight bits.
	// These settings are programmed on the BSP and every secondary CPU.
	tcr := u64(17) | // T0SZ = 17 -> 47-bit user VA
	(u64(16) << 16) | // T1SZ = 16 -> 48-bit kernel VA
	(u64(0b10) << 14) | // TG0 = 16 KiB granule (TTBR0)
	(u64(0b10) << 30) | // TG1 = 4 KiB granule (TTBR1)
	(tcr_ips << 32) | // IPS = physical address size
	(u64(0b11) << 12) | // SH0 = inner shareable
	(u64(0b11) << 28) | // SH1 = inner shareable
	(u64(0b01) << 10) | // ORGN0 = Write-Back
	(u64(0b01) << 26) | // ORGN1 = Write-Back
	(u64(0b01) << 8) | // IRGN0 = Write-Back
	(u64(0b01) << 24) // IRGN1 = Write-Back

	// The individual register helpers issue ISB after each write, which would
	// interpret one table under the other granule. Publish the complete regime
	// before a single context-synchronization barrier.
	C.vinix_arm64_switch_granule(mair, u64(kernel_pagemap.top_level), tcr)
}
