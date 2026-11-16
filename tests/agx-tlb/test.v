// SPDX-License-Identifier: GPL-2.0-or-later
module main

import gpu.agx.pgtable
import gpu.agx.mmu
import gpu.agx.tlb
import memory

fn expect_asid(asid u8, pte u64) {
	calls := tlb.calls()
	assert calls.len == 1
	assert !calls[0].all && calls[0].asid == asid
	assert calls[0].pte == pte, 'TLBI must observe the new PTE'
	tlb.clear()
}

fn test_user_mappings() {
	mut pt := pgtable.new_pgtable(39, 48) or { panic('page table') }
	address := u64(0x100000)
	physical := u64(0x200000)
	assert pt.map(address, physical, pgtable.uat_pgsz, pgtable.gpu_prot_fw_gpu_cached_rw)
	pte := pt.get_pte(address, false) or { panic('PTE') }
	tlb.observe(pte, unsafe { nil })
	assert tlb.calls().len == 0, 'unpublished tables need no TLBI'
	pt.bind_tlb(7)
	expect_asid(7, unsafe { *pte })

	// Reuse a mapping, change cache attributes, then remove it. The reference
	// requires TLBI before sending FWCTL and again before freeing the backing.
	assert pt.map_page(address, physical + pgtable.uat_pgsz, pgtable.gpu_prot_fw_gpu_cached_rw)
	expect_asid(7, unsafe { *pte })
	assert pt.reprotect(address, pgtable.uat_pgsz, pgtable.gpu_prot_fw_gpu_shared_rw)
	expect_asid(7, unsafe { *pte })
	assert !pgtable.is_cached_noncoherent(unsafe { *pte })
	pt.unmap(address, pgtable.uat_pgsz)
	expect_asid(7, 0)

	// Flush once per range, including a partial reprotect failure.
	assert pt.map(address, physical, 2 * pgtable.uat_pgsz, pgtable.gpu_prot_fw_gpu_cached_rw)
	expect_asid(7, unsafe { *pte })
	assert !pt.reprotect(address, 3 * pgtable.uat_pgsz, pgtable.gpu_prot_fw_gpu_shared_rw)
	expect_asid(7, unsafe { *pte })
	pt.unmap(address, 2 * pgtable.uat_pgsz)
	expect_asid(7, 0)

	// Cross an L3 boundary, fail allocation for the second page, and verify
	// rollback is visible before the caller can free the failed map's backing.
	boundary := u64(1) << 25
	rollback_pte := pt.get_pte(boundary - pgtable.uat_pgsz, true) or { panic('rollback PTE') }
	tlb.observe(rollback_pte, unsafe { nil })
	memory.fail_after(0)
	assert !pt.map(boundary - pgtable.uat_pgsz, physical, 2 * pgtable.uat_pgsz, pgtable.gpu_prot_gpu_shared_rw)
	memory.fail_after(-1)
	expect_asid(7, 0)

	pt.unbind_tlb()
	expect_asid(7, 0)
	assert pt.map(address, physical, pgtable.uat_pgsz, pgtable.gpu_prot_gpu_shared_rw)
	assert tlb.calls().len == 0
	tlb.observe(unsafe { nil }, unsafe { nil })
	pgtable.destroy(pt)
	unsafe { free(pt) }
}

