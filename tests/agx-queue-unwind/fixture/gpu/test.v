@[has_globals]
module gpu

import gpu.agx.mmu
import gpu.agx.fw
import klock
#include <sanitizer/asan_interface.h>
fn C.__asan_address_is_poisoned(voidptr) int

fn failed_constructor(mut manager GpuManager, vm &mmu.UatContext) {
	manager.allocations = 0; manager.cleanups = 0
	mut retained := &G13QueueResources(unsafe { nil })
	if _ := manager.create_g13_queue_resources(1, 7, 1, vm, unsafe { &retained }) { panic('unexpected successful failure fixture') }
	assert retained == unsafe { nil } && manager.cleanups == 1 && manager.g13_queues.len == 0
}
fn measure_unwind() {
	C.printf(c'AGX-QUEUE-UNWIND malloc-zone measurement after stdio warmup\n')
	mut manager := GpuManager{mode: 1}; mut vm := mmu.UatContext{active: true, id: 1}
	manager.g13_queues.flags |= .noslices
	for _ in 0 .. 1000 { failed_constructor(mut manager, &vm) }
	live_heap()
	for round in 0 .. 3 {
		before_blocks, before_bytes := live_heap()
		for _ in 0 .. 10000 { failed_constructor(mut manager, &vm) }
		after_blocks, after_bytes := live_heap()
		blocks := i64(after_blocks) - i64(before_blocks); bytes := i64(after_bytes) - i64(before_bytes)
		C.printf(c'AGX-QUEUE-UNWIND round=%d failures=10000 retained_blocks=%lld retained_bytes=%lld\n', round, blocks, bytes)
		assert blocks == 0 && bytes == 0, 'failed unpublished construction must not retain its unreturned queue record'
	}
}
fn check_unwind() {
	mut cases := 0
	for _ in 0 .. 10 { for mask := u32(1); mask <= 7; mask++ { for priority := u32(0); priority < 4; priority++ { for mode in 0 .. 13 {
		mut manager := GpuManager{mode: mode}; manager.g13_queues.flags |= .noslices
		mut vm := mmu.UatContext{active: true, id: 1}
		fw.configure(mode == 5, mode == 6)
		mut returned := unsafe { &G13QueueResources(nil) }
		mut sentinel := G13QueueResources{}
		mut retained := unsafe { &sentinel }
		if resources := manager.create_g13_queue_resources(1, mask, priority, &vm, unsafe { &retained }) { returned = resources }
		failed := mode in [1, 2, 3, 4, 5, 6, 11, 12]! || (mode >= 7 && mode <= 9 && mask & (u32(1) << (mode - 7)) != 0)
			|| (mode == 10 && mask & 1 != 0)
		if !failed {
			assert returned != unsafe { nil } && retained == unsafe { nil } && manager.cleanups == 0 && manager.g13_queues.len == 1
			$if queue_sanitized ? { assert C.__asan_address_is_poisoned(returned) == 0, 'successful returned metadata must remain live' }
			assert !returned.released && !returned.quarantined
		} else if mode in [11, 12]! {
			assert returned == unsafe { nil } && manager.cleanups == 1 && manager.g13_queues.len == 1
			assert voidptr(retained) == voidptr(manager.g13_queues[0])
			$if queue_sanitized ? { assert C.__asan_address_is_poisoned(retained) == 0, 'quarantined metadata must remain live for manager/file adoption' }
			assert retained.quarantined && !retained.released && retained.vm == &vm
		} else {
			assert returned == unsafe { nil } && retained == unsafe { nil } && manager.cleanups == 1 && manager.g13_queues.len == 0
			$if queue_sanitized ? { assert C.__asan_address_is_poisoned(manager.last) != 0, 'failed unpublished construction must free its unreturned queue record' }
		}
		for resource in manager.g13_queues { unsafe { free(resource) } }
		unsafe { manager.g13_queues.free() }; cases++
	} } } }
	fw.configure(false, false)
	assert cases == 3640
	println('AGX queue unwind: 3640 constructor failure/success/quarantine cases free only safely cleaned unreturned metadata')
}

__global stopping_manager &GpuManager = unsafe { nil }

fn stop_on_constructor_unlock() {
	stopping_manager.lock.acquire()
	assert stopping_manager.g13_queues.len == 1
	stopping_manager.state = .stopped
	stopping_manager.release_all_g13_queue_resources()
	stopping_manager.lock.release()
}

fn check_stopped_handoff() {
	for _ in 0 .. 32 {
		for mode in [11, 12]! {
			mut manager := GpuManager{mode: mode}
			manager.g13_queues.flags |= .noslices
			vm := mmu.UatContext{active: true, id: 1}
			mut retained := &G13QueueResources(unsafe { nil })
			stopping_manager = unsafe { &manager }
			klock.on_next_release(unsafe { &manager.lock }, stop_on_constructor_unlock)
			if _ := manager.create_g13_queue_resources(1, 7, 1, &vm, unsafe { &retained }) {
				panic('constructor must fail after quarantine')
			}
			assert manager.g13_queues.len == 0 && manager.cleanups == 2 && manager.state == .stopped
			assert retained != unsafe { nil }, 'shutdown must not lose the constructor handoff'
			assert retained.released && retained.quarantined && voidptr(retained.vm) == voidptr(&vm)
			$if queue_sanitized ? { assert C.__asan_address_is_poisoned(retained) == 0 }
			free_g13_queue_record(retained)
			$if queue_sanitized ? { assert C.__asan_address_is_poisoned(retained) != 0 }
			stopping_manager = unsafe { nil }
			unsafe { manager.g13_queues.free() }
		}
	}
	println('AGX queue unwind: 64 shutdown drains between manager unlock and constructor return preserve the exact owner')
}

pub fn check_queue_unwind(measure bool) {
	if measure { measure_unwind() } else { check_unwind(); check_stopped_handoff() }
}
