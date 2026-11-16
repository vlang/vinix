@[has_globals]
module file

import drm.gem
import drm.ioctl
import drm.syncobj
import gpu.agx.gpu
import gpu.agx.mmu
import klock
import memory
import usercopy

struct LogicalQueue {
	id    u32
	vm_id u32 = 1
	caps  u32 = 5
}

struct Ownership {
	queue_id  u32
	resources &gpu.G13QueueResources
}

struct Objects {
	object &gem.GemObject = unsafe { nil }
}

fn (objects &Objects) find(handle u32) ?&gem.GemObject {
	if handle == 7 && objects.object != unsafe { nil } { return objects.object }
	return none
}

struct GpuFile {
mut:
	owner_key      u64 = 1
	lock           klock.Lock
	queues         []LogicalQueue
	g13_queues     []Ownership
	vm             &mmu.UatContext = unsafe { nil }
	objects        Objects
	inflight_by_vm [64]u64
	mapping_retry_blocked bool
}

// Mapping/page-table services are injected here; the close fixture exercises
// the production retirement helper and ioctl mapping paths.
fn (mut file GpuFile) cleanup_closed_mappings_locked(_vm_id u32) bool {
	return !file.mapping_retry_blocked
}

fn (file &GpuFile) find_vm(id u32) ?&mmu.UatContext {
	if id == 1 { return file.vm }
	return none
}

__global file_reaps = 0

fn reap_closed_files() { file_reaps++ }

fn new_file() &GpuFile {
	ctx := &mmu.UatContext{}
	q1 := &gpu.G13QueueResources{ id: 1, fence_context: syncobj.new_queue_context() or { panic('queue context') } }
	q2 := &gpu.G13QueueResources{ id: 2, fence_context: syncobj.new_queue_context() or { panic('queue context') } }
	return &GpuFile{
		queues:     [LogicalQueue{ id: 1 }, LogicalQueue{ id: 2 }]
		g13_queues: [Ownership{ queue_id: 1, resources: q1 }, Ownership{ queue_id: 2, resources: q2 }]
		vm:         ctx
	}
}

fn submit(mut file GpuFile, queue u32, pair bool, input &syncobj.SyncObj, output &syncobj.SyncObj, results bool) int {
	compute := ioctl.DrmAsahiCmdCompute{ encoder_ptr: 0x12340000 }
	render := ioctl.DrmAsahiCmdRender{
		fb_width:     32
		fb_height:    32
		layers:       1
		utile_width:  32
		utile_height: 32
		samples:      1
	}
	mut commands := [2]ioctl.DrmAsahiCommand{}
	commands[0] = ioctl.DrmAsahiCommand{
		cmd_type:        ioctl.asahi_cmd_compute
		cmd_buffer:      u64(&compute)
		cmd_buffer_size: sizeof(compute)
		barriers:        [ioctl.asahi_barrier_none, ioctl.asahi_barrier_none]!
	}
	if results { commands[0].result_size = sizeof(ioctl.DrmAsahiResultCompute) }
	commands[1] = ioctl.DrmAsahiCommand{
		cmd_type:        ioctl.asahi_cmd_render
		cmd_buffer:      u64(&render)
		cmd_buffer_size: sizeof(render)
		barriers:        [ioctl.asahi_barrier_none, u32(1)]!
	}
	if results {
		commands[1].result_offset = 64
		commands[1].result_size = sizeof(ioctl.DrmAsahiResultRender)
	}
	in_sync := ioctl.DrmAsahiSync{ handle: if input != unsafe { nil } { input.handle } else { 0 } }
	out_sync := ioctl.DrmAsahiSync{ handle: if output != unsafe { nil } { output.handle } else { 0 } }
	request := ioctl.DrmAsahiSubmit{
		queue_id:       queue
		commands:       unsafe { u64(&commands) }
		command_count:  if pair { 2 } else { 1 }
		result_handle:  if results { 7 } else { 0 }
		in_syncs:       u64(&in_sync)
		out_syncs:      u64(&out_sync)
		in_sync_count:  if input != unsafe { nil } { 1 } else { 0 }
		out_sync_count: if output != unsafe { nil } { 1 } else { 0 }
	}
	return file.ioctl_submit(&request)
}

fn output() &syncobj.SyncObj { return syncobj.new_syncobj(1) or { panic('syncobj') } }

fn fence(object &syncobj.SyncObj) &syncobj.DmaFence {
	return syncobj.get_fence(object) or { panic('fence') }
}

fn assert_drained(file &GpuFile) {
	assert pending_head == unsafe { nil } && pending_tail == unsafe { nil } && pending_count == 0
	assert file.inflight_by_vm[1] == 0 && memory.outstanding() == 0
	manager := gpu.get_global_manager() or { panic('manager') }
	assert manager.g13_compute_jobs.len == 0 && manager.g13_render_jobs.len == 0
	assert manager.capture_pins == 0
}

