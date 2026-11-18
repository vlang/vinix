@[has_globals]
module gpu

import klock
import gpu.agx.fw

pub const g13_queue_channel_vertex = u32(1)
pub const g13_queue_channel_fragment = u32(2)
pub const g13_queue_channel_compute = u32(4)
pub const g17_queue_channel_ta = u32(1)
pub const g17_queue_channel_3d = u32(2)
pub const g17_queue_channel_cl = u32(4)

pub enum Generation { g13 g17 }
pub struct Config {
pub mut:
	gpu_gen Generation = .g13
	base_clock_hz u64 = 24_000_000
}

pub struct G13QueueResources {
pub mut:
	queue_id u32
	file_references u64
	released bool
	failures int
	calls    int
	priority u32
	channel_mask u32
	vm_address u64
	pooled bool
	heap_record bool
	record_disposed bool
	context_next &G13QueueResources = unsafe { nil }
	vertex fw.G13WorkQueuePriority
	fragment fw.G13WorkQueuePriority
	compute fw.G13WorkQueuePriority
}

pub struct G17QueueResources {}

pub enum State { idle starting running error stopped }
pub struct GpuManager {
mut:
	lock klock.Lock
pub mut:
	state State = .running
	hw_config Config
	g13_timestamp TimestampAllocator
}

__global test_gpu_manager GpuManager
__global manager_available = true
__global manager_lookups = 0
__global timestamp_unmaps = 0
__global stop_callback fn () = unsafe { nil }
__global failed_mapping_checks = 0
__global mapping_check_failure_after = int(-1)
__global mapping_check_count = 0
__global stops_finished = 0
__global timestamp_maps = 0
__global timestamp_map_error = 0
__global queue_pool = [16]G13QueueResources{}
__global queue_attempts = 0
__global live_queues = 0
__global reject_queue = false
__global quarantine_next = false
__global queue_release_watch fn () = unsafe { nil }

pub fn watch_queue_release(callback fn ()) { queue_release_watch = callback }

pub fn queue_creates() int { return queue_attempts }
pub fn active_queues() int { return live_queues }
pub fn fail_queue() { reject_queue = true }
pub fn quarantine_queue() { quarantine_next = true }

pub fn (mut mgr GpuManager) create_g13_queue_resources(id u32, mask u32, priority u32, vm voidptr) ?&G13QueueResources {
	queue_attempts++
	if reject_queue { reject_queue = false; return none }
	if mgr.state != .running { return none }
	for index in 0 .. 16 {
		if !queue_pool[index].pooled || queue_pool[index].released {
			queue_pool[index] = G13QueueResources{ queue_id: id, priority: priority, channel_mask: mask, vm_address: u64(vm), pooled: true }
			if mask & 1 != 0 { queue_pool[index].vertex = fw.g13_default_workqueue_priority(priority, 0) or { panic('vertex priority') } }
			if mask & 2 != 0 { queue_pool[index].fragment = fw.g13_default_workqueue_priority(priority, 1) or { panic('fragment priority') } }
			if mask & 4 != 0 { queue_pool[index].compute = fw.g13_default_workqueue_priority(priority, 2) or { panic('compute priority') } }
			live_queues++
			if quarantine_next {
				quarantine_next = false
				queue_pool[index].failures = 2
				return none
			}
			return unsafe { &queue_pool[index] }
		}
	}
	return none
}

pub fn (mut mgr GpuManager) retained_g13_queue_resources(id u32, vm voidptr) ?&G13QueueResources {
	for index in 0 .. 16 {
		if queue_pool[index].pooled && !queue_pool[index].released
			&& queue_pool[index].queue_id == id && queue_pool[index].vm_address == u64(vm) {
			return unsafe { &queue_pool[index] }
		}
	}
	return none
}

pub fn (mut mgr GpuManager) create_g17_queue_resources(_id u32, _owner u32, _mask u32, _priority u32) ?&G17QueueResources { return none }

pub fn maps() int { return timestamp_maps }
pub fn fail_timestamp_map(code int) { timestamp_map_error = code }

