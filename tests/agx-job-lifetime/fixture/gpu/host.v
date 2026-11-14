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
	subqueues     [3]G13SubQueueResources
	render_buffer G13RenderBufferResources
	vm            &mmu.UatContext = unsafe { nil }
	released      bool
}

struct G13RenderBufferResources {
mut:
	info             SharedBuffer
	initialized      bool = true
	slot             u32
	slot_reserved    bool
	slot_token_valid bool
	active_scenes    u32
	needs_bind       bool
}

struct GpuManager {
mut:
	lock                  klock.Lock
	state                 State = .running
	g13_compute_jobs      []&G13ComputeJobResources
	g13_render_jobs       []&G13RenderJobResources
	g13_gpu_readonly      Collector
	g13_private           Collector
	g13_shared            Collector
	invalidation_fails    bool
	retirement_fails      bool
	retirements           int
	freed_buffers         int
	pending               int
	g13_tvb_slots         [127]bool
	g13_tvb_owners        [127]u64
	g13_tvb_free_order    [127]u64
	g13_tvb_release_clock u64
	g13_queues            []&G13QueueResources
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
	assert mgr.retain_g13_scene_slot_locked(mut queue.render_buffer)
	mut job := &G13RenderJobResources{
		queue:                   unsafe { &queue }
		context:                 unsafe { context }
		vertex_event_slot:       v.slot
		fragment_event_slot:     f.slot
		vertex_stamp_value:      v.value
		fragment_stamp_value:    f.value
		vertex_event_reserved:   true
		fragment_event_reserved: true
		scene_reserved:          true
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
	check_scene_slots()
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
	// Overlapping scenes hold the same TVB lease. Completing one does not
	// return the slot or either shared event until the other completes.
	completion = Completion{}
	second_completion = Completion{}
	mut render_a := mgr.render_job(mut queue, &context, &completion)
	mut render_b := mgr.render_job(mut queue, &context, &second_completion)
	mut scenes := [render_a, render_b]!
	for mut job in scenes {
		assert queue.subqueues[0].events.publish(job.vertex_event_slot, job.vertex_stamp_value)
		assert queue.subqueues[1].events.publish(job.fragment_event_slot, job.fragment_stamp_value)
		job.submitted = true
		job.vertex_retirement_sequence = 1
		job.fragment_retirement_sequence = 1
	}
	assert queue.render_buffer.active_scenes == 2 && queue.render_buffer.slot_reserved
	stamps[render_a.vertex_event_slot] = render_a.vertex_stamp_value
	stamps[render_a.fragment_event_slot] = render_a.fragment_stamp_value
	mgr.reap_g13_render_jobs()
	assert completion.calls == 1 && second_completion.calls == 0
	assert queue.render_buffer.active_scenes == 1 && queue.render_buffer.slot_reserved
	stamps[render_b.vertex_event_slot] = render_b.vertex_stamp_value
	stamps[render_b.fragment_event_slot] = render_b.fragment_stamp_value
	mgr.reap_g13_render_jobs()
	assert second_completion.calls == 1 && queue.render_buffer.active_scenes == 0
	assert !queue.render_buffer.slot_reserved && !mgr.g13_tvb_slots[queue.render_buffer.slot]
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
	assert mgr.g13_render_jobs.len == 0 && queue.render_buffer.active_scenes == 0
	assert !queue.subqueues[0].events.busy() && !queue.subqueues[1].events.busy()
	completion = Completion{}
	_ = mgr.render_job(mut queue, &context, &completion)
	mgr.g13_render_jobs[0].quarantined = true
	mgr.state = .stopped
	mgr.release_all_g13_render_jobs()
	assert completion.calls == 1 && mgr.g13_render_jobs.len == 0
	assert queue.render_buffer.active_scenes == 0
	assert !queue.subqueues[0].events.busy() && !queue.subqueues[1].events.busy()
	event.reset_event_manager()
	println('AGX job lifetimes: prepared ownership, shared-stamp retirement, failed invalidation, discard retry and firmware-stopped cleanup passed')
}

fn check_scene_slots() {
	mut mgr := GpuManager{}
	mut buffers := [128]G13RenderBufferResources{}
	assert mgr.g13_tvb_slots.all(!it), 'idle queues must not reserve TVB slots'
	for i in 0 .. 127 {
		buffers[i].info.va = u64(i + 1) * 0x1000
		assert mgr.retain_g13_scene_slot_locked(mut buffers[i])
		assert buffers[i].slot == u32(i) && buffers[i].active_scenes == 1
	}
	assert !mgr.retain_g13_scene_slot_locked(mut buffers[127])
	assert buffers[127].active_scenes == 0 && !buffers[127].slot_reserved
	buffers[127].info.va = 0x80000
	assert mgr.retain_g13_scene_slot_locked(mut buffers[0])
	assert buffers[0].active_scenes == 2
	mgr.release_g13_scene_slot_locked(mut buffers[0])
	assert buffers[0].active_scenes == 1 && mgr.g13_tvb_slots[0]
	mgr.release_g13_scene_slot_locked(mut buffers[0])
	assert !mgr.g13_tvb_slots[0]
	assert mgr.retain_g13_scene_slot_locked(mut buffers[127])
	assert buffers[127].slot == 0
	for i in 1 .. 128 { mgr.release_g13_scene_slot_locked(mut buffers[i]) }
	assert mgr.g13_tvb_slots.all(!it)
	// The hint is reused without rebinding only when no intervening owner
	// used the slot, and an unpublished binding remains required.
	buffers[0].needs_bind = false
	assert mgr.retain_g13_scene_slot_locked(mut buffers[0])
	assert buffers[0].needs_bind, 'another buffer used the previous slot'
	assert buffers[0].slot == 1, 'a changed token must select the oldest free slot'
	buffers[0].needs_bind = false
	mgr.release_g13_scene_slot_locked(mut buffers[0])
	assert mgr.retain_g13_scene_slot_locked(mut buffers[0])
	assert !buffers[0].needs_bind, 'an unchanged token retains its firmware binding'
	mgr.release_g13_scene_slot_locked(mut buffers[0])
	buffers[0].needs_bind = true
	assert mgr.retain_g13_scene_slot_locked(mut buffers[0])
	mgr.release_g13_scene_slot_locked(mut buffers[0])
	assert mgr.retain_g13_scene_slot_locked(mut buffers[0])
	assert buffers[0].needs_bind, 'canceled first bind must not be mistaken for a published bind'
	mgr.release_g13_scene_slot_locked(mut buffers[0])
	mut vm := mmu.UatContext{}
	mut stale := G13QueueResources{ vm: &vm }
	mut live := G13QueueResources{ vm: &vm }
	mgr.g13_queues = [&stale, &live]
	assert mgr.retain_g13_scene_slot_locked(mut stale.render_buffer)
	mgr.release_g13_scene_slot_locked(mut stale.render_buffer)
	assert mgr.g13_tvb_owner_locked(vm.id, stale.render_buffer.slot) == none
	assert mgr.retain_g13_scene_slot_locked(mut live.render_buffer)
	stale.render_buffer.slot = live.render_buffer.slot
	owner := mgr.g13_tvb_owner_locked(vm.id, live.render_buffer.slot) or { panic('live scene owner') }
	assert owner == &live.render_buffer
	assert mgr.g13_tvb_owner_locked(vm.id + 1, live.render_buffer.slot) == none
	live.released = true
	assert mgr.g13_tvb_owner_locked(vm.id, live.render_buffer.slot) == none
	mgr.release_g13_scene_slot_locked(mut live.render_buffer)
}
