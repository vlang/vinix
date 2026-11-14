@[has_globals]
module memory

__global fail_buffer = false
__global live_buffers = 0

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
