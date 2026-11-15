@[has_globals]
module memory

__global wait_storage_allocations [8192]voidptr
__global wait_storage_sizes [8192]u64
__global wait_storage_calls = 0
__global wait_storage_frees = 0
__global wait_storage_live = 0
__global wait_storage_live_bytes = u64(0)
__global wait_storage_fail_next = false
__global wait_storage_fail_at = -1
__global wait_storage_last_request = u64(0)
__global wait_storage_free_check fn (voidptr, u64) = unsafe { nil }

pub fn reset() {
	assert wait_storage_live == 0 && wait_storage_live_bytes == 0
	wait_storage_calls = 0; wait_storage_frees = 0
	wait_storage_fail_next = false; wait_storage_last_request = 0
	wait_storage_fail_at = -1
}

pub fn check_before_free(callback fn (voidptr, u64)) { wait_storage_free_check = callback }
pub fn fail_next() { wait_storage_fail_next = true }
pub fn fail_in(successful_calls int) { wait_storage_fail_at = wait_storage_calls + successful_calls + 1 }
pub fn calls() int { return wait_storage_calls }
pub fn frees() int { return wait_storage_frees }
pub fn outstanding() int { return wait_storage_live }
pub fn live_bytes() u64 { return wait_storage_live_bytes }
pub fn last_request() u64 { return wait_storage_last_request }

pub fn malloc_packed_fallible(size u64) voidptr {
	wait_storage_calls++
	wait_storage_last_request = size
	// Inject ENOMEM for enormous requests without exhausting the host. This
	// ceiling belongs only to the fixture, not the production wait handler.
	if wait_storage_fail_next || wait_storage_calls == wait_storage_fail_at || size > 1024 * 1024 {
		wait_storage_fail_next = false
		wait_storage_fail_at = -1
		return unsafe { nil }
	}
	buffer := unsafe { C.malloc(size) }
	if buffer == unsafe { nil } { return buffer }
	unsafe { C.memset(buffer, 0xa5, size) }
	for index in 0 .. wait_storage_allocations.len {
		if wait_storage_allocations[index] == unsafe { nil } {
			wait_storage_allocations[index] = buffer
			wait_storage_sizes[index] = size
			wait_storage_live++; wait_storage_live_bytes += size
			return buffer
		}
	}
	panic('fixture allocation table exhausted')
}

pub fn free(buffer voidptr) {
	for index in 0 .. wait_storage_allocations.len {
		if wait_storage_allocations[index] == buffer && buffer != unsafe { nil } {
			size := wait_storage_sizes[index]
			if wait_storage_free_check != unsafe { nil } { wait_storage_free_check(buffer, size) }
			unsafe { C.memset(buffer, 0xd3, size); C.free(buffer) }
			wait_storage_allocations[index] = unsafe { nil }; wait_storage_sizes[index] = 0
			wait_storage_frees++; wait_storage_live--; wait_storage_live_bytes -= size
			return
		}
	}
	panic('free of an unowned wait allocation')
}

// Fixture-only retirement after every object, capture, synchronous ioctl and
// scripted action is gone. Production retains published fence metadata.
pub fn release_retained_fences(size u64) {
	for index in 0 .. wait_storage_allocations.len {
		buffer := wait_storage_allocations[index]
		if buffer != unsafe { nil } {
			assert wait_storage_sizes[index] == size, 'temporary request owner survived'
			free(buffer)
		}
	}
	assert wait_storage_live == 0 && wait_storage_live_bytes == 0
}
