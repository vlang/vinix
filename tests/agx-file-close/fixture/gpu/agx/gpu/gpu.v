@[has_globals]
module gpu

import klock

pub struct G13QueueResources {
pub mut:
	released bool
	failures int
	calls    int
}

pub struct G17QueueResources {}

enum State { running stopped }
pub struct GpuManager {
mut:
	lock klock.Lock
	state State = .running
}

__global test_gpu_manager GpuManager
__global timestamp_unmaps = 0
__global stop_callback fn () = unsafe { nil }

pub fn get_global_manager() ?&GpuManager {
	if stop_callback != unsafe { nil } {
		callback := stop_callback
		stop_callback = unsafe { nil }
		callback()
		test_gpu_manager.state = .stopped
	}
	return unsafe { &test_gpu_manager }
}

pub fn stop_on_next_lookup(callback fn ()) { stop_callback = callback }

pub fn (mut mgr GpuManager) release_g13_queue_resources(queue &G13QueueResources) bool {
	mut owned := unsafe { queue }
	owned.calls++
	if owned.released { return true }
	if owned.failures != 0 {
		owned.failures--
		return false
	}
	owned.released = true
	return true
}

pub fn (mut mgr GpuManager) release_g17_queue_resources(queue &G17QueueResources) {}

pub fn (mut mgr GpuManager) unmap_g13_timestamp_buffer(address u64, size u64) bool {
	timestamp_unmaps++
	return true
}

pub fn unmaps() int { return timestamp_unmaps }
