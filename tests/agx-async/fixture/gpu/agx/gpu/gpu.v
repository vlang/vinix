@[has_globals]
module gpu

import gpu.agx.compute
import gpu.agx.render
import gpu.agx.mmu
import gpu.agx.admission
import klock

pub enum State {
	idle
	starting
	running
	error
	stopped
}

pub enum Generation {
	g13
	g17
}

pub struct Config {
pub:
	gpu_gen Generation = .g13
}

pub struct G13QueueResources {
pub mut:
	id          u32
	fence_context u64
	fence_seqno u32
	submission_gate admission.Gate
	dispatch_blocked_in_poll bool
	file_references u64
	released    bool
	quarantined bool
	initial_events [2]G13InitialEvent
	admission_slots [3]u32 = [u32(127), 127, 127]!
	admission_space [3]u32 = [u32(1279), 1279, 1279]!
}

pub struct ComputeValues {
pub:
	start u64 = 11
	end   u64 = 22
}

pub struct RenderValues {
pub:
	vertex_start      u64 = 1
	vertex_end        u64 = 2
	fragment_start    u64 = 3
	fragment_end      u64 = 4
	tvb_size_bytes    u64
	tvb_usage_bytes   u64
	num_tvb_overflows u32
	overflowed        bool
}

pub struct G13ComputeJobResources {
pub mut:
	queue       &G13QueueResources = unsafe { nil }
	error       G13JobError
	submitted   bool
	released    bool
	quarantined bool
	marker      u64
	usc_base    u64
	timestamps [2]u64
	flush_stamps bool
	ordinal     u32
	barrier_sources [2]u32
	initial_sources [2]u32
	completion  fn (&G13ComputeJobResources, bool, voidptr) = unsafe { nil }
	data        voidptr
}

pub struct G13RenderJobResources {
pub mut:
	vertex_timestamps [2]u64
	fragment_timestamps [2]u64
	flush_stamps bool
	queue       &G13QueueResources = unsafe { nil }
	error       G13JobError
	submitted   bool
	released    bool
	quarantined bool
	ordinal     u32
	barrier_sources [2]u32
	initial_sources [2]u32
	completion  fn (&G13RenderJobResources, bool, voidptr) = unsafe { nil }
	stage_completion fn (u32, voidptr) = unsafe { nil }
	stage_finished [2]bool
	data        voidptr
}

pub struct GpuManager {
pub mut:
	uat                   &mmu.UatManager = unsafe { nil }
	lock                  klock.Lock
	state                 State = .running
	hw_config             Config
	g13_compute_jobs      []&G13ComputeJobResources
	g13_render_jobs       []&G13RenderJobResources
	published             []u32
	published_order       []u32
	released_order        []u32
	prepares              int
	submit_globals_refreshes int
	active_operations     int
	operation_starts      int
	operation_ends        int
	fail_operation_wake   bool
	callbacks             int
	barrier_setups        int
	capture_pins          int
	fail_barrier_at       int = -1
	stop_barrier_at       int = -1
	stop_publish_at       int = -1
	stop_submit_at        int = -1
	fail_prepare_at       int          = -1
	fail_callback_at      int          = -1
	stop_callback_at      int          = -1
	inspect_callback_at   int          = -1
	on_callback           fn (voidptr) = unsafe { nil }
	fail_compute          bool
	fail_render           bool
	fail_compute_callback bool
	fail_render_callback  bool
	ring_full             bool
	compute_ring_full     bool
	render_ring_full      bool
	publication_limit     int = -1
	firmware_done         [1024]bool
	firmware_vertex_done  [1024]bool
	firmware_status       [1024]u32
	immediate_fault_at    int   = -1
	on_submit             fn () = unsafe { nil }
	immediate_complete    bool
	stop_after_callback   bool
	on_publish            fn () = unsafe { nil }
	on_admit              fn () = unsafe { nil }
	admissions            int
	timestamp_unmaps int
}

__global test_async_gpu_manager GpuManager
__global manager_available = true

pub fn reset() {
	manager_available = true
	assert test_async_gpu_manager.g13_compute_jobs.len == 0 && test_async_gpu_manager.g13_render_jobs.len == 0
	unsafe {
		test_async_gpu_manager.g13_compute_jobs.free()
		test_async_gpu_manager.g13_render_jobs.free()
		test_async_gpu_manager.published.free()
		test_async_gpu_manager.published_order.free()
		test_async_gpu_manager.released_order.free()
	}
	test_async_gpu_manager = GpuManager{ uat: mmu.active_test_uat() }
	test_async_gpu_manager.g13_compute_jobs.flags |= .noslices
	test_async_gpu_manager.g13_render_jobs.flags |= .noslices
	test_async_gpu_manager.published.flags |= .noslices
	test_async_gpu_manager.published_order.flags |= .noslices
	test_async_gpu_manager.released_order.flags |= .noslices
}

