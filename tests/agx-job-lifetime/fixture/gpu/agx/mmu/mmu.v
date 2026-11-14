module mmu

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
	releases        int
	allocations     int
	fail_allocation bool
	pool            [64]UatBuffer
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
