module mmu

import gpu.agx.pgtable
import klock

pub const uat_num_contexts = 64
const ttbr_valid = u64(1)
const ttbr_asid_shift = 48

pub struct SlotTtbs {
pub mut:
	ttb0 u64
	ttb1 u64
}

pub struct UatContext {
pub mut:
	id      u32
	pgtable &pgtable.UatPgtable = unsafe { nil }
}

pub struct UatManager {
pub mut:
	kernel_lower_pgtable &pgtable.UatPgtable = unsafe { nil }
	kernel_pgtable       &pgtable.UatPgtable = unsafe { nil }
	ttbs                 &SlotTtbs           = unsafe { nil }
	handoff              voidptr
	handoff_initialized  bool
	map_kernel_to_user   bool
	lock klock.Lock
}

fn handoff_lock(_h voidptr) {}

fn handoff_unlock(_h voidptr) {}

pub fn (mut mgr UatManager) publish_roots() {
	mgr.publish_initial_context_roots()
	mgr.handoff_initialized = true
}