pub fn available(value bool) { manager_available = value }
pub fn get_global_manager() ?&GpuManager {
	if !manager_available { return none }
	return unsafe { &test_async_gpu_manager }
}

pub fn (job &G13ComputeJobResources) timestamp_values() ComputeValues { return ComputeValues{} }

pub fn (job &G13RenderJobResources) result_values() RenderValues { return RenderValues{} }

pub fn (mut mgr GpuManager) prepare_g13_compute_job(queue &G13QueueResources, ctx &mmu.UatContext,
	input &compute.Command) ?&G13ComputeJobResources {
	return mgr.prepare_g13_compute_job_with_timestamps(queue, ctx, input, [2]u64{})
}

pub fn (mut mgr GpuManager) prepare_g13_compute_job_with_timestamps(queue &G13QueueResources, ctx &mmu.UatContext,
	input &compute.Command, timestamps [2]u64) ?&G13ComputeJobResources {
	if mgr.fail_compute { return none }
	index := mgr.prepares
	mgr.prepares++
	if index == mgr.fail_prepare_at { return none }
	job := &G13ComputeJobResources{ queue: unsafe { queue }, marker: input.encoder_ptr, usc_base: input.usc_base, ordinal: u32(index), timestamps: timestamps, flush_stamps: input.flush_stamps }
	mgr.g13_compute_jobs << job
	return job
}

pub fn (mut mgr GpuManager) prepare_g13_render_job(queue &G13QueueResources,
	input &render.Command) ?&G13RenderJobResources {
	return mgr.prepare_g13_render_job_with_timestamps(queue, input, [2]u64{}, [2]u64{})
}

pub fn (mut mgr GpuManager) prepare_g13_render_job_with_timestamps(queue &G13QueueResources,
	input &render.Command, vertex_timestamps [2]u64, fragment_timestamps [2]u64) ?&G13RenderJobResources {
	if mgr.fail_render { return none }
	index := mgr.prepares
	mgr.prepares++
	if index == mgr.fail_prepare_at { return none }
	job := &G13RenderJobResources{ queue: unsafe { queue }, ordinal: u32(index), vertex_timestamps: vertex_timestamps, fragment_timestamps: fragment_timestamps, flush_stamps: input.flush_stamps }
	mgr.g13_render_jobs << job
	return job
}

pub fn (mut mgr GpuManager) unmap_g13_timestamp_buffer(va u64, size u64) {
	assert !mgr.lock.is_held(), 'timestamp release under manager lock'
	assert va != 0 && size != 0
	mgr.lock.acquire(); mgr.timestamp_unmaps++; mgr.lock.release()
}

pub fn (mut mgr GpuManager) refresh_g13_submit_globals() {
	assert !mgr.lock.is_held()
	mgr.submit_globals_refreshes++
}

pub fn (mut mgr GpuManager) set_g13_compute_completion(job &G13ComputeJobResources,
	callback fn (&G13ComputeJobResources, bool, voidptr), data voidptr) bool {
	if mgr.fail_compute_callback || job.released || job.submitted || job.completion != unsafe { nil } {
		return false
	}
	index := mgr.callbacks
	mgr.callbacks++
	if index == mgr.fail_callback_at { return false }
	unsafe {
		job.completion = callback
		job.data = data
	}
	if index == mgr.inspect_callback_at && mgr.on_callback != unsafe { nil } {
		mgr.on_callback(data)
	}
	if index == mgr.stop_callback_at { mgr.stop() }
	return true
}

pub struct G13BarrierSource {
pub:
	render &G13RenderJobResources = unsafe { nil }
	compute &G13ComputeJobResources = unsafe { nil }
	initial G13InitialEvent
}

fn (mut mgr GpuManager) stage_barrier_sources(queue &G13QueueResources, sources [2]G13BarrierSource) ?[2]u32 {
	if mgr.state != .running { return none }
	index := mgr.barrier_setups
	mgr.barrier_setups++
	if index == mgr.fail_barrier_at { return none }
	mut result := [2]u32{}
	for pipe, source in sources {
		if source.initial.valid {
			assert source.initial.queue == queue
			assert source.initial.pipe == u32(pipe)
			result[pipe] = source.initial.ordinal + 1
		}
		if source.render != unsafe { nil } {
			assert pipe == 0 && source.render.queue == queue && !source.render.submitted && !source.render.released
			result[pipe] = source.render.ordinal + 1
		}
		if source.compute != unsafe { nil } {
			assert pipe == 1 && source.compute.queue == queue && !source.compute.submitted && !source.compute.released
			result[pipe] = source.compute.ordinal + 1
		}
	}
	if index == mgr.stop_barrier_at { mgr.stop() }
	return result
}

