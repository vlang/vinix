// SPDX-License-Identifier: GPL-2.0-or-later
module main

import gpu.agx.pgtable
import gpu.agx.mmu
import event
import gpu.agx.tlb
import memory
import aarch64.cpu

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
}

fn test_root_publication_and_reuse() {
	mut lower := pgtable.new_pgtable(39, 48) or { panic('lower root') }
	mut upper := pgtable.new_pgtable(39, 48) or { panic('upper root') }
	upper.non_global = false
	mut slots := [64]mmu.SlotTtbs{}
	mut handoff := mmu.UatHandoff{}
	mut mgr := mmu.UatManager{
		kernel_lower_pgtable: lower
		kernel_pgtable:       upper
		ttbs:                 unsafe { &slots[0] }
		handoff:              &handoff
	}
	tlb.observe(unsafe { nil }, unsafe { &u64(&slots[0]) })
	mgr.publish_roots()
	startup := tlb.calls()
	assert startup.len == 2 && !startup[0].all && startup[1].all
	assert startup[1].ttb0 == lower.l1_phys | 1
	assert startup[1].ttb1 == upper.l1_phys | 1
	tlb.clear()

	mut user := pgtable.new_pgtable(39, 48) or { panic('user root') }
	ctx := mmu.UatContext{ id: 65, pgtable: user }
	tlb.observe(unsafe { nil }, unsafe { &u64(&slots[1]) })
	assert !ctx.is_bound() && ctx.bound_slot() == 0
	assert user.map(0x4000, 0x200000, pgtable.uat_pgsz, pgtable.gpu_prot_gpu_shared_rw)
	assert slots[1].ttb0 == 0 && tlb.calls().len == 0
	mgr.unbind_context(&ctx)
	assert tlb.calls().len == 0
	assert mgr.bind_context(&ctx) == 1 && ctx.is_bound() && ctx.bound_slot() == 1
	assert mgr.bind_context(&ctx) == 1 // Additional jobs reuse the published root.
	bind := tlb.calls()
	assert bind.len == 1 && !bind[0].all && bind[0].asid == 1
	assert bind[0].ttb0 == user.l1_phys | (u64(1) << 48) | 1
	assert bind[0].ttb1 == 0
	tlb.clear()

	// The ASID alone never identifies the ASC's cache owner.
	saved_root := slots[1].ttb0
	for current in [u32(0), 1, 2, 63, ~u32(0)]! {
		handoff.cur_slot = current
		for root in [saved_root, saved_root ^ pgtable.uat_pgsz]! {
			slots[1].ttb0 = root
			required := mgr.g13_cache_flush_required(&ctx, 1) or { panic('valid G13 root snapshot') }
			assert required == (current == 1 && root == saved_root)
		}
	}
	slots[1].ttb0 = saved_root
	other := mmu.UatContext{pgtable: user}
	if _ := mgr.g13_cache_flush_required(&other, 1) { panic('borrowed a different VM root') }
	if _ := mgr.g13_cache_flush_required(&ctx, 64) { panic('indexed a non-user slot') }
	mgr.handoff_initialized = false
	if _ := mgr.g13_cache_flush_required(&ctx, 1) { panic('read an uninitialized handoff') }
	mgr.handoff_initialized = true
	assert tlb.calls().len == 0
	println('AGX UAT cache ownership: active slot and exact published TTBR must match before FwCtl')

	mgr.release_g13_slot(&ctx, 1)
	mgr.release_g13_slot(&ctx, 1)
	mgr.unbind_context(&ctx)
	unbind := tlb.calls()
	assert unbind.len == 1 && unbind[0].asid == 1
	assert unbind[0].ttb0 == 0 && unbind[0].ttb1 == 0
	tlb.clear()

	// An unused slot is older than the slot cleared above. Firmware kernel
	// aliases use the new root's ASID.
	mut next := pgtable.new_pgtable(39, 48) or { panic('replacement root') }
	next_ctx := mmu.UatContext{ id: 129, pgtable: next }
	mgr.map_kernel_to_user = true
	tlb.observe(unsafe { nil }, unsafe { &u64(&slots[2]) })
	assert mgr.bind_context(&next_ctx) == 2
	reuse := tlb.calls()
	assert reuse.len == 1 && reuse[0].asid == 2
	assert reuse[0].ttb0 == next.l1_phys | (u64(2) << 48) | 1
	assert reuse[0].ttb1 == upper.l1_phys | (u64(2) << 48) | 1
	tlb.clear()
	assert next_ctx.bound_slot() == 2
	mgr.release_g13_slot(&next_ctx, 2)
	mgr.unbind_context(&next_ctx)
	assert next_ctx.bound_slot() == 0 && mgr.contexts[2] == unsafe { nil }
	cleared := tlb.calls()
	assert cleared.len == 1 && cleared[0].asid == 2
	assert cleared[0].ttb0 == 0 && cleared[0].ttb1 == 0
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
}