fn test_root_publication_and_reuse() {
	mut lower := pgtable.new_pgtable(39, 48) or { panic('lower root') }
	mut upper := pgtable.new_pgtable(39, 48) or { panic('upper root') }
	upper.non_global = false
	mut slots := [64]mmu.SlotTtbs{}
	mut mgr := mmu.UatManager{
		kernel_lower_pgtable: lower
		kernel_pgtable:       upper
		ttbs:                 unsafe { &slots[0] }
	}
	tlb.observe(unsafe { nil }, unsafe { &u64(&slots[0]) })
	mgr.publish_roots()
	startup := tlb.calls()
	assert startup.len == 2 && !startup[0].all && startup[1].all
	assert startup[1].ttb0 == lower.l1_phys | 1
	assert startup[1].ttb1 == upper.l1_phys | 1
	tlb.clear()

	mut user := pgtable.new_pgtable(39, 48) or { panic('user root') }
	ctx := mmu.UatContext{ id: 3, pgtable: user }
	tlb.observe(unsafe { nil }, unsafe { &u64(&slots[3]) })
	mgr.bind_context(&ctx)
	bind := tlb.calls()
	assert bind.len == 1 && !bind[0].all && bind[0].asid == 3
	assert bind[0].ttb0 == user.l1_phys | (u64(3) << 48) | 1
	assert bind[0].ttb1 == 0
	tlb.clear()
	mgr.unbind_context(&ctx)
	unbind := tlb.calls()
	assert unbind.len == 1 && unbind[0].asid == 3
	assert unbind[0].ttb0 == 0 && unbind[0].ttb1 == 0
	tlb.clear()

	// The same context number, now naming another root, must invalidate even
	// when no PTE was changed. Firmware kernel aliases keep the same ASID.
	mut next := pgtable.new_pgtable(39, 48) or { panic('replacement root') }
	next_ctx := mmu.UatContext{ id: 3, pgtable: next }
	mgr.map_kernel_to_user = true
	mgr.bind_context(&next_ctx)
	reuse := tlb.calls()
	assert reuse.len == 1 && reuse[0].asid == 3
	assert reuse[0].ttb0 == next.l1_phys | (u64(3) << 48) | 1
	assert reuse[0].ttb1 == upper.l1_phys | (u64(3) << 48) | 1
	tlb.clear()
	mgr.unbind_context(&next_ctx)
	tlb.clear()

	// A global firmware mapping cannot be evicted by ASID alone.
	tlb.observe(unsafe { nil }, unsafe { nil })
	assert upper.map(0xffffffa000000000, 0x400000, pgtable.uat_pgsz, pgtable.gpu_prot_fw_private_rw)
	assert tlb.calls().len == 1 && tlb.calls()[0].all
	tlb.clear()
	assert upper.reprotect(0xffffffa000000000, pgtable.uat_pgsz, pgtable.gpu_prot_fw_shared_rw)
	assert tlb.calls().len == 1 && tlb.calls()[0].all
	tlb.clear()
	upper.unmap(0xffffffa000000000, pgtable.uat_pgsz)
	assert tlb.calls().len == 1 && tlb.calls()[0].all
	tlb.clear()
	lower.unbind_tlb()
	upper.unbind_tlb()
	tlb.clear()
	pgtable.destroy(lower)
	pgtable.destroy(upper)
	pgtable.destroy(user)
	pgtable.destroy(next)
	unsafe {
		free(lower)
		free(upper)
		free(user)
		free(next)
	}
}

fn test_gpu_permissions() {
	// Independent leaf encodings from Asahi AP_GPU=2, AttrIndx=2, AF=1,
	// GPU_ACCESS=bit55 and the PXN/UXN permission selector at bits53/54.
	modes := [pgtable.gpu_prot_gpu_shared_ro, pgtable.gpu_prot_gpu_shared_wo,
		pgtable.gpu_prot_gpu_shared_rw]!
	words := [u64(0x0080000000000488), 0x00a0000000000488, 0x00c0000000000488]!
	mut pt := pgtable.new_pgtable(39, 48) or { panic('permission page table') }
	pt.bind_tlb(11)
	tlb.clear()
	for index, mode in modes {
		assert mode == words[index]
		address := u64(0x4000) * u64(index + 1)
		physical := u64(0x200000) + u64(0x4000) * u64(index)
		assert pt.map(address, physical, pgtable.uat_pgsz, mode)
		pte := pt.get_pte(address, false) or { panic('permission PTE') }
		tlb.clear()
		tlb.observe(pte, unsafe { nil })
		assert unsafe { *pte } == physical | words[index] | u64(0x803)
		assert !pgtable.is_cached_noncoherent(unsafe { *pte })
		// Every transition replaces the selector, retaining the PA and ASID
		// scope. In particular, WO -> RW must clear PXN rather than OR bits.
		for target, next in modes {
			assert pt.reprotect(address, pgtable.uat_pgsz, mode)
			expect_asid(11, physical | words[index] | u64(0x803))
			assert pt.reprotect(address, pgtable.uat_pgsz, next)
			expect_asid(11, physical | words[target] | u64(0x803))
			assert unsafe { *pte } == physical | words[target] | u64(0x803)
		}
		pt.unmap(address, pgtable.uat_pgsz)
		expect_asid(11, 0)
		tlb.observe(unsafe { nil }, unsafe { nil })
	}
	pt.unbind_tlb()
	tlb.clear()
	pgtable.destroy(pt)
	unsafe { free(pt) }
	println('AGX GPU permissions: exact RO/WO/RW leaf words, nine reprotect transitions and visible ASID invalidations passed')
}

