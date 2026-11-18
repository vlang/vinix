@[has_globals]
module mmu

import event
import event.eventstruct
import gpu.agx.admission

pub struct UatContext {
pub mut:
	id u32 = 1
	inflight u64
	detached bool
	active bool = true
	pgtable voidptr = voidptr(1)
	binding_gate admission.Gate
}

pub enum UatHandoffAbi {
	v12_3
}

pub struct UatManager {
pub mut:
	handoff_initialized bool = true
	handoff_abi UatHandoffAbi
	occupied bool
	acquire_attempts int
	lease_count int
	release_during_bind bool
mut:
	slot_released eventstruct.Event
	owner &UatContext = unsafe { nil }
}

__global host_uat UatManager
__global uat_mgr = unsafe { &host_uat }

pub fn (mut mgr UatManager) bind_context(ctx &UatContext) u32 {
	mgr.acquire_attempts++
	if mgr.occupied {
		if mgr.release_during_bind {
			mgr.release_during_bind = false
			mgr.make_slot_available()
		}
		return 0
	}
	assert mgr.lease_count == 0
	mgr.owner = ctx
	mgr.lease_count++
	return 1
}

pub fn (mut mgr UatManager) make_slot_available() {
	mgr.occupied = false
	event.trigger_n(mut mgr.slot_released, 1)
}

pub fn (mut mgr UatManager) release_g13_slot(ctx &UatContext, slot u32) {
	assert slot == 1 && mgr.lease_count == 1 && voidptr(mgr.owner) == voidptr(ctx)
	mgr.lease_count--
	mgr.owner = unsafe { nil }
}
