@[has_globals]
module memory

__global fail_buffer = false
__global live_buffers = 0
__global registration_fail_after = -1
__global live_registrations = 0

pub fn fail_next(fail bool) { fail_buffer = fail }

pub fn outstanding() int { return live_buffers }

pub fn malloc_packed_fallible(size u64) voidptr {
	if fail_buffer { return unsafe { nil } }
	buffer := unsafe { C.malloc(size) }
	if buffer != unsafe { nil } { live_buffers++ }
	return buffer
}

pub fn free(buffer voidptr) {
	assert live_buffers > 0
	live_buffers--
	unsafe { C.free(buffer) }
}

pub fn fail_registration_after(count int) { registration_fail_after = count }

pub fn registration_outstanding() int { return live_registrations }

pub fn allocate_registration(size u64) voidptr {
	if registration_fail_after == 0 { return unsafe { nil } }
	if registration_fail_after > 0 { registration_fail_after-- }
	buffer := unsafe { C.malloc(size) }
	if buffer != unsafe { nil } { live_registrations++ }
	return buffer
}

pub fn free_registration(buffer voidptr) {
	assert live_registrations > 0
	live_registrations--
	unsafe { C.free(buffer) }
}