fn test_user_slot_capacity() {
	upper := pgtable.new_pgtable(39, 48) or { panic('kernel alias root') }
	mut slots := [64]mmu.SlotTtbs{}
	mut handoff := mmu.UatHandoff{}
	mut contexts := [65]mmu.UatContext{}
	mut mgr := mmu.UatManager{
		handoff_initialized: true
		ttbs: unsafe { &slots[0] }
		handoff: &handoff
		kernel_pgtable: upper
		map_kernel_to_user: true
	}
	for index in 0 .. contexts.len {
		contexts[index].id = u32(1000 + index)
		contexts[index].pgtable = pgtable.new_pgtable(39, 48) or { panic('user root') }
		expected := if index < 63 { u32(index + 1) } else { u32(0) }
		assert mgr.bind_context(unsafe { &contexts[index] }) == expected
	}
	assert contexts[63].bound_slot() == 0 && slots[0].ttb0 == 0
	assert tlb.calls().len == 63
	tlb.clear()
	generation := mgr.release_generation()
	wakes_before := event.single_wakes()
	assert mgr.bind_context(unsafe { &contexts[0] }) == 1
	mgr.release_g13_slot(unsafe { &contexts[0] }, 1)
	assert mgr.release_generation() == generation
	assert mgr.bind_context(unsafe { &contexts[63] }) == 0, 'one surviving job keeps the slot'
	mgr.release_g13_slot(unsafe { &contexts[0] }, 1)
	mgr.release_g13_slot(unsafe { &contexts[1] }, 2)
	assert mgr.release_generation() == generation + 2
	handoff.cur_slot = 1
	handoff.flush[2].state = 1
	assert mgr.bind_context(unsafe { &contexts[63] }) == 0, 'ASC and FWCTL owners exclude idle roots'
	mgr.release_g13_slot(unsafe { &contexts[2] }, 3)
	mgr.release_g13_slot(unsafe { &contexts[3] }, 4)
	assert mgr.release_generation() == generation + 4
	assert event.single_wakes() == wakes_before + 4
	tlb.observe(unsafe { nil }, unsafe { &u64(&slots[3]) })
	assert mgr.bind_context(unsafe { &contexts[63] }) == 3
	assert contexts[2].bound_slot() == 0 && contexts[3].bound_slot() == 4
	assert contexts[0].bound_slot() == 1 && contexts[1].bound_slot() == 2
	replaced := tlb.calls()
	assert replaced.len == 1 && replaced[0].asid == 3
	assert replaced[0].ttb0 == contexts[63].pgtable.l1_phys | (u64(3) << 48) | 1
	assert replaced[0].ttb1 == upper.l1_phys | (u64(3) << 48) | 1
	tlb.clear()
	assert contexts[2].pgtable.map(0x4000, 0x200000, pgtable.uat_pgsz, pgtable.gpu_prot_gpu_shared_rw)
	assert tlb.calls().len == 0, 'edits of the displaced root leave the new ASID alone'
	assert contexts[63].pgtable.map(0x4000, 0x400000, pgtable.uat_pgsz, pgtable.gpu_prot_gpu_shared_rw)
	assert tlb.calls().len == 1 && tlb.calls()[0].asid == 3
	// The surviving idle VM can borrow its cached slot without changing its
	// root. A previously evicted VM gets a new binding epoch on return.
	tlb.clear()
	assert mgr.bind_context(unsafe { &contexts[3] }) == 4 && contexts[3].binding_epoch == 1
	assert tlb.calls().len == 0
	mgr.release_g13_slot(unsafe { &contexts[3] }, 4)
	assert mgr.bind_context(unsafe { &contexts[2] }) == 4 && contexts[2].binding_epoch == 2
	assert contexts[3].bound_slot() == 0
	assert mgr.bind_context(unsafe { &contexts[64] }) == 0
	tlb.clear()
	tlb.observe(unsafe { nil }, unsafe { nil })
	mgr.release_g13_slot(unsafe { &contexts[63] }, 3)
	mgr.release_g13_slot(unsafe { &contexts[2] }, 4)
	mgr.unbind_context(unsafe { &contexts[2] })
	assert mgr.bind_context(unsafe { &contexts[64] }) == 3, 'clearing a newer slot preserves its release age'
	assert contexts[63].bound_slot() == 0 && slots[4].ttb0 == 0
	handoff.cur_slot = 0
	handoff.flush[2].state = 0
	for index in 0 .. contexts.len {
		slot := contexts[index].bound_slot()
		if slot != 0 && index != 0 && index != 1 {
			mgr.release_g13_slot(unsafe { &contexts[index] }, slot)
		}
		mgr.unbind_context(unsafe { &contexts[index] })
		pgtable.destroy(contexts[index].pgtable)
		tlb.clear()
	}
	pgtable.destroy(upper)
	println('AGX UAT leases: 63 active roots, overlapping users, cached-root reuse, release age across root removal, ASC/FWCTL exclusion and one-invalidation rebind passed')
}

