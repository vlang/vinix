module mmu

import gpu.agx.gpu
import gpu.agx.pgtable

pub const uat_num_contexts = 64

pub struct UatManager {}

pub struct UatContext {
pub mut:
	id u32
	pgtable &pgtable.UatPgtable = unsafe { nil }
	kernel_start u64 = 0x100000000
	kernel_end u64 = 0x120000000
	destroyed bool
	queue     &gpu.G13QueueResources = unsafe { nil }
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