pub fn (mut mgr GpuManager) map_g13_timestamp_buffer(physical u64, size u64) (int, u64) {
	assert physical != 0 && size != 0
	timestamp_maps++
	if timestamp_map_error != 0 { return timestamp_map_error, 0 }
	return 0, u64(0xffffffae10000000) + u64(timestamp_maps - 1) * 0x4000
}

pub fn stop_count() int { return stops_finished }

fn finish_stop() {
	assert test_gpu_manager.state == .stopped && test_gpu_manager.lock.is_held()
	stops_finished++
	test_gpu_manager.lock.release()
}

pub fn stop_during_mapping_lock() {
	// Production shutdown holds this lock while the early stopped state is
	// visible. Only completing stop releases it to a concurrent file mapping.
	test_gpu_manager.lock.acquire()
	test_gpu_manager.state = .stopped
	klock.wait_once(unsafe { &test_gpu_manager.lock }, finish_stop)
}

pub fn fail_mapping_checks(count int) {
	failed_mapping_checks = count
	mapping_check_failure_after = -1
}

pub fn fail_mapping_check_after(successes int) { mapping_check_failure_after = successes }
pub fn mapping_checks() int { return mapping_check_count }

pub fn before_file_mapping_lock(callback fn ()) {
	klock.before_once(unsafe { &test_gpu_manager.lock }, callback)
}

fn (mgr &GpuManager) g13_submission_status_locked() int {
	assert mgr.lock.is_held()
	mapping_check_count++
	if mapping_check_failure_after == 0 { mapping_check_failure_after = -1; return -19 }
	if mapping_check_failure_after > 0 { mapping_check_failure_after-- }
	if failed_mapping_checks > 0 { failed_mapping_checks--; return -19 }
	return mgr.g13_submission_status_real_locked()
}

pub fn (mut mgr GpuManager) flush_g13_uat_range(slot u32, addr u64, size u64) bool {
	panic('GPU-only file mappings do not use FwCtl')
}

pub fn get_global_manager() ?&GpuManager {
	manager_lookups++
	if !manager_available { return none }
	if stop_callback != unsafe { nil } {
		callback := stop_callback
		stop_callback = unsafe { nil }
		callback()
		test_gpu_manager.state = .stopped
	}
	return unsafe { &test_gpu_manager }
}

pub fn available(value bool) { manager_available = value }
pub fn lookups() int { return manager_lookups }

pub fn set_query_state(state State) { test_gpu_manager.state = state }
pub fn query_lock_held() bool { return test_gpu_manager.lock.is_held() }

fn fail_query() { test_gpu_manager.state = .error }

pub fn fail_before_query_lock() {
	assert test_gpu_manager.state == .running
	klock.before_once(unsafe { &test_gpu_manager.lock }, fail_query)
}

pub fn stop_on_next_lookup(callback fn ()) { stop_callback = callback }

pub fn (mut mgr GpuManager) release_g13_queue_resources(queue &G13QueueResources) bool {
	if queue_release_watch != unsafe { nil } { queue_release_watch() }
	mut owned := unsafe { queue }
	owned.calls++
	if owned.released { return true }
	if owned.has_file_references() { return false }
	if owned.failures != 0 {
		owned.failures--
		return false
	}
	owned.released = true
	if owned.pooled { live_queues-- }
	return true
}

pub fn (mut mgr GpuManager) release_g17_queue_resources(queue &G17QueueResources) {}

pub fn free_g13_queue_record(resources &G13QueueResources) {
	if resources.heap_record { free_g13_queue_record_real(resources); return }
	assert resources.released && !resources.has_file_references() && !resources.record_disposed,
		'queue metadata disposal must occur once per final owner'
	// Existing fixtures retain stack/pool records for post-release observations.
	mut owned := unsafe { resources }; owned.record_disposed = true
}

pub fn (mut mgr GpuManager) unmap_g13_timestamp_buffer(address u64, size u64) bool {
	timestamp_unmaps++
	return true
}

pub fn unmaps() int { return timestamp_unmaps }

pub fn set_running(running bool) {
	test_gpu_manager.state = if running { State.running } else { State.stopped }
}
