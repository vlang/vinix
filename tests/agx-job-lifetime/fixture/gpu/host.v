@[has_globals]
module gpu

import gpu.agx.event
import gpu.agx.fw
import gpu.agx.mmu
import klock

#include <stdio.h>
#define kprintf printf

fn C.kprintf(format &char, ...) i32

struct SharedBuffer {
mut:
	phys u64
	va   u64
	size u64
}

enum State {
	running
	stopped
}

struct Collector {}

fn (mut collector Collector) gc() {}

struct G13JobError {
mut:
	status u32
}

struct G13QueueResources {
mut:
	subqueues         [3]G13SubQueueResources
	render_job_active bool
}

struct GpuManager {
mut:
	lock               klock.Lock
	state              State = .running
	g13_compute_jobs   []&G13ComputeJobResources
	g13_render_jobs    []&G13RenderJobResources
	g13_gpu_readonly   Collector
	g13_private        Collector
	g13_shared         Collector
	invalidation_fails bool
	retirement_fails   bool
	retirements        int
	freed_buffers      int
	pending            int
}

fn (mut mgr GpuManager) invalidate_g13_driver_buffer(mut context mmu.UatContext, buffer &mmu.UatBuffer) bool {
	return !mgr.invalidation_fails
}

fn (mut mgr GpuManager) invalidate_g13_shared_buffer(mut buffer SharedBuffer) bool {
	return !mgr.invalidation_fails
}

fn (mut mgr GpuManager) release_shared_buffer_backing(mut buffer SharedBuffer) {
	if buffer.phys != 0 {
		mgr.freed_buffers++
		buffer = SharedBuffer{}
	}
}

fn (mut mgr GpuManager) free_shared_buffer(mut buffer SharedBuffer) {
	mgr.release_shared_buffer_backing(mut buffer)
}

fn (mut mgr GpuManager) end_g13_operation_locked() bool {
	mgr.pending--
	return true
}

fn (mut mgr GpuManager) retire_g13_subqueue_locked(queue &G13QueueResources, pipe u32, sequence u64, slot u32) bool {
	assert sequence != 0, 'never-published job attempted hardware retirement'
	mgr.retirements++
	return !mgr.retirement_fails
}

fn read_g13_render_result(job &G13RenderJobResources) G13RenderResultValues {
	assert !job.released
	return G13RenderResultValues{ vertex_start: 42 }
}

fn (job &G13ComputeJobResources) timestamp_values() fw.G13JobTimestamps {
	assert !job.released
	return fw.G13JobTimestamps{ start: 42 }
}

struct Completion {
mut:
	calls int
	ok    bool
}

fn compute_done(job &G13ComputeJobResources, successful bool, data voidptr) {
	mut completion := unsafe { &Completion(data) }
	completion.calls++
	completion.ok = successful
}

fn render_done(job &G13RenderJobResources, successful bool, data voidptr) {
	mut completion := unsafe { &Completion(data) }
	completion.calls++
	completion.ok = successful
}

fn (mut mgr GpuManager) compute_job(mut queue G13QueueResources, context &mmu.UatContext, completion &Completion) &G13ComputeJobResources {
	ticket := queue.subqueues[2].events.retain() or { panic('compute event') }
	mut job := &G13ComputeJobResources{
		queue:              unsafe { &queue }
		context:            unsafe { context }
		event_slot:         ticket.slot
		stamp_value:        ticket.value
		event_reserved:     true
		command:            SharedBuffer{ phys: 1 }
		microsequence:      SharedBuffer{ phys: 2 }
		timestamps:         SharedBuffer{ phys: 3 }
		preempt:            &mmu.UatBuffer{}
		mappings_published: true
		completion:         compute_done
		completion_data:    unsafe { completion }
	}
	mgr.g13_compute_jobs << job
	return job
}

fn (mut mgr GpuManager) render_job(mut queue G13QueueResources, context &mmu.UatContext, completion &Completion) &G13RenderJobResources {
	v := queue.subqueues[0].events.retain() or { panic('vertex event') }
	f := queue.subqueues[1].events.retain() or { panic('fragment event') }
	queue.render_job_active = true
	mut job := &G13RenderJobResources{
		queue:                   unsafe { &queue }
		context:                 unsafe { context }
		vertex_event_slot:       v.slot
		fragment_event_slot:     f.slot
		vertex_stamp_value:      v.value
		fragment_stamp_value:    f.value
		vertex_event_reserved:   true
		fragment_event_reserved: true
		vertex:                  SharedBuffer{ phys: 1 }
		fragment:                SharedBuffer{ phys: 2 }
		mappings_published:      true
		completion:              render_done
		completion_data:         unsafe { completion }
	}
	mgr.g13_render_jobs << job
	return job
}

