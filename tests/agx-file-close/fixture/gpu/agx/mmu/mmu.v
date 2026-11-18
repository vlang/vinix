module mmu

import gpu.agx.gpu
import gpu.agx.pgtable

pub const uat_num_contexts = 64

pub enum UatHandoffAbi {
	v12_3
	g17_26_5
}

pub struct UatManager {
pub mut:
	handoff_abi UatHandoffAbi
	timestamp_map_calls int
	timestamp_unmap_calls int
	timestamp_reject bool
	ias u32 = 39
	next_context &UatContext = unsafe { nil }
	vm_binds int
}

pub fn (mgr &UatManager) map_kernel(va u64, phys u64, size u64, prot u64) bool {
	assert gpu.timestamp_lock_held() && va != 0 && phys != 0 && size == 0x4000
	assert prot == pgtable.gpu_prot_fw_shared_rw
	mut owned := unsafe { mgr }; owned.timestamp_map_calls++
	return !mgr.timestamp_reject
}

pub fn (mgr &UatManager) unmap_kernel(va u64, size u64) {
	assert gpu.timestamp_lock_held() && va != 0 && size == 0x4000
	mut owned := unsafe { mgr }; owned.timestamp_unmap_calls++
}

pub struct UatContext {
pub mut:
	id u32
	vm_id u32
	inflight u64
	detached bool
	identity u64
	pgtable &pgtable.UatPgtable = unsafe { nil }
	kernel_start u64 = 0x100000000
	kernel_end u64 = 0x120000000
	destroyed bool
	queue     &gpu.G13QueueResources = unsafe { nil }
}

pub fn new_identity() u64 { return allocate_context_identity() or { panic('VM identity') } }

pub fn (mut mgr UatManager) create_context(start u64, end u64) ?&UatContext {
	assert start < end
	ctx := mgr.next_context
	if ctx == unsafe { nil } { return none }
	mgr.next_context = unsafe { nil }
	if ctx.pgtable != unsafe { nil } {
		mut table := unsafe { ctx.pgtable }
		table.tlb_bound = false
	}
	return unsafe { ctx }
}

pub fn (ctx &UatContext) is_bound() bool {
	return ctx.pgtable != unsafe { nil } && ctx.pgtable.tlb_bound
}

pub fn (ctx &UatContext) bound_slot() u32 {
	return if ctx.is_bound() { u32(ctx.pgtable.tlb_asid) } else { u32(0) }
}

pub fn (mut mgr UatManager) bind_context(ctx &UatContext) u32 {
	assert ctx.id != 0 && ctx.vm_id != 0 && !ctx.destroyed
	if ctx.pgtable == unsafe { nil } { return 0 }
	mut table := unsafe { ctx.pgtable }
	table.tlb_asid = 1
	table.tlb_bound = true
	mgr.vm_binds++
	return 1
}

pub fn (mut vm_manager UatManager) destroy_context(context &UatContext) {
	mut owned := unsafe { context }
	assert owned.queue == unsafe { nil } || owned.queue.released, 'VM destroyed while queue backing is retained'
	assert !owned.destroyed, 'VM destroyed twice during close retry'
	owned.destroyed = true
	if owned.pgtable != unsafe { nil } {
		mut pt := unsafe { owned.pgtable }
		pt.destroyed = true
	}
}