fn test_stopped_slot_retirement() {
	for _ in 0 .. 64 {
		mut slots := [64]mmu.SlotTtbs{}
		mut handoff := mmu.UatHandoff{}
		mut new_handoff := mmu.UatHandoff{}
		upper := pgtable.new_pgtable(39, 48) or { panic('upper root') }
		leased := mmu.UatContext{pgtable: pgtable.new_pgtable(39, 48) or { panic('leased root') }}
		idle := mmu.UatContext{pgtable: pgtable.new_pgtable(39, 48) or { panic('idle root') }}
		reused := mmu.UatContext{pgtable: pgtable.new_pgtable(39, 48) or { panic('replacement root') }}
		mut original := mmu.UatManager{
			ttbs: unsafe { &slots[0] }
			handoff: unsafe { &handoff }
			kernel_pgtable: upper
			map_kernel_to_user: true
			handoff_initialized: true
		}
		slots[0].ttb0 = 0x400001
		assert original.bind_context(&leased) == 1 && original.bind_context(&leased) == 1
		assert original.bind_context(&idle) == 2
		assert slots[1].ttb1 != 0 && slots[2].ttb1 != 0
		original.release_g13_slot(&idle, 2)
		tlb.clear()
		tlb.observe(unsafe { nil }, unsafe { &u64(&slots[1]) })
		handoff.held = true
		before := original.release_generation()
		original.lock.acquire()
		original.retire_g13_slots_locked()
		original.lock.release()
		cleared := tlb.calls()
		assert cleared.len == 2 && cleared[0].asid == 1 && cleared[1].asid == 2
		assert cleared[0].ttb0 == 0 && cleared[0].ttb1 == 0
		assert leased.bound_slot() == 0 && idle.bound_slot() == 0
		assert voidptr(original.contexts[1]) == voidptr(&leased) && original.contexts[2] == unsafe { nil }
		assert slots[0].ttb0 == 0x400001 && slots[1].ttb0 == 0 && slots[2].ttb0 == 0
		assert slots[1].ttb1 == 0 && slots[2].ttb1 == 0
		assert original.release_generation() == before + 1 && handoff.held
		original.lock.acquire()
		original.retire_g13_slots_locked()
		original.lock.release()
		assert original.release_generation() == before + 1 && tlb.calls().len == 2
		assert original.bind_context(&leased) == 0 && original.bind_context(&idle) == 0

		tlb.clear()
		mut replacement := mmu.UatManager{
			ttbs: unsafe { &slots[0] }
			handoff: unsafe { &new_handoff }
			kernel_pgtable: upper
			map_kernel_to_user: true
			handoff_initialized: true
		}
		assert replacement.bind_context(&reused) == 1
		published := slots[1].ttb0
		published_upper := slots[1].ttb1
		tlb.clear()
		original.release_g13_slot(&leased, 1)
		assert voidptr(original.contexts[1]) == voidptr(&leased)
		original.release_g13_slot(&leased, 1)
		original.unbind_context(&leased)
		pgtable.destroy(leased.pgtable)
		pgtable.destroy(idle.pgtable)
		assert original.contexts[1] == unsafe { nil } && original.release_generation() == before + 1
		assert slots[1].ttb0 == published && slots[1].ttb1 == published_upper && tlb.calls().len == 0
		replacement.release_g13_slot(&reused, 1)
		replacement.unbind_context(&reused)
		pgtable.destroy(reused.pgtable)
		pgtable.destroy(upper)
		tlb.clear()
		tlb.observe(unsafe { nil }, unsafe { nil })
		assert memory.live_pages() == 0
	}
	println('AGX UAT shutdown: 64 retirements clear resident roots, wake slot waiters, keep late leases on the old UAT and preserve replacement roots')
}

