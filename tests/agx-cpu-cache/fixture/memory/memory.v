@[has_globals]
module memory

import aarch64.cpu
import klock

pub const pte_uncached = u64(1) << 4
const kernel_page_size = u64(4096)
const kernel_pte_address_mask = u64(0x0000_ffff_ffff_f000)
const arm64_pte_valid = u64(3)
const arm64_pte_attr_normal = u64(0)
const arm64_pte_attr_uncached = u64(2) << 2
const arm64_pte_sh_inner = u64(3) << 8
const arm64_pte_ap_ro = u64(1) << 7
const keep_bits = (u64(1) << 10) | (u64(1) << 53) | (u64(1) << 54)

struct Leaf { phys u64 mut: pte u64 }
struct Allocation { phys u64 pages u64 raw voidptr }
struct Pagemap { mut: l klock.Lock top_level &u64 = unsafe { &u64(0x4000) } }
__global kernel_pagemap Pagemap
__global higher_half = u64(0)
__global vmm_initialised = true
__global leaves [256]Leaf
__global leaf_count int
__global allocations [32]Allocation
__global allocation_count int
__global reject_allocation bool
__global omit_leaf = -1
__global omit_new_leaf = -1
__global freed int

fn (pagemap &Pagemap) kernel_virt2pte(virt u64, allocate bool) ?&u64 {
	assert !allocate, 'cache transition must not allocate page tables'
	assert pagemap.l.is_held()
	cpu.watch(virt)
	for i in 0 .. leaf_count {
		if leaves[i].phys == virt {
			if i == omit_leaf { return none }
			return unsafe { &leaves[i].pte }
		}
	}
	return none
}

pub fn prepare() { cpu.set_probe(probe); cpu.set_root(0x4000); cpu.set_ctr(u64(5) << 16); cpu.reset() }
pub fn live() int { return allocation_count }
pub fn frees() int { return freed }
pub fn fail_allocations(value bool) { reject_allocation = value }
pub fn fail_new_mapping(index int) { omit_new_leaf = index }
pub fn fail_lookup(index int) { omit_leaf = index }
pub fn initialized(value bool) { vmm_initialised = value }
pub fn leaf_pte(index int) u64 { assert index < leaf_count; return leaves[index].pte }
pub fn set_leaf(index int, pte u64) { assert index < leaf_count; leaves[index].pte = pte }
pub fn locked() bool { return kernel_pagemap.l.is_held() }

pub fn probe(address u64) u64 {
	page := address & ~(kernel_page_size - 1)
	for i in 0 .. leaf_count { if leaves[i].phys == page { return leaves[i].pte } }
	return 0
}

pub fn user_room(pages u64) bool { return pages > 0 && pages <= 16 }
pub fn pmm_alloc_aligned_fallible(pages u64, alignment u64) voidptr {
	if reject_allocation { return unsafe { nil } }
	assert pages <= 16 && alignment > 0 && allocation_count < allocations.len
	boundary := alignment * 16384
	raw := unsafe { C.malloc(pages * 16384 + boundary) }
	assert raw != unsafe { nil }
	phys := (u64(raw) + boundary - 1) & ~(boundary - 1)
	unsafe { C.memset(voidptr(phys), 0, pages * 16384) }
	allocations[allocation_count] = Allocation{phys, pages, raw}
	allocation_count++
	first := leaf_count
	for offset := u64(0); offset < pages * 16384; offset += kernel_page_size {
		assert leaf_count < leaves.len
		leaves[leaf_count] = Leaf{phys + offset, (phys + offset) | arm64_pte_valid | arm64_pte_sh_inner | keep_bits}
		leaf_count++
	}
	if omit_new_leaf >= 0 { omit_leaf = first + omit_new_leaf; omit_new_leaf = -1 }
	return voidptr(phys)
}

pub fn pmm_free(pointer voidptr, pages u64) {
	phys := u64(pointer)
	for i in 0 .. leaf_count {
		if leaves[i].phys >= phys && leaves[i].phys < phys + pages * 16384 {
			assert leaves[i].pte & (u64(7) << 2) == arm64_pte_attr_normal, 'PMM reuse before restoring Write-Back'
			assert leaves[i].pte & (u64(3) << 8) == arm64_pte_sh_inner
		}
	}
	for i in 0 .. allocation_count {
		if allocations[i].phys != phys { continue }
		assert allocations[i].pages == pages
		cpu.record('pmm_free', phys)
		unsafe { C.free(allocations[i].raw) }
		for j in i + 1 .. allocation_count { allocations[j - 1] = allocations[j] }
		allocation_count--
		mut count := 0
		for j in 0 .. leaf_count {
			if leaves[j].phys >= phys && leaves[j].phys < phys + pages * 16384 { continue }
			leaves[count] = leaves[j]; count++
		}
		leaf_count = count
		omit_leaf = -1
		freed++
		return
	}
	assert false, 'unknown PMM free'
}
