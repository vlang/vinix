// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module memory

fn C.__asan_address_is_poisoned(addr voidptr) int

__global reject_allocations = false
__global allocation_calls = 0
__global allocations [64]voidptr
__global allocation_count = 0

pub fn fail_allocations(reject bool) { reject_allocations = reject }
pub fn calls() int { return allocation_calls }
pub fn outstanding() int {
	$if queue_records_sanitized ? {
		mut live_count := 0
		for i in 0 .. allocation_count {
			if C.__asan_address_is_poisoned(allocations[i]) == 0 { live_count++ }
		}
		return live_count
	} $else {
		panic('allocation tracking requires ASan')
	}
}

pub fn free(pointer voidptr) { unsafe { C.free(pointer) } }

pub fn malloc_packed_fallible(size u64) voidptr {
	allocation_calls++
	// Fresh BIND now uses the same owned array backing. Reclaim tracking
	// slots only after ASan proves an earlier reservation has been freed.
	$if queue_records_sanitized ? {
		mut kept := 0
		for i in 0 .. allocation_count {
			if C.__asan_address_is_poisoned(allocations[i]) == 0 {
				allocations[kept] = allocations[i]
				kept++
			}
		}
		allocation_count = kept
	}
	if reject_allocations { return unsafe { nil } }
	result := unsafe { C.malloc(size) }
	assert result != unsafe { nil }
	$if queue_records_sanitized ? {
		assert allocation_count < allocations.len
		allocations[allocation_count] = result
		allocation_count++
	}
	return result
}

// The production owned-array free uses libc free in this host fixture. ASan's
// shadow proves every successful raw reservation was freed before resetting.
pub fn assert_released() {
	$if queue_records_sanitized ? {
		for i in 0 .. allocation_count {
			assert C.__asan_address_is_poisoned(allocations[i]) != 0, 'mapping reservation remains live after close'
			allocations[i] = unsafe { nil }
		}
		allocation_count = 0
	} $else {
		panic('allocation tracking requires ASan')
	}
}