fn test_borrowed_root_destruction() {
	root := pgtable.alloc_table_page() or { panic('bootloader root') }
	subtree := pgtable.alloc_table_page() or { panic('bootloader subtree') }
	unsafe { root[2] = u64(subtree) | pgtable.uat_pte_table }
	borrowed := pgtable.new_pgtable_with_root(u64(root), 39, 48) or { panic('borrowed root') }
	pgtable.destroy(borrowed)
	assert memory.live_pages() == 2
	assert unsafe { root[2] } == u64(subtree) | pgtable.uat_pte_table
	pgtable.free_table_page(subtree)
	pgtable.free_table_page(root)
}

fn test_eager_bindings_hold_slots_until_destroy() {
	mut slots := [64]mmu.SlotTtbs{}
	mut handoff := mmu.UatHandoff{}
	mut contexts := [64]mmu.UatContext{}
	mut mgr := mmu.UatManager{
		handoff_initialized: true
		handoff_abi: .g17_26_5
		ttbs: unsafe { &slots[0] }
		handoff: &handoff
	}
	for index in 0 .. contexts.len {
		contexts[index].pgtable = pgtable.new_pgtable(39, 48) or { panic('user root') }
		expected := if index < 63 { u32(index + 1) } else { u32(0) }
		assert mgr.bind_context(unsafe { &contexts[index] }) == expected
	}
	for index in 0 .. contexts.len {
		mgr.unbind_context(unsafe { &contexts[index] })
		pgtable.destroy(contexts[index].pgtable)
	}
	tlb.clear()
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
		pgtable.destroy(pt)
		assert memory.live_pages() == 0
	}
	println('AGX repeated PTEs: 100 cycles of exact alias leaves, RO/WO/RW, L3 boundary crossing, contiguous controls, partial rollback before one TLBI, invalid geometry and complete table release passed')
}