fn check_dependencies_and_fifo() {
	gpu.reset()
	mut file := new_file()
	mut manager := gpu.get_global_manager() or { panic('manager') }
	input := output()
	dependency := syncobj.new_fence(1, 1)
	syncobj.replace_fence(input, dependency)
	a := output()
	b := output()
	c := output()
	assert submit(mut file, 1, false, input, a, false) == 0
	assert submit(mut file, 1, false, unsafe { nil }, b, false) == 0
	assert submit(mut file, 2, false, unsafe { nil }, c, false) == 0
	assert manager.published.len == 0 && pending_count == 3 && file.inflight_by_vm[1] == 6
	// Userspace input was stack-owned; worker only sees immutable prepared jobs.
	assert manager.g13_compute_jobs[0].marker == 0x12340000
	service_file_work()
	assert manager.published == [u32(22)], 'blocked queue must not stall an unrelated queue'
	manager.finish_compute(0)
	service_file_work()
	assert pending_count == 2 && !syncobj.is_signaled(fence(a)) && syncobj.is_signaled(fence(c))
	syncobj.signal(dependency)
	service_file_work()
	assert manager.published == [u32(22), 12, 12]
	manager.finish_compute(0)
	service_file_work()
	assert manager.published == [u32(22), 12, 12]
	manager.finish_compute(0)
	service_file_work()
	assert_drained(file)
}

fn check_pair_and_forged_fence() {
	gpu.reset()
	mut file := new_file()
	mut manager := gpu.get_global_manager() or { panic('manager') }
	mut result := [192]u8{}
	mut object := gem.GemObject{ size: sizeof(result), virt_addr: unsafe { u64(&result) } }
	file.objects = Objects{ object: &object }
	out := output()
	assert submit(mut file, 1, true, unsafe { nil }, out, true) == 0
	assert file.inflight_by_vm[1] == 3 && object.references == 3
	syncobj.signal(fence(out)) // clients must not drive internal phase/lifetime
	service_file_work()
	assert manager.published == [u32(12), 10] && memory.outstanding() == 1
	service_file_work()
	assert manager.published == [u32(12), 10] && file.inflight_by_vm[1] == 3
	manager.finish_compute(0)
	assert file.inflight_by_vm[1] == 2 && object.references == 2
	service_file_work()
	assert manager.published == [u32(12), 10]
	manager.finish_render(0)
	assert file.inflight_by_vm[1] == 1 && object.references == 1
	service_file_work()
	assert_drained(file)
	compute := unsafe { &ioctl.DrmAsahiResultCompute(&result[0]) }
	render := unsafe { &ioctl.DrmAsahiResultRender(&result[64]) }
	assert compute.info.status == 1 && compute.ts_start == 11 && render.info.status == 1
}

fn check_failures() {
	for mode in 0 .. 8 {
		gpu.reset()
		mut file := new_file()
		mut manager := gpu.get_global_manager() or { panic('manager') }
		out := output()
		manager.fail_compute = mode == 0
		manager.fail_render = mode == 1
		manager.fail_compute_callback = mode == 2
		manager.fail_render_callback = mode == 3
		manager.stop_after_callback = mode == 4
		memory.fail_next(mode == 5)
		usercopy.reject(mode == 6)
		queue := if mode == 7 { u32(3) } else { u32(1) }
		code := submit(mut file, queue, true, unsafe { nil }, out, false)
		memory.fail_next(false)
		usercopy.reject(false)
		assert code < 0
		assert_drained(file)
	}
	// A signaled dependency's error does not become this job's error.
	gpu.reset()
	mut file := new_file()
	mut manager := gpu.get_global_manager() or { panic('manager') }
	input := output()
	out := output()
	failed := syncobj.new_fence(1, 1)
	syncobj.signal_error(failed, -110)
	syncobj.replace_fence(input, failed)
	assert submit(mut file, 1, true, input, out, false) == 0
	service_file_work()
	assert manager.published == [u32(12), 10] && !syncobj.is_signaled(fence(out))
	manager.finish_compute(0)
	manager.finish_render(0)
	service_file_work()
	assert syncobj.get_error(fence(out)) == 0 && syncobj.is_signaled(fence(out))
	syncobj.signal_error(fence(out), -19)
	assert syncobj.get_error(fence(out)) == 0, 'late shutdown changed a completed success'
	assert_drained(file)
	// A compute fault also cancels the unsubmitted render half.
	gpu.reset()
	manager = gpu.get_global_manager() or { panic('manager') }
	failed_compute := output()
	assert submit(mut file, 1, true, unsafe { nil }, failed_compute, false) == 0
	manager.render_ring_full = true
	service_file_work()
	manager.finish_compute(3)
	service_file_work()
	assert manager.published == [u32(12)]
	assert syncobj.get_error(fence(failed_compute)) == -110
	syncobj.signal_error(fence(failed_compute), -125)
	syncobj.signal(fence(failed_compute))
	assert syncobj.get_error(fence(failed_compute)) == -110, 'late cancellation changed the original GPU error'
	assert_drained(file)
	println('AGX completed output fences: real ioctl success/fault retain original status after late shutdown/cancellation signals')
}

