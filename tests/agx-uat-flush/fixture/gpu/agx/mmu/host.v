module mmu

import gpu.agx.pgtable

pub const uat_num_contexts = 64
pub const uat_kernel_flush_slot = 64

pub struct UatManager {
pub mut:
	handoff &UatHandoff = unsafe { nil }
	handoff_initialized bool
	ias u32
	kernel_lower_pgtable &pgtable.UatPgtable = unsafe { nil }
	kernel_pgtable &pgtable.UatPgtable = unsafe { nil }
}