fn test_partial_unmap_survivors() {
	for _ in 0 .. 100 {
		for repeated in [false, true]! {
			for mode in [pgtable.gpu_prot_gpu_shared_ro, pgtable.gpu_prot_gpu_shared_wo, pgtable.gpu_prot_gpu_shared_rw]! {
				for cut in [[u64(0), 1]!, [u64(7), 8]!, [u64(2), 5]!, [u64(0), 8]!]! {
					mut pt := pgtable.new_pgtable(39, 48) or { panic('partial unmap table') }
					address := (u64(1) << 25) - pgtable.uat_pgsz
					physical := u64(0x400000)
					first := pt.get_pte(address, true) or { panic('partial unmap PTE') }
					tlb.observe(first, unsafe { nil }); pt.bind_tlb(22); expect_asid(22, 0)
					if repeated { assert pt.map_repeated_page(address, physical, 8 * pgtable.uat_pgsz, mode) }
					else { assert pt.map(address, physical, 8 * pgtable.uat_pgsz, mode) }
					first_word := physical | mode | pgtable.uat_pte_page | pgtable.uat_pte_ng
					expect_asid(22, first_word)
					pt.unmap(address + cut[0] * pgtable.uat_pgsz, (cut[1] - cut[0]) * pgtable.uat_pgsz)
					expect_asid(22, if cut[0] == 0 { u64(0) } else { first_word })
					for index := u64(0); index < 8; index++ {
						pte := pt.get_pte(address + index * pgtable.uat_pgsz, false) or { panic('survivor PTE') }
						phys := physical + if repeated { u64(0) } else { index * pgtable.uat_pgsz }
						expected := if index >= cut[0] && index < cut[1] { u64(0) }
							else { phys | mode | pgtable.uat_pte_page | pgtable.uat_pte_ng }
						assert unsafe { *pte } == expected
					}
					pt.unmap(address, 8 * pgtable.uat_pgsz); expect_asid(22, 0)
					pt.unbind_tlb(); expect_asid(22, 0); tlb.observe(unsafe { nil }, unsafe { nil })
					pgtable.destroy(pt)
					assert memory.live_pages() == 0
				}
			}
		}
	}
	println('AGX partial unmap PTEs: 100 cycles of head/tail/middle/full cuts preserve exact contiguous/repeated RO/WO/RW survivor leaves across L3 boundaries before TLBI and free every table')
}

fn test_child_table_publication() {
	mut pt := pgtable.new_pgtable(39, 48) or { panic('publication root') }
	address := pgtable.uat_pgsz
	cpu.watch_descriptor(pt.l1)
	memory.fail_after(0)
	assert !pt.prepare_map_range(address, pgtable.uat_pgsz)
	_, no_root_barrier := cpu.descriptor_at_barrier()
	assert no_root_barrier == 0 && unsafe { *pt.l1 } == 0

	// Publish an L2 table, then fail before its L3 table is allocated.
	memory.fail_after(1)
	assert !pt.prepare_map_range(address, pgtable.uat_pgsz)
	root_at_barrier, root_barriers := cpu.descriptor_at_barrier()
	assert root_at_barrier == 0 && root_barriers == 1, 'L2 child must be synchronized before its parent store'
	root_descriptor := unsafe { *pt.l1 }
	assert root_descriptor & pgtable.uat_pte_page == pgtable.uat_pte_page
	middle := unsafe { &u64(root_descriptor & pt.oas_mask & ~pgtable.uat_pg_mask) }
	assert unsafe { *middle } == 0

	cpu.watch_descriptor(middle)
	memory.fail_after(-1)
	assert pt.prepare_map_range(address, pgtable.uat_pgsz)
	middle_at_barrier, middle_barriers := cpu.descriptor_at_barrier()
	assert middle_at_barrier == 0 && middle_barriers == 1, 'L3 child must be synchronized before its parent store'
	assert unsafe { *middle } & pgtable.uat_pte_page == pgtable.uat_pte_page
	assert (pt.read_pte(address) or { panic('prepared leaf') }) == 0 && tlb.calls().len == 0
	assert pt.prepare_map_range(address, pgtable.uat_pgsz)
	_, barriers_after_reuse := cpu.descriptor_at_barrier()
	assert barriers_after_reuse == middle_barriers
	cpu.watch_descriptor(unsafe { nil })
	pgtable.destroy(pt)
	assert memory.live_pages() == 0
	println('AGX child tables: one barrier before publishing each level, none on failure or reuse')
}

