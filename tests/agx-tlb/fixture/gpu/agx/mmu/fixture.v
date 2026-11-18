module mmu

import gpu.agx.pgtable
import klock
import event.eventstruct

pub const uat_num_contexts = 64
const ttbr_valid = u64(1)
const ttbr_asid_shift = 48

pub enum UatHandoffAbi {
	v12_3
	g17_26_5
}

pub struct UatFlushInfo {
pub mut:
	state u64
}

pub struct UatHandoff {
pub mut:
	cur_slot u32
	flush [uat_num_contexts + 1]UatFlushInfo
	held bool
}

pub struct SlotTtbs {
pub mut:
	ttb0 u64
	ttb1 u64
}

pub struct UatContext {
pub mut:
	id      u32
	active  bool = true
	binding_epoch u64
	pgtable &pgtable.UatPgtable = unsafe { nil }
}

pub struct UatManager {
pub mut:
	contexts             [uat_num_contexts]&UatContext
	kernel_lower_pgtable &pgtable.UatPgtable = unsafe { nil }
	kernel_pgtable       &pgtable.UatPgtable = unsafe { nil }
	ttbs                 &SlotTtbs           = unsafe { nil }
	handoff              &UatHandoff = unsafe { nil }
	ias                  u32
	handoff_initialized  bool
	handoff_abi          UatHandoffAbi
	map_kernel_to_user   bool
	lock klock.Lock
mut:
	slot_users [uat_num_contexts]u64
	slot_release [uat_num_contexts]u64
	slot_release_clock u64
	slot_released eventstruct.Event
	g13_slots_retired bool
}

pub fn (mgr &UatManager) release_generation() u64 { return mgr.slot_released.generation }

fn handoff_lock(h &UatHandoff) {
	assert !h.held
	mut shared := unsafe { h }
	shared.held = true
}

fn handoff_unlock(h &UatHandoff) {
	assert h.held
	mut shared := unsafe { h }
	shared.held = false
}

pub fn (mut mgr UatManager) publish_roots() {
	mgr.publish_initial_context_roots()
	mgr.handoff_initialized = true
}
