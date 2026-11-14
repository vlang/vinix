module mmu

import gpu.agx.gpu

pub const uat_num_contexts = 64

pub struct UatManager {}

pub struct UatContext {
pub mut:
	destroyed bool
	queue     &gpu.G13QueueResources = unsafe { nil }
}

pub fn (mut vm_manager UatManager) destroy_context(context &UatContext) {
	mut owned := unsafe { context }
	assert owned.queue == unsafe { nil } || owned.queue.released, 'VM destroyed while queue backing is retained'
	assert !owned.destroyed, 'VM destroyed twice during close retry'
	owned.destroyed = true
}