fn check_reserved_descriptor(level int, kind u64) {
	owner := pgtable.new_pgtable(39, 48) or { panic('root backing') }
	mut pt := pgtable.new_pgtable_with_root(owner.l1_phys, 39, 48) or { panic('borrowed root') }
	address := u64(0xffffffa000004000)
	span := if level == 1 { u64(1) << 36 } else { u64(1) << 25 }
	neighbor := address + span
	page := pgtable.uat_pgsz
	protection := pgtable.gpu_prot_fw_shared_rw
	assert pt.map(neighbor, 0x200000, page, protection)
	neighbor_pte := pt.read_pte(neighbor) or { panic('neighbor leaf') }
	root_slot := unsafe { &pt.l1[(address >> 36) & 7] }
	mut descriptor := if level == 1 { root_slot } else {
		unsafe { &u64(*root_slot & pt.oas_mask & ~pgtable.uat_pg_mask) }
	}
	assert unsafe { *descriptor } == 0
	backing := pgtable.alloc_table_page() or { panic('block backing') }
	old := u64(backing) | kind
	unsafe {
		*descriptor = old
		backing[2] = 0x600000
	}
	before := memory.live_pages()
	if _ := pt.read_pte(address) { panic('non-table descriptor returned as a leaf') }
	assert !pt.prepare_map_range(address, page)
	assert !pt.map(address, 0x400000, page, protection)
	assert !pt.map_repeated_page(address, 0x400000, page, protection)
	assert !pt.reprotect(address, page, pgtable.gpu_prot_fw_private_rw)
	pt.unmap(address, page)
	assert unsafe { *descriptor } == old, 'non-table intermediate descriptor changed'
	assert unsafe { backing[0] == 0 && backing[2] == 0x600000 }
	assert memory.live_pages() == before
	assert (pt.read_pte(neighbor) or { panic('neighbor leaf lost') }) == neighbor_pte

	pgtable.destroy(pt)
	pgtable.destroy(owner)
	assert memory.live_pages() == 1, 'table destruction must preserve non-table backing'
	pgtable.free_table_page(backing)
	assert memory.live_pages() == 0
}

fn test_reserved_descriptors() {
	for level in [1, 2]! {
		for kind in [u64(0), 1, 2]! {
			check_reserved_descriptor(level, kind)
		}
	}
	println('AGX intermediate descriptors: six borrowed TTBR1 cases preserve non-table entries, backing and adjacent leaves')
}

fn test_preparation_boundaries() {
	page := pgtable.uat_pgsz
	root_boundary := u64(1) << 36
	start := root_boundary - page
	mut pt := pgtable.new_pgtable(39, 48) or { panic('boundary root') }
	assert pt.prepare_map_range(start, 2 * page)
	assert memory.live_pages() == 5 && tlb.calls().len == 0
	memory.fail_after(0)
	assert pt.map(start, 0x400000, 2 * page, pgtable.gpu_prot_gpu_shared_rw)
	memory.fail_after(-1)
	// Preparation must terminate at the final page without adding its size.
	top := ~pgtable.uat_pg_mask
	assert pt.prepare_map_range(top, page)
	assert (pt.read_pte(top) or { panic('last prepared leaf') }) == 0
	assert memory.live_pages() == 7 && tlb.calls().len == 0
	pgtable.destroy(pt)
	assert memory.live_pages() == 0
	println('AGX table preparation: covers a root boundary and the last TTBR1 page')
}

