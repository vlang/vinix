// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module gpu

import aarch64.timer
import gpu.agx.channel
import gpu.agx.fw
import gpu.agx.hw
import gpu.agx.mmu
import gpu.agx.pgtable
import gpu.agx.tlb
import memory

enum KernelTeardownCase {
	uncached
	delayed
	full
	no_handoff
	send_failure
	reprotect_failure
}

fn check_kernel_teardown() {
	for upper in [false, true]! {
		for sample in [KernelTeardownCase.uncached, .delayed, .full, .no_handoff, .send_failure,
			.reprotect_failure]! {
			kernel_teardown_case(upper, sample)
		}
	}
	assert memory.live_pages() == 0
	println('AGX kernel teardown: 12 lower/upper root cases verify slot-64 acknowledgement before unmap and final TLBI')
}

fn kernel_teardown_case(upper bool, sample KernelTeardownCase) {
	slot := u32(mmu.uat_kernel_flush_slot)
	address := if upper { u64(0xffffffa000004000) } else { u64(0x4000) }
	cached := sample != .uncached
	protection := if cached { pgtable.gpu_prot_fw_private_rw } else { pgtable.gpu_prot_fw_shared_rw }
	mut root := pgtable.new_pgtable(39, 48) or { panic('kernel page table') }
	root.non_global = !upper
	root.bind_tlb(0)
	mut handoff := mmu.UatHandoff{}
	mut table := mmu.UatManager{
		handoff: unsafe { &handoff }
		handoff_initialized: true
		ias: 39
		kernel_lower_pgtable: if upper { unsafe { nil } } else { root }
		kernel_pgtable: if upper { root } else { unsafe { nil } }
	}
	assert table.map_kernel(address, 0x200000, pgtable.uat_pgsz, protection)
	pte := root.get_pte(address, false) or { panic('kernel mapping') }
	tlb.clear()
	tlb.observe(pte, unsafe { nil })

	mut header := channel.FwCtlRingHeader{write_ptr: 255, read_ptr: if sample == .full { u32(0) } else { u32(255) }}
	mut ring := [256]fw.FwFwCtlMsg{}
	mut manager := GpuManager{
		state: .running
		hw_config: hw.HwConfig{gpu_gen: .g13}
		channels: GpuChannels{fw_ctrl: channel.new_fwctl_tx_channel('kernel', 1, u64(unsafe { &header }), 1, u64(unsafe { &ring }), 256, 20)}
		mode: match sample { .delayed { 1 } .no_handoff { 6 } .send_failure { 2 } else { 0 } }
		slot: slot
		kernel_pte: pte
	}
	mut buffer := SharedBuffer{
		va: address
		phys: 0x200000
		size: if sample == .reprotect_failure { 2 * pgtable.uat_pgsz } else { pgtable.uat_pgsz }
		protection: protection
		mapped: true
		cache_flush_pending: cached
	}
	uat_mgr = unsafe { &table }
	active = unsafe { &manager }
	timer.reset()
	timer.on_tick(poll_callback)
	defer {
		active = unsafe { nil }
		uat_mgr = unsafe { nil }
		timer.on_tick(fn () {})
		tlb.observe(unsafe { nil }, unsafe { nil })
		tlb.clear()
		pgtable.destroy(root)
	}
	manager.lock.acquire()
	defer { manager.lock.release() }

	completed := sample in [.uncached, .delayed, .full]!
	first := manager.invalidate_g13_shared_buffer(mut buffer)
	assert first == (sample in [.uncached, .delayed]!)
	if !first {
		assert buffer.mapped && buffer.cache_flush_pending && buffer.phys == 0x200000
		assert unsafe { *pte } & pgtable.uat_pte_valid != 0
		if sample == .full {
			assert manager.sends == 0 && handoff.flush[slot].state == 0 && header.write_ptr == 255
			header.read_ptr = header.write_ptr
			assert manager.invalidate_g13_shared_buffer(mut buffer)
		}
	}
	expected_sends := if sample in [.uncached, .reprotect_failure]! { 0 } else { 1 }
	if completed {
		assert !buffer.mapped && !buffer.cache_flush_pending && unsafe { *pte } == 0
		assert manager.invalidate_g13_shared_buffer(mut buffer)
		buffer.cache_flush_pending = true
		assert !manager.invalidate_g13_shared_buffer(mut buffer)
	}
	assert manager.sends == expected_sends && !manager.fwctl_lock.is_held()
	assert header.write_ptr == if expected_sends == 0 { u32(255) } else { u32(0) }
	if expected_sends != 0 {
		assert ring[255] == fw.FwFwCtlMsg{addr: address, slot: slot, page_count: 1, unk_12: 2}
	}
	assert handoff.flush[slot].state == if sample in [.no_handoff, .send_failure]! { u64(1) } else { u64(0) }
	mut calls := tlb.calls()
	defer { unsafe { calls.free() } }
	assert calls.len == if cached && completed { 2 } else { 1 }
	if cached {
		assert calls[0].pte & pgtable.uat_pte_valid != 0 && !pgtable.is_cached_noncoherent(calls[0].pte)
	}
	if completed { assert calls.last().pte == 0 }
	for call in calls {
		assert call.all == upper && call.range == !upper
		if !upper { assert call.asid == 0 && call.address == address && call.size == buffer.size }
	}
}
