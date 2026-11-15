@[has_globals]
module gpu

import gpu.agx.event
import gpu.agx.fw
import gpu.agx.mmu
import gpu.agx.channel
import klock
import memory

#include <stdio.h>
#define kprintf printf

fn C.kprintf(format &char, ...) i32

__global higher_half = u64(0)

struct GpuChannels {
mut:
	pipes [12]channel.TxChannel
}

enum Generation { g13 other }
struct Config { gpu_gen Generation = .g13 }

fn pipe_index(priority u32, pipe u32) int { return int(priority * 3 + pipe) }

fn (mut mgr GpuManager) g13_pending_submissions_locked() ?&u32 {
	if mgr.pending_missing { return none }
	return unsafe { &mgr.batch_pending }
}

fn (mut mgr GpuManager) kick_firmware() bool {
	mgr.kicks++
	return !mgr.kick_fails
}

fn (mut mgr GpuManager) ring_pipe(priority u32, pipe u32) bool {
	assert priority < 4
	mgr.doorbells << pipe
	mut submitted := u32(0)
	for job in mgr.g13_compute_jobs {
		if mgr.expected_owned == 0 { assert job.submitted }
		if job.submitted { assert job.pending_counted; submitted++ }
	}
	for job in mgr.g13_render_jobs {
		if mgr.expected_owned == 0 { assert job.submitted }
		if job.submitted { assert job.pending_counted; submitted++ }
	}
	if mgr.expected_owned != 0 { assert submitted == mgr.expected_owned }
	return mgr.doorbell_fail != int(pipe)
}

struct SharedBuffer {
mut:
	phys u64
	va   u64
	size u64
}

fn (buffer &SharedBuffer) cpu_address() voidptr { return voidptr(buffer.phys) }

enum State {
	running
	error
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
	initial_events [2]G13InitialEvent
	subqueues     [3]G13SubQueueResources
	render_buffer G13RenderBufferResources
	vm            &mmu.UatContext = unsafe { nil }
	released      bool
	quarantined bool
	mappings_published bool
	priority u32
	channel_mask u32 = 7
	threshold SharedBuffer
}

struct G13RenderBufferResources {
mut:
	context &mmu.UatContext = unsafe { nil }
	tail_pointer_cache &G13TailPointerCache = unsafe { nil }
	info             SharedBuffer
	initialized      bool = true
	slot             u32
	slot_reserved    bool
	slot_token_valid bool
	active_scenes    u32
	needs_bind       bool
	bound_blocks     u32
	blocks []&mmu.UatBuffer
	block_list &mmu.UatBuffer = unsafe { nil }
	page_list &mmu.UatBuffer = unsafe { nil }
	kernel_buffer SharedBuffer
	stats SharedBuffer
	counter SharedBuffer
	block_control SharedBuffer
}

struct GpuManager {
mut:
	g13_events G13EventResources
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
	driver_invalidations int
	pending               int
	g13_tvb_slots         [127]bool
	g13_tvb_owners        [127]u64
	g13_tvb_free_order    [127]u64
	g13_tvb_release_clock u64
	g13_queues            []&G13QueueResources
	flush_fails bool
	flushes int
	channels GpuChannels
	hw_config Config
	g13_channels &u8 = unsafe { nil }
	batch_pending u32
	pending_missing bool
	kicks int
	kick_fails bool
	doorbells []u32
	doorbell_fail int = -1
	expected_owned u32
}

struct G13EventResources {
	mut:
	initialized bool = true
}

fn (mut mgr GpuManager) flush_g13_kernel_buffer(buffer &SharedBuffer) bool {
	assert buffer.phys != 0 && buffer.size != 0
	mgr.flushes++
	return !mgr.flush_fails
}