fn check_kernel_map_preflight(upper bool) {
	page := pgtable.uat_pgsz
	span := u64(1) << 25
	base := if upper { u64(0xffffffa000000000) } else { u64(0) }
	start := base + span - page
	mut pt := pgtable.new_pgtable(39, 48) or { panic('kernel root') }
	pt.non_global = !upper
	mut mgr := mmu.UatManager{
		ias: 39
		handoff_abi: .v12_3
		kernel_lower_pgtable: if upper { unsafe { nil } } else { pt }
		kernel_pgtable: if upper { pt } else { unsafe { nil } }
	}
	prot := pgtable.gpu_prot_fw_shared_rw
	assert mgr.map_kernel(start + page, 0x200000, page, prot)
	collision := pt.get_pte(start + page, false) or { panic('occupied PTE') }
	saved := unsafe { *collision }
	pt.bind_tlb(0)
	tlb.clear()
	tlb.observe(collision, unsafe { nil })
	before := memory.live_pages()
	assert mgr.map_kernel_status(start, 0x800001, page, prot) == -22
	assert memory.live_pages() == before && tlb.calls().len == 0
	for occupied in [saved, u64(0x4000)]! {
		unsafe { *collision = occupied }
		assert mgr.map_kernel_status(start, 0x800000, 2 * page, prot) == -16
		assert !mgr.map_kernel(start, 0x800000, 2 * page, prot), 'collision must fail before preparing earlier tables'
		assert unsafe { *collision } == occupied && tlb.calls().len == 0
		assert memory.live_pages() == before
		if _ := pt.get_pte(start, false) { panic('earlier table allocated before vacancy check finished') }
	}
	unsafe { *collision = saved }

	// G17 uses a different handoff path and keeps its existing map semantics.
	mgr.handoff_abi = .g17_26_5
	assert mgr.map_kernel(start + page, 0x400000, page, prot)
	assert (pt.translate(start + page) or { panic('updated G17 PTE') }) == 0x400000
	mgr.handoff_abi = .v12_3
	tlb.clear()

	// Fail the second table allocation with the first table already attached.
	oom_start := start + 2 * span
	memory.fail_after(1)
	assert mgr.map_kernel_status(oom_start, 0x800000, 2 * page, prot) == -12
	assert memory.live_pages() == before + 1 && tlb.calls().len == 0
	first := pt.get_pte(oom_start, false) or { panic('retained empty table') }
	assert unsafe { *first } == 0
	if _ := pt.get_pte(oom_start + page, false) { panic('out of memory at second table') }
	memory.fail_after(-1)
	tlb.observe(first, unsafe { nil })
	assert mgr.map_kernel(oom_start, 0x800000, 2 * page, prot)
	assert (pt.translate(oom_start + page) or { panic('installed final page') }) == 0x800000 + page
	calls := tlb.calls()
	assert calls.len == 1 && calls[0].all == upper
	assert calls[0].pte == unsafe { *first } && calls[0].pte != 0
	tlb.observe(unsafe { nil }, unsafe { nil })
	pt.unbind_tlb()
	tlb.clear()
	pgtable.destroy(pt)
	assert memory.live_pages() == 0
}

fn test_kernel_map_preflight() {
	for upper in [false, true]! {
		check_kernel_map_preflight(upper)
	}
	println('AGX kernel mapping: TTBR0 and TTBR1 preflight distinguish EINVAL, EBUSY and ENOMEM, preserving occupied leaves and keeping failed preparation empty')
}