fn test_range_operands() {
	single := tlb.range_plan(3, 0x4000, 1) or { panic('page plan') }
	pair := tlb.range_plan(3, 0x4000, 0x8000) or { panic('range plan') }
	assert (single.operand(0) or { panic('page operand') }) == (u64(3) << 48) | 4
	assert (pair.operand(0) or { panic('range operand') }) == (u64(3) << 48) | (u64(2) << 46) | 1
	for pages in [u64(2), 31, 32, 63, 64, 2047, 2048, 65535, 65536, 1048575, 1048576, 1048577,
		4194305] {
		plan := tlb.range_plan(63, 0xffffffa000004000, pages * 16384) or { panic('range plan') }
		mut covered := u64(0)
		for index := u64(0); index < plan.count; index++ {
			operand := plan.operand(index) or { panic('range operand') }
			assert operand >> 48 == 63
			assert (operand >> 46) & 3 == 2
			assert operand & ((u64(1) << 37) - 1) == ((u64(0xffffffa000004000) >> 14) + covered) & ((u64(1) << 37) - 1)
			count := ((operand >> 39) & 31) + 1
			scale := (operand >> 44) & 3
			covered += count << (5 * scale + 1)
		}
		assert covered >= pages && covered - pages < (u64(2) << (5 * plan.scale))
		if _ := plan.operand(plan.count) {
			assert false
		}
	}
	if _ := tlb.range_plan(1, 0x4000, 0) {
		assert false
	}
	if _ := tlb.range_plan(1, ~u64(0) - 3, 5) {
		assert false
	}
	top := tlb.range_plan(1, ~u64(0) - 3, 4) or { panic('top page') }
	assert top.page
}

fn test_repeated_pages() {
	for _ in 0 .. 100 {
		mut pt := pgtable.new_pgtable(39, 48) or { panic('repeated page table') }
		address := (u64(1) << 25) - pgtable.uat_pgsz
		physical := u64(0x400000)
		first := pt.get_pte(address, true) or { panic('first repeated PTE') }
		tlb.observe(first, unsafe { nil }); pt.bind_tlb(21); expect_asid(21, 0)
		for mode in [pgtable.gpu_prot_gpu_shared_ro, pgtable.gpu_prot_gpu_shared_wo, pgtable.gpu_prot_gpu_shared_rw]! {
			for pages in [u64(1), 2, 3, 17]! {
				assert pt.map_repeated_page(address, physical, pages * pgtable.uat_pgsz, mode)
				expect_asid(21, physical | mode | pgtable.uat_pte_page | pgtable.uat_pte_ng)
				for index := u64(0); index < pages; index++ {
					pte := pt.get_pte(address + index * pgtable.uat_pgsz, false) or { panic('repeated leaf') }
					assert unsafe { *pte } == physical | mode | pgtable.uat_pte_page | pgtable.uat_pte_ng
				}
				pt.unmap(address, pages * pgtable.uat_pgsz); expect_asid(21, 0)
				for index := u64(0); index < pages; index++ {
					pte := pt.get_pte(address + index * pgtable.uat_pgsz, false) or { panic('cleared repeated leaf') }
					assert unsafe { *pte } == 0, 'every repeated alias must be removed'
				}
				assert pt.map(address, physical, pages * pgtable.uat_pgsz, mode)
				expect_asid(21, physical | mode | pgtable.uat_pte_page | pgtable.uat_pte_ng)
				for index := u64(0); index < pages; index++ {
					pte := pt.get_pte(address + index * pgtable.uat_pgsz, false) or { panic('contiguous control leaf') }
					assert unsafe { *pte } == (physical + index * pgtable.uat_pgsz) | mode | pgtable.uat_pte_page | pgtable.uat_pte_ng
				}
				pt.unmap(address, pages * pgtable.uat_pgsz); expect_asid(21, 0)
			}
		}
		rollback_address := (u64(1) << 26) - pgtable.uat_pgsz
		rollback := pt.get_pte(rollback_address, true) or { panic('repeat rollback PTE') }
		tlb.observe(rollback, unsafe { nil }); memory.fail_after(0)
		assert !pt.map_repeated_page(rollback_address, physical, 3 * pgtable.uat_pgsz, pgtable.gpu_prot_gpu_shared_rw)
		memory.fail_after(-1); expect_asid(21, 0)
		assert unsafe { *rollback } == 0
		for args in [[address + 1, physical, pgtable.uat_pgsz]!, [address, physical + 1, pgtable.uat_pgsz]!, [~u64(0) & ~pgtable.uat_pg_mask, physical, 2 * pgtable.uat_pgsz]!]! {
			assert !pt.map_repeated_page(args[0], args[1], args[2], pgtable.gpu_prot_gpu_shared_rw)
			assert tlb.calls().len == 0
		}
		pt.unbind_tlb(); expect_asid(21, 0); tlb.observe(unsafe { nil }, unsafe { nil })
		pgtable.destroy(pt); unsafe { free(pt) }
		assert memory.live_pages() == 0
	}
	println('AGX repeated PTEs: 100 cycles of exact alias leaves, RO/WO/RW, L3 boundary crossing, contiguous controls, partial rollback before one TLBI, invalid geometry and complete table release passed')
}

fn main() {
	test_repeated_pages()
	test_user_mappings()
	test_root_publication_and_reuse()
	test_gpu_permissions()
	test_range_operands()
	assert memory.live_pages() == 0
	println('AGX TLB: mapping visibility, cache transitions, rollback, globals and context reuse passed')
}
