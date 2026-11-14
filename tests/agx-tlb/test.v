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

fn main() {
	test_user_mappings()
	test_root_publication_and_reuse()
	assert memory.live_pages() == 0
	println('AGX TLB: mapping visibility, cache transitions, rollback, globals and context reuse passed')
}
