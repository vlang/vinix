@[has_globals]
module gpu

import gpu.agx.compute
import gpu.agx.render
import gpu.agx.mmu
import klock

pub enum State {
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
	released    bool
	quarantined bool
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
	ordinal     u32
	completion  fn (&G13ComputeJobResources, bool, voidptr) = unsafe { nil }
	data        voidptr
}

pub struct G13RenderJobResources {
pub mut:
	queue       &G13QueueResources = unsafe { nil }
	error       G13JobError
	submitted   bool
	released    bool
	quarantined bool
	ordinal     u32
	completion  fn (&G13RenderJobResources, bool, voidptr) = unsafe { nil }
	data        voidptr
}

pub struct GpuManager {
pub mut:
	lock                  klock.Lock
	state                 State = .running
	hw_config             Config
	g13_compute_jobs      []&G13ComputeJobResources
	g13_render_jobs       []&G13RenderJobResources
	published             []u32
	released_order        []u32
	prepares              int
	callbacks             int
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
	immediate_complete    bool
	stop_after_callback   bool
	on_publish            fn () = unsafe { nil }
}

__global test_async_gpu_manager GpuManager

pub fn reset() {
	assert test_async_gpu_manager.g13_compute_jobs.len == 0 && test_async_gpu_manager.g13_render_jobs.len == 0
	unsafe {
		test_async_gpu_manager.g13_compute_jobs.free()
		test_async_gpu_manager.g13_render_jobs.free()
		test_async_gpu_manager.published.free()
		test_async_gpu_manager.released_order.free()
	}
	test_async_gpu_manager = GpuManager{}
	test_async_gpu_manager.g13_compute_jobs.flags |= .noslices
	test_async_gpu_manager.g13_render_jobs.flags |= .noslices
	test_async_gpu_manager.published.flags |= .noslices
	test_async_gpu_manager.released_order.flags |= .noslices
}

pub fn get_global_manager() ?&GpuManager { return unsafe { &test_async_gpu_manager } }

pub fn (job &G13ComputeJobResources) timestamp_values() ComputeValues { return ComputeValues{} }

pub fn (job &G13RenderJobResources) result_values() RenderValues { return RenderValues{} }

pub fn (mut mgr GpuManager) prepare_g13_compute_job(queue &G13QueueResources, ctx &mmu.UatContext,
	input &compute.Command) ?&G13ComputeJobResources {
	if mgr.fail_compute { return none }
	index := mgr.prepares
	mgr.prepares++
	if index == mgr.fail_prepare_at { return none }
	job := &G13ComputeJobResources{ queue: unsafe { queue }, marker: input.encoder_ptr, ordinal: u32(index) }
	mgr.g13_compute_jobs << job
	return job
}

pub fn (mut mgr GpuManager) prepare_g13_render_job(queue &G13QueueResources,
	input &render.Command) ?&G13RenderJobResources {
	if mgr.fail_render { return none }
	index := mgr.prepares
	mgr.prepares++
	if index == mgr.fail_prepare_at { return none }
	job := &G13RenderJobResources{ queue: unsafe { queue }, ordinal: u32(index) }
	mgr.g13_render_jobs << job
	return job
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

pub fn (mut mgr GpuManager) set_g13_render_completion(job &G13RenderJobResources,
	callback fn (&G13RenderJobResources, bool, voidptr), data voidptr) bool {
	if mgr.fail_render_callback || job.released || job.submitted || job.completion != unsafe { nil } {
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
	if mgr.state != .running || mgr.ring_full { return false }
	assert !job.submitted && !job.released
	unsafe { job.submitted = true }
	mgr.published << job.queue.id * 10 + 2
	if mgr.on_publish != unsafe { nil } {
		hook := mgr.on_publish
		mgr.on_publish = unsafe { nil }
		hook()
	}
	if mgr.immediate_complete { mgr.finish_compute(0) }
	return true
}

pub fn (mut mgr GpuManager) submit_g13_render_job(job &G13RenderJobResources) bool {
	if mgr.state != .running || mgr.ring_full { return false }
	assert !job.submitted && !job.released
	unsafe { job.submitted = true }
	mgr.published << job.queue.id * 10
	if mgr.immediate_complete { mgr.finish_render(0) }
	return true
}

pub fn (mut mgr GpuManager) finish_compute(status u32) {
	for i, job in mgr.g13_compute_jobs {
		if !job.submitted { continue }
		unsafe { job.error = G13JobError{ status: status } }
		mgr.complete_compute(job, status == 0)
		mgr.g13_compute_jobs.delete(i)
		unsafe { free(job) }
		return
	}
	panic('no submitted compute')
}

pub fn (mut mgr GpuManager) finish_render(status u32) {
	for i, job in mgr.g13_render_jobs {
		if !job.submitted { continue }
		unsafe { job.error = G13JobError{ status: status } }
		mgr.complete_render(job, status == 0)
		mgr.g13_render_jobs.delete(i)
		unsafe { free(job) }
		return
	}
	panic('no submitted render')
}

pub fn (mut mgr GpuManager) stop() {
	mgr.lock.acquire()
	mgr.state = .stopped
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
