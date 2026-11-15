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
pub mut:
	state State = .running
}

__global test_gpu_manager GpuManager
__global timestamp_unmaps = 0
__global stop_callback fn () = unsafe { nil }
__global failed_mapping_flushes = 0
__global mapping_flushes = 0
__global stops_finished = 0
__global timestamp_maps = 0

pub fn maps() int { return timestamp_maps }

pub fn (mut mgr GpuManager) map_g13_timestamp_buffer(physical u64, size u64) ?u64 {
	assert physical != 0 && size != 0
	timestamp_maps++
	return u64(0xffffffae10000000) + u64(timestamp_maps - 1) * 0x4000
}

pub fn stop_count() int { return stops_finished }

fn finish_stop() {
	assert test_gpu_manager.state == .stopped && test_gpu_manager.lock.is_held()
	stops_finished++
	test_gpu_manager.lock.release()
}

pub fn stop_during_mapping_lock() {
	// Production shutdown holds this lock while the early stopped state is
	// visible. Only completing stop releases it to a concurrent file flush.
	test_gpu_manager.lock.acquire()
	test_gpu_manager.state = .stopped
	klock.wait_once(unsafe { &test_gpu_manager.lock }, finish_stop)
}

pub fn fail_flushes(count int) { failed_mapping_flushes = count }
pub fn flushes() int { return mapping_flushes }

pub fn (mut mgr GpuManager) flush_g13_uat_range(slot u32, addr u64, size u64) bool {
	// The production file wrapper must serialize even running invalidations.
	assert mgr.lock.is_held()
	assert slot != 0 && addr != 0 && size != 0
	mapping_flushes++
	if mgr.state == .stopped { return false }
	if failed_mapping_flushes > 0 { failed_mapping_flushes--; return false }
	return true
}

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

pub fn set_running(running bool) {
	test_gpu_manager.state = if running { State.running } else { State.stopped }
}