fn (mut mgr GpuManager) invalidate_g13_driver_buffer(mut context mmu.UatContext, buffer &mmu.UatBuffer) bool {
	if buffer != unsafe { nil } { mgr.driver_invalidations++ }
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

fn (mut mgr GpuManager) free_g13_queue_resources_locked(mut queue G13QueueResources, invalidate bool) bool {
	if invalidate && mgr.invalidation_fails { return false }
	mgr.free_g13_render_buffer_locked(mut queue.render_buffer)
	queue.released = true
	return true
}

fn (mut mgr GpuManager) end_g13_operation_locked() bool {
	mgr.pending--
	if mgr.batch_pending != 0 { mgr.batch_pending-- }
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
	check_prepared_job_backlog()
	check_batch_publication()
	check_batch_admission()
	check_initial_barrier_lifetimes()
	check_initial_cancellation_fallback()
	check_initial_acceptance_and_reset()
	check_initial_compaction()
	check_barrier_lifetimes()
	check_published_batches()
	check_scene_slots()
	check_tail_pointer_cache()
	check_queue_cleanup_retry()
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

fn check_published_batches() {
	for count in [64, 127]! { check_published_batch(count) }
	println('AGX published lifetimes: 64 published and 127 prepared compute/render jobs; the 127th waits for host retirement, then resumes; reverse traversal and vertex-only retention pass')
}

fn check_published_batch(count int) {
	for render in [false, true]! {
		mut stamps := [128]u32{}
		mut firmware := [128]u32{}
		assert event.configure_event_manager(0x10000, unsafe { u64(&stamps) }, 0x20000, unsafe { u64(&firmware) })
		mut queue := G13QueueResources{}
		mut context := mmu.UatContext{}
		mut mgr := GpuManager{}
		mut completions := [127]Completion{}
		mut last_vertex := u32(0)
		mut last_fragment := u32(0)
		mut vertex_slot := u32(0)
		mut fragment_slot := u32(0)
		early := if count == 127 { 1 } else { 0 }
		for index in 0 .. count {
			if render {
				mut job := mgr.render_job(mut queue, &context, unsafe { &completions[index] })
				if index == 126 {
					assert !queue.subqueues[0].events.can_publish(job.vertex_event_slot, job.vertex_stamp_value)
					assert !queue.subqueues[1].events.can_publish(job.fragment_event_slot, job.fragment_stamp_value)
					first := mgr.g13_render_jobs[0]
					stamps[first.vertex_event_slot] = first.vertex_stamp_value
					stamps[first.fragment_event_slot] = first.fragment_stamp_value
					mgr.reap_g13_render_jobs()
					assert completions[0].calls == 1 && completions[index].calls == 0
				}
				assert queue.subqueues[0].events.publish(job.vertex_event_slot, job.vertex_stamp_value)
				assert queue.subqueues[1].events.publish(job.fragment_event_slot, job.fragment_stamp_value)
				job.submitted = true
				job.pending_counted = true
				job.vertex_retirement_sequence = u64(index + 1)
				job.fragment_retirement_sequence = u64(index + 1)
				last_vertex = job.vertex_stamp_value
				last_fragment = job.fragment_stamp_value
				vertex_slot = job.vertex_event_slot
				fragment_slot = job.fragment_event_slot
			} else {
				mut job := mgr.compute_job(mut queue, &context, unsafe { &completions[index] })
				if index == 126 {
					assert !queue.subqueues[2].events.can_publish(job.event_slot, job.stamp_value)
					first := mgr.g13_compute_jobs[0]
					stamps[first.event_slot] = first.stamp_value
					mgr.reap_g13_compute_jobs()
					assert completions[0].calls == 1 && completions[index].calls == 0
				}
				assert queue.subqueues[2].events.publish(job.event_slot, job.stamp_value)
				job.submitted = true
				job.pending_counted = true
				job.retirement_sequence = u64(index + 1)
				last_vertex = job.stamp_value
				vertex_slot = job.event_slot
			}
			mgr.pending++
		}
		assert mgr.pending == count - early
		stamps[vertex_slot] = last_vertex
		if render {
			mgr.reap_g13_render_jobs()
			assert mgr.g13_render_jobs.len == count - early && queue.render_buffer.active_scenes == count - early
			for index in 0 .. count {
				assert completions[index].calls == if index < early { 1 } else { 0 }
			}
			stamps[fragment_slot] = last_fragment
			mgr.reap_g13_render_jobs()
			assert mgr.retirements == 2 * count && queue.render_buffer.active_scenes == 0
			assert !queue.render_buffer.slot_reserved
		} else {
			mgr.reap_g13_compute_jobs()
			assert mgr.retirements == count && context.releases == count
		}
		for index in 0 .. count {
			assert completions[index].calls == 1 && completions[index].ok
		}
		assert mgr.pending == 0 && mgr.g13_compute_jobs.len == 0 && mgr.g13_render_jobs.len == 0
		for subqueue in queue.subqueues {
			assert !subqueue.events.busy()
		}
		event.reset_event_manager()
	}
}

fn check_queue_cleanup_retry() {
	mut mgr := GpuManager{}
	mut queue := G13QueueResources{mappings_published: true}
	mgr.g13_queues << &queue
	mgr.invalidation_fails = true
	assert !mgr.release_g13_queue_resources(&queue)
	assert queue.quarantined && !queue.released && mgr.g13_queues.len == 1
	mgr.invalidation_fails = false
	assert mgr.release_g13_queue_resources(&queue), 'quarantine must block new work while allowing cleanup retry'
	assert queue.released && mgr.g13_queues.len == 0
	assert mgr.release_g13_queue_resources(&queue)
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

fn check_tail_pointer_cache() {
	mut context := mmu.UatContext{}
	mut owner := G13RenderBufferResources{context: &context}
	mut mgr := GpuManager{}
	first := mgr.retain_g13_tpc_locked(mut owner, 1) or { panic('initial TPC') }
	assert first.buffer.size == 0x4000 && first.references == 2 && context.allocations == 1
	// A full render batch prepares 64 scenes before publishing its first.
	for _ in 0 .. 64 {
		shared := mgr.retain_g13_tpc_locked(mut owner, 1) or { panic('batch TPC') }
		assert voidptr(shared) == voidptr(first)
	}
	assert first.references == 66 && context.allocations == 1
	for _ in 0 .. 64 {
		assert mgr.invalidate_g13_tpc_locked(mut context, first)
		mgr.release_g13_tpc_locked(mut context, first)
	}
	assert first.references == 2 && mgr.driver_invalidations == 0
	for _ in 0 .. 500 {
		cached := mgr.retain_g13_tpc_locked(mut owner, 0x4000) or { panic('reused TPC') }
		assert voidptr(cached) == voidptr(first) && cached.references == 3
		assert mgr.invalidate_g13_tpc_locked(mut context, cached)
		mgr.release_g13_tpc_locked(mut context, cached)
	}
	assert context.allocations == 1 && context.releases == 0 && memory.outstanding() == 1
	assert mgr.driver_invalidations == 0, 'shared backing must not be unmapped by a retiring scene'
	mgr.release_g13_tpc_locked(mut context, first)
	assert owner.tail_pointer_cache.references == 1
	second := mgr.retain_g13_tpc_locked(mut owner, 0x4001) or { panic('grown TPC') }
	assert second.buffer.size == 0x8000 && context.pool[0].released
	assert context.releases == 1 && memory.outstanding() == 1 && mgr.driver_invalidations == 1
	third := mgr.retain_g13_tpc_locked(mut owner, 0x8001) or { panic('overlapping growth') }
	assert voidptr(third) != voidptr(second) && !second.buffer.released && second.references == 1
	assert memory.outstanding() == 2 && context.releases == 1
	assert mgr.invalidate_g13_tpc_locked(mut context, second)
	mgr.release_g13_tpc_locked(mut context, second)
	assert context.pool[1].released && context.releases == 2 && memory.outstanding() == 1
	assert mgr.invalidate_g13_tpc_locked(mut context, third)
	mgr.release_g13_tpc_locked(mut context, third)
	assert owner.tail_pointer_cache.references == 1 && !owner.tail_pointer_cache.retiring
	count := context.allocations
	memory.fail_next(true)
	assert mgr.retain_g13_tpc_locked(mut owner, 0x30000) == none
	memory.fail_next(false)
	assert context.allocations == count && memory.outstanding() == 1
	context.fail_allocation = true
	assert mgr.retain_g13_tpc_locked(mut owner, 0x30000) == none
	context.fail_allocation = false
	assert context.allocations == count && memory.outstanding() == 1
	// An interrupted UAT teardown cannot make a partially unmapped cache
	// reusable. It stays owned until a successful retry or firmware stop.
	mgr.invalidation_fails = true
	old := owner.tail_pointer_cache
	assert mgr.retain_g13_tpc_locked(mut owner, 0x30000) == none
	assert voidptr(old) == voidptr(owner.tail_pointer_cache) && old.retiring && !old.buffer.released
	assert memory.outstanding() == 1 && context.pool[count].released
	mgr.invalidation_fails = false
	old_identity := voidptr(old)
	recovered := mgr.retain_g13_tpc_locked(mut owner, 1) or { panic('retirement retry') }
	assert voidptr(recovered) != old_identity && context.pool[2].released && !recovered.retiring
	mgr.release_g13_tpc_locked(mut context, recovered)
	assert mgr.invalidate_g13_tpc_locked(mut context, owner.tail_pointer_cache)
	mgr.free_g13_render_buffer_locked(mut owner)
	assert context.allocations == context.releases && memory.outstanding() == 0
	// On shutdown, stopped firmware removes the need for a live handshake.
	mgr.state = .running
	owner = G13RenderBufferResources{context: &context}
	a := mgr.retain_g13_tpc_locked(mut owner, 1) or { panic('shutdown cache a') }
	b := mgr.retain_g13_tpc_locked(mut owner, 0x10000) or { panic('shutdown cache b') }
	mgr.state = .stopped
	mgr.release_g13_tpc_locked(mut context, a)
	mgr.release_g13_tpc_locked(mut context, b)
	mgr.free_g13_render_buffer_locked(mut owner)
	assert context.allocations == context.releases && memory.outstanding() == 0
	println('AGX TPC: 500 reuses, page rounding, overlapping growth, final-owner invalidation, allocation/flush failure, retry and shutdown passed')
}
