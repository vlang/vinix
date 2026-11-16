// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module gpu

import gpu.agx.alloc
import gpu.agx.mmu

struct TimestampAllocator {
mut:
	allocations int
	releases int
	collections int
	reject bool
}

__global uat_mgr &mmu.UatManager = unsafe { nil }

pub fn timestamp_lock_held() bool { return test_gpu_manager.lock.is_held() }

fn (mut allocator TimestampAllocator) alloc(size u64, alignment u64) ?u64 {
	assert timestamp_lock_held() && size == 0x4000 && alignment == alloc.gpu_page_size
	allocator.allocations++
	if allocator.reject { return none }
	return alloc.g13_timestamp_start
}

fn (mut allocator TimestampAllocator) release(va u64) {
	assert timestamp_lock_held() && va == alloc.g13_timestamp_start
	allocator.releases++
}

fn (mut allocator TimestampAllocator) gc() {
	assert timestamp_lock_held()
	allocator.collections++
}

pub fn check_timestamp_serialization() {
	mut manager := unsafe { &test_gpu_manager }
	mut uat := mmu.UatManager{}
	for _ in 0 .. 100 {
		manager.g13_timestamp = TimestampAllocator{}
		uat_mgr = unsafe { &uat }
		manager.hw_config.gpu_gen = .g17
		if _ := manager.checked_timestamp_map(0x200000, 0x4000) { assert false }
		assert !timestamp_lock_held()
		manager.hw_config.gpu_gen = .g13
		for physical, size in {u64(0x200001): u64(0x4000), u64(0x200002): u64(0), u64(0x200003): u64(0x4001)} {
			if _ := manager.checked_timestamp_map(physical, size) { assert false }
			assert !timestamp_lock_held()
		}
		uat_mgr = unsafe { nil }
		if _ := manager.checked_timestamp_map(0x200000, 0x4000) { assert false }
		assert !timestamp_lock_held() && manager.g13_timestamp.allocations == 0
		uat_mgr = unsafe { &uat }
		manager.g13_timestamp.reject = true
		if _ := manager.checked_timestamp_map(0x200000, 0x4000) { assert false }
		assert !timestamp_lock_held() && manager.g13_timestamp.releases == 0
		manager.g13_timestamp.reject = false; uat.timestamp_reject = true
		if _ := manager.checked_timestamp_map(0x200000, 0x4000) { assert false }
		assert !timestamp_lock_held() && manager.g13_timestamp.releases == 1 && manager.g13_timestamp.collections == 1
		uat.timestamp_reject = false
		va := manager.checked_timestamp_map(0x200000, 0x4000) or { panic('timestamp map') }
		assert va == alloc.g13_timestamp_start && !timestamp_lock_held()
		before := manager.g13_timestamp.releases
		for invalid_va, size in {alloc.g13_timestamp_start - 1: u64(0x4000), alloc.g13_timestamp_end: u64(0x4000), alloc.g13_timestamp_start: u64(0), alloc.g13_timestamp_start + 0x4000: ~u64(0)} {
			manager.checked_timestamp_unmap(invalid_va, size)
			assert !timestamp_lock_held() && manager.g13_timestamp.releases == before
		}
		manager.checked_timestamp_unmap(va, 0x4000)
		assert !timestamp_lock_held() && manager.g13_timestamp.releases == before + 1
	}
	uat_mgr = unsafe { nil }
	println('G13 timestamp allocator: 100 native map/unmap lock-balance cycles, invalid requests, allocation/map failures, rollback and successful release passed')
}