__global append_file &GpuFile = unsafe { nil }

fn append_during_poll() {
	mut file := unsafe { append_file }
	assert submit(mut file, 1, false, unsafe { nil }, unsafe { nil }, false) == 0
}

fn check_append_and_backpressure() {
	gpu.reset()
	mut file := new_file()
	mut manager := gpu.get_global_manager() or { panic('manager') }
	assert submit(mut file, 1, false, unsafe { nil }, unsafe { nil }, false) == 0
	first := voidptr(pending_head)
	manager.g13_compute_jobs[0].quarantined = true
	service_file_work()
	assert manager.published.len == 0 && pending_count == 1
	manager.g13_compute_jobs[0].quarantined = false
	manager.ring_full = true
	service_file_work()
	assert manager.published.len == 0 && pending_count == 1
	manager.ring_full = false
	append_file = file
	manager.on_publish = append_during_poll
	service_file_work()
	assert pending_count == 2 && voidptr(pending_head) == first && pending_head.next != unsafe { nil }
	assert manager.published == [u32(12)]
	manager.finish_compute(0)
	service_file_work()
	assert manager.published == [u32(12), 12]
	manager.finish_compute(0)
	service_file_work()
	append_file = unsafe { nil }
	assert_drained(file)
}

fn check_shutdown_and_immediate_retirement() {
	gpu.reset()
	mut file := new_file()
	mut manager := gpu.get_global_manager() or { panic('manager') }
	out := output()
	assert submit(mut file, 1, true, unsafe { nil }, out, false) == 0
	service_file_work()
	manager.stop()
	service_file_work()
	assert syncobj.get_error(fence(out)) == -19
	assert_drained(file)
	// A permanently unsignaled dependency cannot strand accepted work after stop.
	gpu.reset()
	manager = gpu.get_global_manager() or { panic('manager') }
	input := output()
	syncobj.replace_fence(input, syncobj.new_fence(1, 1))
	blocked_output := output()
	assert submit(mut file, 1, true, input, blocked_output, false) == 0
	service_file_work()
	assert manager.published.len == 0
	manager.stop()
	service_file_work()
	assert syncobj.get_error(fence(blocked_output)) == -19
	assert_drained(file)
	gpu.reset()
	manager = gpu.get_global_manager() or { panic('manager') }
	manager.immediate_complete = true
	for _ in 0 .. 200 {
		assert submit(mut file, 1, true, unsafe { nil }, unsafe { nil }, false) == 0
		for _ in 0 .. 3 { service_file_work() }
		assert_drained(file)
	}
}

fn check_mapping_admission() {
	gpu.reset()
	mut file := new_file()
	mut manager := gpu.get_global_manager() or { panic('manager') }
	input := output()
	old := syncobj.new_fence(1, 1)
	syncobj.replace_fence(input, old)
	out := output()
	previous := syncobj.new_fence(1, 2)
	syncobj.replace_fence(out, previous)
	file.mapping_retry_blocked = true
	assert submit(mut file, 1, true, input, out, false) == -5
	assert voidptr(fence(out)) == voidptr(previous) && !syncobj.is_signaled(previous)
	assert voidptr(fence(input)) == voidptr(old) && !syncobj.is_signaled(old)
	assert manager.published.len == 0
	assert_drained(file)
	file.mapping_retry_blocked = false
	assert submit(mut file, 1, true, input, out, false) == 0
	syncobj.signal(old)
	service_file_work()
	manager.finish_compute(0)
	manager.finish_render(0)
	service_file_work()
	assert syncobj.is_signaled(fence(out))
	assert_drained(file)
}

pub fn run_checks() {
	check_missing_syncobj_submission_failures()
	check_mapping_admission()
	check_queued_ioctl_backlog()
	check_batch_capacity()
	check_dependencies_and_fifo()
	check_pair_and_forged_fence()
	check_failures()
	check_append_and_backpressure()
	check_shutdown_and_immediate_retirement()
	check_batches()
	check_overlap()
	check_firmware_dependencies()
	check_submission_pipelining()
	check_initial_submission_events()
	check_input_sync_errors()
	check_queue_fence_elision()
	syncobj.check_queue_context_allocator()
	println('AGX async: ioctl staging, independent queues/FIFO, compute→render phases, forged fences, failure cleanup, enqueue/shutdown races, backpressure and 200 immediate-retirement cycles passed')
}
