module mmu

pub struct UatBuffer { pub: id u32 }
pub struct UatContext { pub mut: active bool = true released_mask u64 }
pub fn (mut context UatContext) release_driver_buffer(buffer &UatBuffer) {
	if buffer == unsafe { nil } { return }
	bit := u64(1) << buffer.id
	assert context.released_mask & bit == 0, 'driver buffer must release once'
	context.released_mask |= bit
}
