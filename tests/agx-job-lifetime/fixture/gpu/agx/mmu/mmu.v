module mmu

pub const uat_kernel_flush_slot = 64

pub struct UatBuffer {
pub mut:
	released bool
	va       u64
	size     u64
}

pub struct UatContext {
pub mut:
	active          bool = true
	id              u32  = 1
	slot            u32  = 1
	binding_epoch   u64
	lease_users     int
	releases        int
	allocations     int
	fail_allocation bool
	pool            [64]UatBuffer
}

pub struct UatManager {}

pub fn (mut mgr UatManager) release_g13_slot(context &UatContext, slot u32) {
	assert slot == context.slot && context.lease_users > 0
	mut owner := unsafe { context }
	owner.lease_users--
}

pub fn (context &UatContext) bound_slot() u32 {
	return context.slot
}

pub fn (mut context UatContext) alloc_driver_buffer_aligned(size u64, private bool, alignment u64) ?&UatBuffer {
	assert private && alignment == 0x4000
	if context.fail_allocation { return none }
	index := context.allocations
	assert index < context.pool.len
	context.allocations++
	context.pool[index] = UatBuffer{ size: (size + 0x3fff) & ~u64(0x3fff), va: 0x100000 + u64(index) * 0x10000 }
	return unsafe { &context.pool[index] }
}

pub fn (mut context UatContext) release_driver_buffer(buffer &UatBuffer) {
	if buffer == unsafe { nil } { return }
	mut owned := unsafe { buffer }
	assert !owned.released, 'driver buffer released twice'
	owned.released = true
	context.releases++
}