pub fn (mut mgr GpuManager) set_g13_compute_barriers(job &G13ComputeJobResources, sources [2]G13BarrierSource) bool {
	if job.released || job.submitted || job.quarantined { return false }
	values := mgr.stage_barrier_sources(job.queue, sources) or { return false }
	unsafe { job.barrier_sources = values }
	for pipe, source in sources { if source.initial.valid { unsafe { job.initial_sources[pipe] = source.initial.ordinal + 1 } } }
	return true
}

pub fn (mut mgr GpuManager) set_g13_render_barriers(job &G13RenderJobResources, sources [2]G13BarrierSource) bool {
	if job.released || job.submitted || job.quarantined { return false }
	values := mgr.stage_barrier_sources(job.queue, sources) or { return false }
	unsafe { job.barrier_sources = values }
	for pipe, source in sources { if source.initial.valid { unsafe { job.initial_sources[pipe] = source.initial.ordinal + 1 } } }
	return true
}

pub fn (mut mgr GpuManager) set_g13_render_completion(job &G13RenderJobResources,
	callback fn (&G13RenderJobResources, bool, voidptr), stage_callback fn (u32, voidptr), data voidptr) bool {
	if mgr.fail_render_callback || job.released || job.submitted || job.completion != unsafe { nil } {
		return false
	}
	index := mgr.callbacks
	mgr.callbacks++
	if index == mgr.fail_callback_at { return false }
	unsafe {
		job.completion = callback
		job.stage_completion = stage_callback
		job.data = data
	}
	if index == mgr.inspect_callback_at && mgr.on_callback != unsafe { nil } {
		mgr.on_callback(data)
	}
	if mgr.stop_after_callback || index == mgr.stop_callback_at { mgr.stop() }
	return true
}

fn (mut mgr GpuManager) complete_compute(job &G13ComputeJobResources, successful bool) {
	if job.completion != unsafe { nil } {
		callback := job.completion
		data := job.data
		unsafe {
			job.completion = nil
			job.data = nil
		}
		callback(job, successful, data)
	}
}

fn (mut mgr GpuManager) complete_render(job &G13RenderJobResources, successful bool) {
	unsafe { job.stage_completion = nil }
	if job.completion != unsafe { nil } {
		callback := job.completion
		data := job.data
		unsafe {
			job.completion = nil
			job.data = nil
		}
		callback(job, successful, data)
	}
}

pub fn (mut mgr GpuManager) release_g13_compute_job(job &G13ComputeJobResources) {
	assert !job.submitted
	mgr.released_order << job.ordinal
	mgr.complete_compute(job, false)
	for i, item in mgr.g13_compute_jobs {
		if voidptr(item) == voidptr(job) {
			mgr.g13_compute_jobs.delete(i)
			break
		}
	}
	unsafe { free(job) }
}

pub fn (mut mgr GpuManager) release_g13_render_job(job &G13RenderJobResources) {
	assert !job.submitted
	mgr.released_order << job.ordinal
	mgr.complete_render(job, false)
	for i, item in mgr.g13_render_jobs {
		if voidptr(item) == voidptr(job) {
			mgr.g13_render_jobs.delete(i)
			break
		}
	}
	unsafe { free(job) }
}

pub fn (mut mgr GpuManager) submit_g13_compute_job(job &G13ComputeJobResources) bool {
	if int(job.ordinal) == mgr.stop_submit_at { mgr.stop() }
	if mgr.on_submit != unsafe { nil } {
		hook := mgr.on_submit
		mgr.on_submit = unsafe { nil }
		hook()
	}
	if mgr.state != .running || mgr.ring_full || mgr.compute_ring_full
		|| (mgr.publication_limit >= 0 && mgr.published.len >= mgr.publication_limit)
		|| mgr.g13_queue_dispatch_blocked_locked(job.queue) {
		return false
	}
	assert !job.submitted && !job.released
	resolved := mgr.resolve_initial_sources(job.queue, job.initial_sources, job.barrier_sources) or { return false }
	unsafe { job.barrier_sources = resolved }
	unsafe { job.submitted = true }
	mgr.published << job.queue.id * 10 + 2
	mgr.published_order << job.ordinal
	status := if int(job.ordinal) == mgr.immediate_fault_at { u32(3) } else { u32(0) }
	if int(job.ordinal) == mgr.stop_publish_at { mgr.stop() }
	if mgr.on_publish != unsafe { nil } {
		hook := mgr.on_publish
		mgr.on_publish = unsafe { nil }
		hook()
	}
	if mgr.immediate_complete { mgr.finish_compute(status) }
	return true
}