fn test_bind_preparation() {
	for _ in 0 .. 100 {
		memory.fail_after(0)
		if _ := pgtable.new_pgtable(39, 48) { panic('root OOM must be fallible') }
		memory.fail_after(-1)
		assert memory.live_pages() == 0
		for repeated in [false, true]! {
			mut pt := pgtable.new_pgtable(39, 48) or { panic('prepare table') }
			address := (u64(1) << 25) - pgtable.uat_pgsz
			physical := u64(0x400000)
			first := pt.get_pte(address, true) or { panic('original leaf') }
			tlb.observe(first, unsafe { nil }); pt.bind_tlb(23); expect_asid(23, 0)
			assert pt.map(address, physical, pgtable.uat_pgsz, pgtable.gpu_prot_gpu_shared_ro)
			old_word := physical | pgtable.gpu_prot_gpu_shared_ro | pgtable.uat_pte_page | pgtable.uat_pte_ng
			expect_asid(23, old_word)
			before := memory.live_pages()
			memory.fail_after(0)
			assert !pt.prepare_map_range(address, 3 * pgtable.uat_pgsz)
			assert memory.live_pages() == before && unsafe { *first } == old_word && tlb.calls().len == 0
			// Attach the next L3 table, then fail at the following boundary.
			span := u64(2050) * pgtable.uat_pgsz
			memory.fail_after(1)
			assert !pt.prepare_map_range(address, span)
			assert memory.live_pages() == before + 1 && unsafe { *first } == old_word && tlb.calls().len == 0
			prepared := pt.get_pte(address + pgtable.uat_pgsz, false) or { panic('retained empty table') }
			assert unsafe { *prepared } == 0
			memory.fail_after(-1)
			assert pt.prepare_map_range(address, span) && unsafe { *first } == old_word && tlb.calls().len == 0
			// Clearing old leaves retains topology. Both final map paths must
			// finish with the physical allocator now forced to fail every call.
			memory.fail_after(0)
			pt.unmap(address, pgtable.uat_pgsz); expect_asid(23, 0)
			new_physical := u64(0x800000)
			if repeated { assert pt.map_repeated_page(address, new_physical, span, pgtable.gpu_prot_gpu_shared_wo) }
			else { assert pt.map(address, new_physical, span, pgtable.gpu_prot_gpu_shared_wo) }
			expect_asid(23, new_physical | pgtable.gpu_prot_gpu_shared_wo | pgtable.uat_pte_page | pgtable.uat_pte_ng)
			for index := u64(0); index < 2050; index++ {
				pte := pt.get_pte(address + index * pgtable.uat_pgsz, false) or { panic('prepared replacement leaf') }
				phys := new_physical + if repeated { u64(0) } else { index * pgtable.uat_pgsz }
				assert unsafe { *pte } == phys | pgtable.gpu_prot_gpu_shared_wo | pgtable.uat_pte_page | pgtable.uat_pte_ng
			}
			for invalid in [[address, u64(0)]!, [address + 1, pgtable.uat_pgsz]!, [address, pgtable.uat_pgsz + 1]!,
				[~u64(0) & ~pgtable.uat_pg_mask, 2 * pgtable.uat_pgsz]!]! {
				assert !pt.prepare_map_range(invalid[0], invalid[1]) && tlb.calls().len == 0
			}
			memory.fail_after(-1)
			pt.unmap(address, span); expect_asid(23, 0)
			pt.unbind_tlb(); expect_asid(23, 0); tlb.observe(unsafe { nil }, unsafe { nil })
			pgtable.destroy(pt)
			assert memory.live_pages() == 0
		}
	}
	println('AGX BIND preparation: 100 cycles of fallible root/table allocation, preserved old leaves on partial preparation failure, retained empty tables, allocation-free contiguous/repeated replacement across L3 boundaries and complete destruction passed')
}

fn main() {
	test_child_table_publication()
	test_reserved_descriptors()
	test_preparation_boundaries()
	test_kernel_map_preflight()
	test_bind_preparation()
	test_partial_unmap_survivors()
	test_repeated_pages()
	test_user_mappings()
	test_root_publication_and_reuse()
	test_user_slot_capacity()
	test_stopped_slot_retirement()
	test_eager_bindings_hold_slots_until_destroy()
	test_borrowed_root_destruction()
	test_gpu_permissions()
	test_range_operands()
	assert memory.live_pages() == 0
	println('AGX TLB: mapping visibility, cache transitions, rollback, globals and context reuse passed')
}