pub fn run_checks() {
	mut stamps := [128]u32{}
	mut firmware := [128]u32{}
	assert event.configure_event_manager(0x10000, unsafe { u64(&stamps) }, 0x20000, unsafe { u64(&firmware) })
	mut queue := G13QueueResources{}
	mut context := mmu.UatContext{}
	mut mgr := GpuManager{}
	mut completion := Completion{}
	prepared := mgr.compute_job(mut queue, &context, &completion)
	mgr.reap_g13_compute_jobs()
	assert completion.calls == 0 && mgr.g13_compute_jobs.len == 1 && mgr.freed_buffers == 0
	mgr.release_g13_compute_job(prepared)
	assert completion.calls == 1 && !completion.ok && mgr.g13_compute_jobs.len == 0
	assert !queue.subqueues[2].events.busy() && mgr.retirements == 0 && mgr.freed_buffers == 3
	// Failed cancellation is retained until invalidation succeeds, without
	// fabricating a ring sequence or invoking completion a second time.
	completion = Completion{}
	quarantined := mgr.compute_job(mut queue, &context, &completion)
	mgr.invalidation_fails = true
	mgr.release_g13_compute_job(quarantined)
	assert completion.calls == 1 && mgr.g13_compute_jobs.len == 1
	mgr.reap_g13_compute_jobs()
	assert mgr.g13_compute_jobs.len == 1 && queue.subqueues[2].events.busy()
	mgr.invalidation_fails = false
	mgr.reap_g13_compute_jobs()
	assert mgr.g13_compute_jobs.len == 0 && completion.calls == 1 && mgr.retirements == 0
	// Two submitted jobs share one slot, but only the earlier stamp has
	// completed. The reverse traversal must retain the later job.
	completion = Completion{}
	mut second_completion := Completion{}
	mut first := mgr.compute_job(mut queue, &context, &completion)
	mut second := mgr.compute_job(mut queue, &context, &second_completion)
	mut ordered := [first, second]!
	for mut job in ordered {
		assert queue.subqueues[2].events.publish(job.event_slot, job.stamp_value)
		job.submitted = true
		job.retirement_sequence = 1
		job.pending_counted = true
		mgr.pending++
	}
	stamps[first.event_slot] = first.stamp_value
	mgr.reap_g13_compute_jobs()
	assert completion.calls == 1 && completion.ok && second_completion.calls == 0
	assert mgr.g13_compute_jobs.len == 1 && queue.subqueues[2].events.busy() && mgr.pending == 1
	stamps[second.event_slot] = second.stamp_value
	mgr.reap_g13_compute_jobs()
	assert second_completion.calls == 1 && mgr.pending == 0 && mgr.g13_compute_jobs.len == 0
	assert !queue.subqueues[2].events.busy()
	completion = Completion{}
	mut render_complete := mgr.render_job(mut queue, &context, &completion)
	assert queue.subqueues[0].events.publish(render_complete.vertex_event_slot, render_complete.vertex_stamp_value)
	assert queue.subqueues[1].events.publish(render_complete.fragment_event_slot, render_complete.fragment_stamp_value)
	render_complete.submitted = true
	render_complete.vertex_retirement_sequence = 1
	render_complete.fragment_retirement_sequence = 1
	render_complete.pending_counted = true
	mgr.pending++
	stamps[render_complete.vertex_event_slot] = render_complete.vertex_stamp_value
	mgr.reap_g13_render_jobs()
	assert completion.calls == 0 && mgr.g13_render_jobs.len == 1
	stamps[render_complete.fragment_event_slot] = render_complete.fragment_stamp_value
	mgr.reap_g13_render_jobs()
	assert completion.calls == 1 && completion.ok && mgr.g13_render_jobs.len == 0 && mgr.pending == 0
	// Shutdown releases backing of a caller-owned prepared job, but leaves
	// the object valid for the caller's eventual discard.
	completion = Completion{}
	caller_owned := mgr.compute_job(mut queue, &context, &completion)
	mgr.state = .stopped
	mgr.release_all_g13_compute_jobs()
	assert caller_owned.released && completion.calls == 1
	mgr.release_g13_compute_job(caller_owned)
	assert completion.calls == 1 && !queue.subqueues[2].events.busy()
	mgr.state = .running
	completion = Completion{}
	mut stopped_job := mgr.compute_job(mut queue, &context, &completion)
	assert queue.subqueues[2].events.publish(stopped_job.event_slot, stopped_job.stamp_value)
	stopped_job.submitted = true
	mgr.state = .stopped
	mgr.release_all_g13_compute_jobs()
	assert completion.calls == 1 && !completion.ok && mgr.g13_compute_jobs.len == 0
	assert !queue.subqueues[2].events.busy()
	// Quarantined unpublished render jobs own no ring sequence. They may
	// be cleaned up on retry or after firmware stops.
	mgr.state = .running
	completion = Completion{}
	render := mgr.render_job(mut queue, &context, &completion)
	mgr.invalidation_fails = true
	mgr.release_g13_render_job(render)
	assert completion.calls == 1 && mgr.g13_render_jobs.len == 1
	mgr.invalidation_fails = false
	mgr.reap_g13_render_jobs()
	assert mgr.g13_render_jobs.len == 0 && !queue.render_job_active
	assert !queue.subqueues[0].events.busy() && !queue.subqueues[1].events.busy()
	completion = Completion{}
	_ = mgr.render_job(mut queue, &context, &completion)
	mgr.g13_render_jobs[0].quarantined = true
	mgr.state = .stopped
	mgr.release_all_g13_render_jobs()
	assert completion.calls == 1 && mgr.g13_render_jobs.len == 0
	assert !queue.render_job_active
	assert !queue.subqueues[0].events.busy() && !queue.subqueues[1].events.busy()
	event.reset_event_manager()
	println('AGX job lifetimes: prepared ownership, shared-stamp retirement, failed invalidation, discard retry and firmware-stopped cleanup passed')
}