pub fn (mut mgr GpuManager) submit_g13_render_job(job &G13RenderJobResources) bool {
	if int(job.ordinal) == mgr.stop_submit_at { mgr.stop() }
	if mgr.on_submit != unsafe { nil } {
		hook := mgr.on_submit
		mgr.on_submit = unsafe { nil }
		hook()
	}
	if mgr.state != .running || mgr.ring_full || mgr.render_ring_full
		|| (mgr.publication_limit >= 0 && mgr.published.len >= mgr.publication_limit)
		|| mgr.g13_queue_dispatch_blocked_locked(job.queue) {
		return false
	}
	assert !job.submitted && !job.released
	resolved := mgr.resolve_initial_sources(job.queue, job.initial_sources, job.barrier_sources) or { return false }
	unsafe { job.barrier_sources = resolved }
	unsafe { job.submitted = true }
	mgr.published << job.queue.id * 10
	mgr.published_order << job.ordinal
	status := if int(job.ordinal) == mgr.immediate_fault_at { u32(3) } else { u32(0) }
	if int(job.ordinal) == mgr.stop_publish_at { mgr.stop() }
	if mgr.immediate_complete { mgr.finish_render(status) }
	return true
}

pub fn (mut mgr GpuManager) finish_compute(status u32) {
	for job in mgr.g13_compute_jobs {
		if !job.submitted { continue }
		mgr.finish_compute_at(job.ordinal, status)
		return
	}
	panic('no submitted compute')
}

pub fn (mut mgr GpuManager) finish_compute_at(ordinal u32, status u32) {
	for i, job in mgr.g13_compute_jobs {
		if !job.submitted || job.ordinal != ordinal { continue }
		unsafe { job.error = G13JobError{ status: status } }
		mgr.complete_compute(job, status == 0)
		mgr.g13_compute_jobs.delete(i)
		unsafe { free(job) }
		return
	}
	panic('no submitted compute')
}

pub fn (mut mgr GpuManager) finish_render(status u32) {
	for job in mgr.g13_render_jobs {
		if !job.submitted { continue }
		mgr.finish_render_at(job.ordinal, status)
		return
	}
	panic('no submitted render')
}

pub fn (mut mgr GpuManager) finish_render_at(ordinal u32, status u32) {
	for i, job in mgr.g13_render_jobs {
		if !job.submitted || job.ordinal != ordinal { continue }
		unsafe { job.error = G13JobError{ status: status } }
		mgr.complete_render(job, status == 0)
		mgr.g13_render_jobs.delete(i)
		unsafe { free(job) }
		return
	}
	panic('no submitted render')
}

// Separate firmware stages publish only private completion state. Aggregate
// callbacks and shared job metadata remain owned until finish_render_at/stop.
pub fn (mut mgr GpuManager) finish_render_stage(ordinal u32, pipe u32) {
	assert pipe < 2
	mgr.lock.acquire()
	defer { mgr.lock.release() }
	for job in mgr.g13_render_jobs {
		if !job.submitted || job.ordinal != ordinal { continue }
		if job.stage_finished[pipe] { return }
		unsafe { job.stage_finished[pipe] = true }
		if job.stage_completion != unsafe { nil } { job.stage_completion(pipe, job.data) }
		return
	}
	panic('no submitted render stage')
}

pub fn (mut mgr GpuManager) stop() {
	mgr.lock.acquire()
	mgr.state = .stopped
	mgr.active_operations = 0
	// Prepared metadata remains caller-owned, just as native shutdown does.
	for index := mgr.g13_render_jobs.len - 1; index >= 0; index-- {
		job := mgr.g13_render_jobs[index]
		unsafe {
			job.error = G13JobError{ status: 6 }
			job.released = true
		}
		mgr.complete_render(job, false)
		if job.submitted {
			mgr.g13_render_jobs.delete(index)
			unsafe { free(job) }
		}
	}
	for index := mgr.g13_compute_jobs.len - 1; index >= 0; index-- {
		job := mgr.g13_compute_jobs[index]
		unsafe {
			job.error = G13JobError{ status: 6 }
			job.released = true
		}
		mgr.complete_compute(job, false)
		if job.submitted {
			mgr.g13_compute_jobs.delete(index)
			unsafe { free(job) }
		}
	}
	mgr.lock.release()
}
