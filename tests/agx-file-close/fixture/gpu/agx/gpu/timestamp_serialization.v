// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module gpu

import gpu.agx.alloc
import gpu.agx.mmu

struct TimestampAllocator {
mut:
	heap alloc.HeapAllocator
	allocations int
	releases int
	collections int
	cancellations int
	reject bool
}

__global uat_mgr &mmu.UatManager = unsafe { nil }

pub fn timestamp_lock_held() bool {
	return test_gpu_manager.lock.is_held() || replacement_gpu_manager.lock.is_held()
}

fn (mut allocator TimestampAllocator) alloc(size u64, alignment u64) ?u64 {
	assert timestamp_lock_held() && size == 0x4000 && alignment == alloc.gpu_page_size
	allocator.allocations++
	if allocator.reject { return none }
	return allocator.heap.alloc(size, alignment)
}

fn (mut allocator TimestampAllocator) release(va u64) {
	assert timestamp_lock_held()
	allocator.heap.release(va)
	allocator.releases++
}

fn (mut allocator TimestampAllocator) cancel_unpublished(va u64) {
	assert timestamp_lock_held()
	allocator.heap.cancel_unpublished(va)
	allocator.cancellations++
}

fn (mut allocator TimestampAllocator) gc() {
	assert timestamp_lock_held()
	allocator.heap.gc()
	allocator.collections++
}

fn expect_timestamp_map_error(mut manager GpuManager, physical u64, size u64, expected int) {
	code, va := manager.checked_timestamp_map(physical, size)
	assert code == expected && va == 0
	assert !timestamp_lock_held()
}

pub fn check_timestamp_serialization() {
	mut manager := unsafe { &test_gpu_manager }
	initial_uat := manager.uat
	mut uat := mmu.UatManager{}
	for _ in 0 .. 100 {
		manager.g13_timestamp = TimestampAllocator{
			heap: alloc.new_heap('timestamp', alloc.g13_timestamp_start, alloc.g13_timestamp_end)
		}
		manager.uat = unsafe { &uat }
		manager.hw_config.gpu_gen = .g17
		expect_timestamp_map_error(mut manager, 0x200000, 0x4000, -12)
		manager.hw_config.gpu_gen = .g13
		for physical, size in {u64(0x200001): u64(0x4000), u64(0x200002): u64(0), u64(0x200003): u64(0x4001)} {
			expect_timestamp_map_error(mut manager, physical, size, -12)
		}
		manager.uat = unsafe { nil }
		expect_timestamp_map_error(mut manager, 0x200000, 0x4000, -12)
		assert manager.g13_timestamp.allocations == 0
		manager.uat = unsafe { &uat }
		before_stop := stop_count()
		maps_before_stop := uat.timestamp_map_calls
		stop_during_mapping_lock()
		expect_timestamp_map_error(mut manager, 0x200000, 0x4000, -19)
		assert stop_count() == before_stop + 1 && manager.g13_timestamp.allocations == 0
		assert uat.timestamp_map_calls == maps_before_stop
		manager.state = .running
		manager.g13_timestamp.reject = true
		before_maps := uat.timestamp_map_calls
		expect_timestamp_map_error(mut manager, 0x200000, 0x4000, -28)
		assert uat.timestamp_map_calls == before_maps && manager.g13_timestamp.releases == 0
		manager.g13_timestamp.reject = false
		pending := manager.g13_timestamp.heap.alloc(0x4000, alloc.gpu_page_size) or { panic('deferred timestamp reservation') }
		manager.g13_timestamp.heap.release(pending)
		for index, status in [-12, -16]! {
			uat.timestamp_map_status = status
			expect_timestamp_map_error(mut manager, 0x200000, 0x4000, status)
			assert manager.g13_timestamp.cancellations == index + 1
			assert manager.g13_timestamp.heap.allocations.len == 1
			deferred, bytes := manager.g13_timestamp.heap.garbage()
			assert deferred == 1 && bytes == 0x4000, 'map rollback must preserve the deferred VA'
			assert manager.g13_timestamp.releases == 0 && manager.g13_timestamp.collections == 0
		}
		uat.timestamp_map_status = 0
		code, va := manager.checked_timestamp_map(0x200000, 0x4000)
		assert code == 0 && va == pending + 0x4000 && !timestamp_lock_held()
		before := manager.g13_timestamp.releases
		for invalid_va, size in {alloc.g13_timestamp_start - 1: u64(0x4000), alloc.g13_timestamp_end: u64(0x4000), alloc.g13_timestamp_start: u64(0), alloc.g13_timestamp_start + 0x4000: ~u64(0)} {
			manager.checked_timestamp_unmap(invalid_va, size)
			assert !timestamp_lock_held() && manager.g13_timestamp.releases == before
		}
		manager.checked_timestamp_unmap(va, 0x4000)
		assert !timestamp_lock_held() && manager.g13_timestamp.releases == before + 1
		assert manager.g13_timestamp.collections == 1 && manager.g13_timestamp.heap.allocations.len == 0
		unsafe { manager.g13_timestamp.heap.allocations.free() }
		manager.state = .running
	}
	check_timestamp_aperture_capacity(mut manager, mut uat)
	check_timestamp_aperture_teardown(mut manager, mut uat)
	manager.uat = initial_uat
	println('G13 timestamp allocator: 100 cycles distinguish ENOSPC, ENOMEM and EBUSY, cancel failed maps without collection and reuse their VA under balanced locks')
	println('G13 timestamp shutdown: 100 lock races reject late maps with ENODEV before allocation or UAT writes')
}

