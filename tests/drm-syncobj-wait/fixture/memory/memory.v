@[has_globals]
module memory

__global wait_storage_allocations [8192]voidptr
__global wait_storage_sizes [8192]u64
__global allocation_kinds [8192]u8
__global wait_storage_calls = 0
__global wait_storage_frees = 0
__global wait_storage_live = 0
__global wait_storage_live_bytes = u64(0)
__global wait_storage_fail_next = false
__global wait_storage_fail_at = -1
__global allocation_attempts = 0
__global metadata_object_size = u64(0)
__global metadata_fence_size = u64(0)
__global metadata_objects = 0
__global metadata_fences = 0
__global wait_storage_last_request = u64(0)
__global wait_storage_free_check fn (voidptr, u64) = unsafe { nil }
__global metadata_free_check fn (voidptr, u64) = unsafe { nil }
__global failure_action fn () = unsafe { nil }

pub fn reset() {
	assert wait_storage_live == 0 && wait_storage_live_bytes == 0 && metadata_objects == 0 && metadata_fences == 0
	wait_storage_calls = 0; wait_storage_frees = 0
	allocation_attempts = 0
	wait_storage_fail_next = false; wait_storage_last_request = 0
	wait_storage_fail_at = -1
	failure_action = unsafe { nil }
}

pub fn check_before_free(callback fn (voidptr, u64)) { wait_storage_free_check = callback }
pub fn check_metadata_free(callback fn (voidptr, u64)) { metadata_free_check = callback }
pub fn when_failing(callback fn ()) { failure_action = callback }
pub fn fail_next() { wait_storage_fail_next = true }
pub fn fail_in(successful_calls int) { wait_storage_fail_at = allocation_attempts + successful_calls + 1 }
pub fn configure_metadata(objects u64, fences u64) {
	assert objects != 0 && fences != 0
	metadata_object_size = objects; metadata_fence_size = fences
}
pub fn object_count() int { return metadata_objects }
pub fn fence_count() int { return metadata_fences }
pub fn fence_bytes() u64 { return u64(metadata_fences) * metadata_fence_size }
pub fn attempts() int { return allocation_attempts }
pub fn calls() int { return wait_storage_calls }
pub fn frees() int { return wait_storage_frees }
pub fn outstanding() int { return wait_storage_live }
pub fn live_bytes() u64 { return wait_storage_live_bytes }
pub fn last_request() u64 { return wait_storage_last_request }

pub fn malloc_packed_fallible(size u64) voidptr {
	return allocate(size, 0)
}

pub fn malloc_syncobj_fallible(size u64) voidptr {
	assert size == metadata_object_size
	return allocate(size, 1)
}

pub fn malloc_fence_fallible(size u64) voidptr {
	assert size == metadata_fence_size
	return allocate(size, 2)
}

fn allocate(size u64, kind u8) voidptr {
	allocation_attempts++
	metadata := kind != 0
	if !metadata { wait_storage_calls++ }
	wait_storage_last_request = size
	// Inject ENOMEM for enormous requests without exhausting the host. This
	// ceiling belongs only to the fixture, not the production wait handler.
	if wait_storage_fail_next || allocation_attempts == wait_storage_fail_at || size > 1024 * 1024 {
		wait_storage_fail_next = false
		wait_storage_fail_at = -1
		if failure_action != unsafe { nil } {
			callback := failure_action; failure_action = unsafe { nil }; callback()
		}
		return unsafe { nil }
	}
	buffer := unsafe { C.malloc(size) }
	if buffer == unsafe { nil } { return buffer }
	unsafe { C.memset(buffer, 0xa5, size) }
	for index in 0 .. wait_storage_allocations.len {
		if wait_storage_allocations[index] == unsafe { nil } {
			wait_storage_allocations[index] = buffer
			wait_storage_sizes[index] = size
			allocation_kinds[index] = kind
			if kind == 1 { metadata_objects++ }
			else if kind == 2 { metadata_fences++ }
			else { wait_storage_live++; wait_storage_live_bytes += size }
			return buffer
		}
	}
	panic('fixture allocation table exhausted')
}

pub fn free(buffer voidptr) {
	for index in 0 .. wait_storage_allocations.len {
		if wait_storage_allocations[index] == buffer && buffer != unsafe { nil } {
			size := wait_storage_sizes[index]
			kind := allocation_kinds[index]
			metadata := kind != 0
			if !metadata && wait_storage_free_check != unsafe { nil } { wait_storage_free_check(buffer, size) }
			if metadata && metadata_free_check != unsafe { nil } { metadata_free_check(buffer, size) }
			unsafe { C.memset(buffer, 0xd3, size); C.free(buffer) }
			wait_storage_allocations[index] = unsafe { nil }; wait_storage_sizes[index] = 0
			allocation_kinds[index] = 0
			if kind == 1 { metadata_objects-- }
			else if kind == 2 { metadata_fences-- }
			else { wait_storage_frees++; wait_storage_live--; wait_storage_live_bytes -= size }
			return
		}
	}
	panic('free of an unowned wait allocation')
}

pub fn owns(buffer voidptr) bool {
	for allocation in wait_storage_allocations { if allocation == buffer && buffer != unsafe { nil } { return true } }
	return false
}

// Fixture-only retirement after every object, capture, synchronous ioctl and
// scripted action is gone. Production retains published fence metadata.
pub fn release_retained_fences(size u64) {
	for index in 0 .. wait_storage_allocations.len {
		buffer := wait_storage_allocations[index]
		if buffer != unsafe { nil } {
			assert wait_storage_sizes[index] == size && allocation_kinds[index] == 2, 'non-fence allocation survived'
			free(buffer)
		}
	}
	assert wait_storage_live == 0 && wait_storage_live_bytes == 0 && metadata_objects == 0 && metadata_fences == 0
}