fn check_timestamp_aperture_teardown(mut manager GpuManager, mut original mmu.UatManager) {
	mut replacement := unsafe { &replacement_gpu_manager }
	mut replacement_uat := mmu.UatManager{}
	unit := alloc.gpu_page_size
	for _ in 0 .. 64 {
		manager.g13_timestamp = TimestampAllocator{
			heap: alloc.new_heap('old timestamp', alloc.g13_timestamp_start, alloc.g13_timestamp_end)
		}
		manager.uat = unsafe { &original }
		code, va := manager.checked_timestamp_map(0x200000, unit)
		unpublished_code, unpublished := manager.checked_timestamp_map(0x204000, unit)
		assert code == 0 && unpublished_code == 0 && unpublished == va + unit
		before_stop := original.timestamp_unmap_calls
		manager.lock.acquire()
		manager.state = .stopped
		manager.retire_g13_timestamp_aperture_locked()
		manager.lock.release()
		assert original.timestamp_unmap_calls == before_stop + 2
		assert manager.g13_timestamp.heap.allocations.len == 0 && voidptr(manager.uat) == voidptr(original)
		expect_timestamp_map_error(mut manager, 0x200000, unit, -19)

		replacement.g13_timestamp = TimestampAllocator{
			heap: alloc.new_heap('new timestamp', alloc.g13_timestamp_start, alloc.g13_timestamp_end)
		}
		replacement.uat = unsafe { &replacement_uat }
		new_code, reused := replacement.checked_timestamp_map(0x208000, unit)
		assert new_code == 0 && reused == va
		before_late := replacement_uat.timestamp_unmap_calls
		manager.checked_timestamp_unmap(unpublished, unit)
		manager.checked_timestamp_unmap(va, unit)
		assert original.timestamp_unmap_calls == before_stop + 2
		assert replacement_uat.timestamp_unmap_calls == before_late
		assert replacement.g13_timestamp.heap.allocations.len == 1 && !timestamp_lock_held()
		replacement.checked_timestamp_unmap(reused, unit)
		assert replacement_uat.timestamp_unmap_calls == before_late + 1
		unsafe { replacement.g13_timestamp.heap.allocations.free() }
		replacement.uat = unsafe { nil }
		manager.state = .running
	}
	println('G13 timestamp aperture teardown: 64 drains revoke mapped and unpublished VAs before replacement reuse and ignore old releases')
}

fn check_timestamp_aperture_capacity(mut manager GpuManager, mut uat mmu.UatManager) {
	manager.g13_timestamp = TimestampAllocator{
		heap: alloc.new_heap('timestamp', alloc.g13_timestamp_start, alloc.g13_timestamp_end)
	}
	unit := alloc.gpu_page_size
	capacity := (alloc.g13_timestamp_end - alloc.g13_timestamp_start) / unit
	assert capacity == 4096
	for index := u64(0); index < capacity; index++ {
		code, va := manager.checked_timestamp_map(0x200000, unit)
		assert code == 0 && va == alloc.g13_timestamp_start + index * unit
	}
	before := uat.timestamp_map_calls
	expect_timestamp_map_error(mut manager, 0x200000, unit, -28)
	assert uat.timestamp_map_calls == before && manager.g13_timestamp.heap.allocations.len == int(capacity)

	hole := alloc.g13_timestamp_start + capacity / 2 * unit
	manager.checked_timestamp_unmap(hole, unit)
	code, reused := manager.checked_timestamp_map(0x200000, unit)
	assert code == 0 && reused == hole
	for index := u64(0); index < capacity; index++ {
		manager.checked_timestamp_unmap(alloc.g13_timestamp_start + index * unit, unit)
	}
	assert manager.g13_timestamp.heap.allocations.len == 0 && !timestamp_lock_held()
	unsafe { manager.g13_timestamp.heap.allocations.free() }
	println('G13 timestamp aperture: 4096 live reservations exhaust the real 64 MiB heap with ENOSPC and a released hole accepts retry')
}
