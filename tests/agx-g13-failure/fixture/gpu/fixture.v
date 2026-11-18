@[has_globals]
module gpu

import gpu.agx.channel
import gpu.agx.fw
import gpu.agx.hw
import gpu.agx.alloc
import gpu.agx.event
import katomic
import klock

struct G13InitialEvent {}

#include <stdio.h>
#define kprintf printf

fn C.kprintf(format &char, ...) i32

const msg_halt = u64(0x85) << 48

enum GpuState {
	running
	error
	stopped
}

struct GpuChannels {
mut:
	device_ctrl channel.TxChannel
	event       channel.RxChannel
	fw_log      channel.RxChannel
	fw_ctrl     channel.TxChannel
	ktrace      channel.RxChannel
	stats       channel.RxChannel
	pipes       [12]channel.TxChannel
}

struct SharedBuffer {
mut:
	phys u64
	va   u64
	size u64
}

fn (buffer &SharedBuffer) cpu_address() voidptr { return voidptr(buffer.phys) }

struct G13ChannelAllocations {
mut:
	fw_status SharedBuffer
	globals SharedBuffer
}

struct FaultInfo {
	read        bool
	address     u64
	unit_code   u32
	vm_slot     u32
	reason_code u32
	sideband u8
	level u8
	unknown_5 u8
}

struct Resources {
mut:
	fault_valid bool
	fault FaultInfo
}

fn (res &Resources) get_g13_fault_info() ?FaultInfo {
	if res.fault_valid { return res.fault }
	return none
}

struct GpuManager {
mut:
	state          GpuState = .running
	hw_config      hw.HwConfig
	channels       GpuChannels
	g13_channels   &G13ChannelAllocations = unsafe { nil }
	res            Resources
	lock           klock.Lock
	firmware_roles u32 = 1
	grows          int
	polls          int
	trace          []string
	rings          int
	g13_compute_jobs []&G13ComputeJobResources
	g13_render_jobs []&G13RenderJobResources
	g13_queues []&G13QueueResources
	auto_ack bool
	tvb_target u32
	tvb_calls u32
	tvb_grow_fails bool
	file_reaper fn () = unsafe { nil }
}

__global maintenance_owner &GpuManager = unsafe { nil }
__global maintenance_calls = 0
__global maintenance_stopped = false

fn maintain_files() {
	// The callback can take the manager lock only if dispatch released it.
	maintenance_owner.lock.acquire()
	maintenance_calls++
	maintenance_stopped = maintenance_owner.state == .stopped
	maintenance_owner.lock.release()
}

struct G13Subqueue {
mut:
	events event.WorkQueueEvents
	state  SharedBuffer
	ring   SharedBuffer
	info   SharedBuffer
	is_new bool = true
	command_sequence u64
	retired_sequence u64
	last_command_slot u32
	lock   klock.Lock
}

struct G13QueueResources {
mut:
	file_references u64
	mappings_published bool
	released     bool
	quarantined bool
	priority     u32
	channel_mask u32 = 7
	subqueues    [3]G13Subqueue
	render_buffer G13RenderBufferResources
}

// The production queue-release guard runs before this disposal service. Tests
// drop every file reference after completion while backing is quarantined.
fn (mut manager GpuManager) completion_test_free_queue(mut queue G13QueueResources, _ bool) bool {
 queue.released = true
 return true
}

struct Context {
	active bool = true
	id u32
}

struct G13RenderBufferResources {
mut:
	initialized bool = true
	stats SharedBuffer
	blocks []u8
	active_scenes u32
	needs_bind bool = true
	bound_blocks u32
}

// Allocation is the injected service here; the production feedback policy
// must request the correct target and reset statistics before calling it.
fn (mut mgr GpuManager) ensure_g13_tvb_blocks(mut buffer G13RenderBufferResources,
	minimum u32, firmware_active bool) bool {
	assert firmware_active == (buffer.active_scenes != 0)
	assert unsafe { &fw.G13BufferStats(buffer.stats.cpu_address()) }.reset == 1
	mgr.tvb_calls++
	mgr.tvb_target = minimum
	if mgr.tvb_grow_fails { return false }
	buffer.blocks = []u8{len: int(minimum)}
	return true
}

struct G13RenderJobResources {
mut:
	vm_slot             u32
	queue               &G13QueueResources = unsafe { nil }
	context             &Context           = unsafe { nil }
	barrier             SharedBuffer
	fragment            SharedBuffer
	init_buffer         SharedBuffer
	explicit_barriers   G13CommandBarriers
	vertex              SharedBuffer
	vertex_event_slot   u32
	fragment_event_slot u32
	vertex_ring_slot u32
	fragment_ring_slot u32
	vertex_retirement_sequence u64
	fragment_retirement_sequence u64
	retirement_published bool
	vertex_retirement_published bool
	fragment_retirement_published bool
	retirement_failed bool
	quarantined bool
	error G13JobError
	submitted bool
	released bool
	vertex_stamp_value u32
	fragment_stamp_value u32
	tvb_size_bytes u64
	pending_counted bool
	completion_result RetirementTestResult
	completion_result_ready bool
	completion fn (&G13RenderJobResources, bool, voidptr) = unsafe { nil }
	stage_completion fn (u32, voidptr) = unsafe { nil }
	completion_data voidptr
}

struct G13ComputeJobResources {
mut:
	vm_slot u32
	command SharedBuffer
	timestamps SharedBuffer
	microsequence SharedBuffer
	explicit_barriers G13CommandBarriers
	context &Context = unsafe { nil }
	queue &G13QueueResources = unsafe { nil }
	event_slot u32
	stamp_value u32
	submitted bool
	quarantined bool
	pending_counted bool
	retirement_sequence u64
	ring_slot u32
	retirement_published bool
	released bool
	error G13JobError
	completion fn (&G13ComputeJobResources, bool, voidptr) = unsafe { nil }
	completion_data voidptr
	completion_result fw.G13JobTimestamps
	completion_ready bool
}

fn (mut mgr GpuManager) ring_device_control() bool {
	mgr.rings++
	if mgr.auto_ack {
		unsafe {
			mut read := &u32(mgr.channels.device_ctrl.state_phys)
			write := &u32(mgr.channels.device_ctrl.state_phys + 0x20)
			*read = *write
		}
	}
	return true
}

fn pipe_index(priority u32, kind u32) u32 { return priority * 3 + kind }

fn (mut mgr GpuManager) ring_pipe(_ u32, _ u32) bool {
	mgr.rings++
	return true
}

fn (mut mgr GpuManager) handle_g13_grow_tvb(_ &fw.FwGrowTVBEvent) { mgr.grows++ }

fn (mut mgr GpuManager) poll_rtkit_messages() bool {
	mgr.polls++
	return true
}

fn (mut mgr GpuManager) drain_auxiliary_channels() {
	mut bytes := [256]u8{}
	for i := u32(0); i < 6; i++ {
		for mgr.channels.fw_log.dequeue_subchannel(&bytes[0], i) {
		}
	}
	for mgr.channels.ktrace.dequeue(&bytes[0]) {
	}
	for mgr.channels.stats.dequeue(&bytes[0]) {
	}
}

fn (mut mgr GpuManager) reap_g13_render_jobs() { mgr.trace << 'success' }

fn (mut mgr GpuManager) reap_g13_compute_jobs() { mgr.state = .stopped }

fn (mut mgr GpuManager) send_fw_msg(message u64, data u64) bool {
	assert message == msg_halt && data == 0
	mgr.trace << 'halt'
	return true
}

fn (mut mgr GpuManager) stop_firmware_cpus(roles u32) {
	assert roles == 1
	mgr.trace << 'stop'
}

fn (mut mgr GpuManager) release_rtkit_buffers() { mgr.trace << 'rtkit' }

fn (mut mgr GpuManager) release_all_g13_render_jobs() { mgr.trace << 'fail-render' }

fn (mut mgr GpuManager) release_all_g13_compute_jobs() { mgr.trace << 'fail-compute' }

fn (mut mgr GpuManager) release_all_g13_queue_resources() { mgr.trace << 'queues' }

fn (mut mgr GpuManager) release_g13_channels() { mgr.trace << 'channels' }

fn (mut mgr GpuManager) release_g13_event_resources_locked() { mgr.trace << 'events' }

fn (mut mgr GpuManager) release_all_g17_queue_resources() {}

fn (mut mgr GpuManager) release_g17_firmware_graph() {}

fn assert_failed(mgr &GpuManager) {
	assert mgr.state == .stopped
	assert mgr.trace == ['halt', 'stop', 'rtkit', 'fail-render', 'fail-compute', 'queues', 'channels',
		'events']
}

pub fn run_checks() {
	mut maintenance := GpuManager{}
	maintenance_owner = &maintenance
	maintenance.set_file_reaper(maintain_files)
	maintenance.reap_file_resources()
	assert maintenance_calls == 1
	mut stopped_maintenance := GpuManager{state: .error}
	maintenance_owner = &stopped_maintenance
	stopped_maintenance.set_file_reaper(maintain_files)
	event_worker(mut stopped_maintenance)
	assert maintenance_calls == 2 && maintenance_stopped
	check_publishers()
	check_barrier_publishers()
	check_retirement()
	check_render_retirement()
	check_compute_retirement()
	check_recovery()
	check_submit_idle_delay()
	check_tvb_feedback()
	assert sizeof(fw.G13FwStatus) == 0x80
	assert __offsetof(fw.G13FwStatus, halt_count) == 0x10
	assert __offsetof(fw.G13FwStatus, halted) == 0x20
	assert __offsetof(fw.G13FwStatus, resume) == 0x30
	for abi in [hw.FirmwareAbi.v12_3, .v13_5_partial] {
		for tag in [u32(0), 4, 8] {
			mut header := channel.RingHeader{ write_ptr: 2 }
			mut ring := [4]fw.FwEventMsg{}
			ring[0].tag = tag
			ring[1].tag = fw.fw_event_grow_tvb
			mut mgr := GpuManager{ hw_config: hw.HwConfig{ gpu_gen: .g13, firmware_abi: abi } }
			mgr.channels.event = channel.new_rx_channel('event', 1, u64(&header), 1, u64(&ring), 4, 0x38)
			event_worker(mut mgr)
			assert_failed(&mgr)
			assert mgr.grows == 0
			assert header.read_ptr == 1, 'stop consuming events after a fatal event'
		}
		mut status := fw.G13FwStatus{ halt_count: 3, halted: 1 }
		mut graph := G13ChannelAllocations{ fw_status: SharedBuffer{ phys: u64(&status) } }
		mut halted := GpuManager{
			hw_config:    hw.HwConfig{ gpu_gen: .g13, firmware_abi: abi }
			g13_channels: &graph
		}
		event_worker(mut halted)
		assert_failed(&halted)
		assert halted.polls == 0, 'halt without an event must fail before more firmware work'
		assert status.halted == 1 && status.resume == 0, 'unrepaired queues must never be resumed'
	}
	// A malformed event ring produces no event; the sticky error must still
	// reach shutdown instead of being mistaken for an empty ring.
	mut broken_state := channel.RingHeader{ read_ptr: 4, write_ptr: 4 }
	mut broken_ring := [4]fw.FwEventMsg{}
	mut broken := GpuManager{ hw_config: hw.HwConfig{ gpu_gen: .g13 } }
	broken.channels.event = channel.new_rx_channel('event', 1, u64(&broken_state), 1, u64(&broken_ring), 4, 0x38)
	event_worker(mut broken)
	assert_failed(&broken)

	mut log_state := [6]channel.RingHeader{}
	mut log_ring := [24]fw.FwLogMsg{}
	log_state[5].write_ptr = 0xffff_ffff
	mut bad_log := GpuManager{ hw_config: hw.HwConfig{ gpu_gen: .g13 } }
	bad_log.channels.fw_log = channel.new_rx_channel_with_subchannels('log', 1, u64(&log_state), 1, u64(&log_ring), 4, 0xd8, 6)
	event_worker(mut bad_log)
	assert_failed(&bad_log)

	mut tx_state := channel.RingHeader{ read_ptr: 4 }
	mut tx_ring := [4]u64{}
	mut bad_pipe := GpuManager{ hw_config: hw.HwConfig{ gpu_gen: .g13 } }
	bad_pipe.channels.pipes[11] = channel.new_tx_channel('pipe', 1, u64(&tx_state), 1, u64(&tx_ring), 4, 8)
	value := u64(123)
	assert !bad_pipe.channels.pipes[11].enqueue(&value)
	event_worker(mut bad_pipe)
	assert_failed(&bad_pipe)
	assert bad_pipe.polls == 0

	// Normal traffic must still reach successful job reaping.
	mut normal_state := channel.RingHeader{ write_ptr: 2 }
	mut normal_ring := [4]fw.FwEventMsg{}
	normal_ring[0].tag = fw.fw_event_flag
	normal_ring[1].tag = fw.fw_event_grow_tvb
	mut normal := GpuManager{ hw_config: hw.HwConfig{ gpu_gen: .g13 } }
	normal.channels.event = channel.new_rx_channel('event', 1, u64(&normal_state), 1, u64(&normal_ring), 4, 0x38)
	event_worker(mut normal)
	assert normal.trace == ['success'] && normal.grows == 1
}

fn check_submit_idle_delay() {
	// Offsets in the two Globals layouts. Compare the whole buffer so a write
	// to a neighbouring field or to the older ABI's location cannot pass.
	for index, abi in [hw.FirmwareAbi.v12_3, .v13_5_partial, .g17_26_5_partial]! {
		offset := [u64(0x11030), 0x1119c, 0]![index]
		for mode in 0 .. 7 {
			mut words := []u32{len: 0x12400 / 4, init: u32(0xa55a51f0)}
			defer { unsafe { words.free() } }
			size := if mode == 3 { offset + 3 } else { u64(words.len * 4) }
			mut graph := G13ChannelAllocations{
				globals: SharedBuffer{phys: if mode == 2 { u64(0) } else { u64(words.data) }, size: size}
			}
			mut mgr := GpuManager{
				hw_config: hw.HwConfig{firmware_abi: abi, gpu_gen: if mode == 6 { .g17 } else { .g13 }}
				g13_channels: if mode == 1 { unsafe { nil } } else { unsafe { &graph } }
				state: match mode { 4 { .stopped } 5 { .error } else { .running } }
			}
			mgr.refresh_g13_submit_globals()
			mgr.lock.acquire()
			mgr.lock.release()
			for word_index, word in words {
				expected := if mode == 0 && index != 2 && u64(word_index * 4) == offset { u32(2) } else { u32(0xa55a51f0) }
				assert word == expected
			}
		}
	}
	println('G13 submit idle delay: 21 whole-Globals checks cover both ABIs, absent and short backing, stopped/error state and unrelated GPUs')
}

fn check_tvb_feedback() {
	// Twenty pages fit in ten blocks with 2x headroom; the next page
	// requires growth, rounded up to sixteen blocks (3x headroom).
	for used, target in {u32(0): u32(0), 20: 0, 21: 16, 43: 33, ~u32(0): g13_tvb_max_blocks_nomemless} {
		mut stats := fw.G13BufferStats{max_pages: used}
		mut buffer := G13RenderBufferResources{
			stats: SharedBuffer{phys: u64(&stats), size: sizeof(fw.G13BufferStats)}
			blocks: []u8{len: 10}
		}
		mut mgr := GpuManager{}
		assert mgr.auto_grow_g13_tvb_locked(mut buffer)
		assert stats.reset == 1 && stats.max_pages == used
		assert mgr.tvb_calls == if target == 0 { u32(0) } else { u32(1) }
		assert mgr.tvb_target == target
		assert buffer.blocks.len == if target == 0 { 10 } else { int(target) }
	}
	mut stats := fw.G13BufferStats{max_pages: ~u32(0)}
	mut capped := G13RenderBufferResources{
		stats: SharedBuffer{phys: u64(&stats), size: sizeof(fw.G13BufferStats)}
		blocks: []u8{len: int(g13_tvb_max_blocks_nomemless)}
	}
	mut mgr := GpuManager{}
	assert mgr.auto_grow_g13_tvb_locked(mut capped) && mgr.tvb_calls == 0
	mut empty := G13RenderBufferResources{}
	assert !mgr.auto_grow_g13_tvb_locked(mut empty) && mgr.tvb_calls == 0
	mut failing := G13RenderBufferResources{
		stats: SharedBuffer{phys: u64(&stats), size: sizeof(fw.G13BufferStats)}
		blocks: []u8{len: 10}
	}
	mgr.tvb_grow_fails = true
	assert !mgr.auto_grow_g13_tvb_locked(mut failing)
	assert mgr.tvb_calls == 1 && failing.blocks.len == 10
	mut active_stats := fw.G13BufferStats{max_pages: 43}
	mut active := G13RenderBufferResources{
		stats: SharedBuffer{phys: u64(&active_stats), size: sizeof(fw.G13BufferStats)}
		blocks: []u8{len: 10}
		active_scenes: 2
	}
	mgr.tvb_grow_fails = false
	assert mgr.auto_grow_g13_tvb_locked(mut active)
	println('G13 TVB feedback: threshold, rounding, reset, cap and allocation failure passed')
}

fn check_recovery() {
	for abi in [hw.FirmwareAbi.v12_3, .v13_5_partial] {
		mut globals := fw.G13Globals{}
		mut status := fw.G13FwStatus{halted: 1}
		mut graph := G13ChannelAllocations{
			globals: SharedBuffer{phys: u64(&globals), size: sizeof(fw.G13Globals)}
			fw_status: SharedBuffer{phys: u64(&status)}
		}
		mut vm := Context{id: 9}
		mut culprit := G13ComputeJobResources{event_slot: 3, stamp_value: 0x100, submitted: true,
			context: &vm, vm_slot: 8}
		mut other := G13ComputeJobResources{event_slot: 4, stamp_value: 0x100, submitted: true}
		mut already_done := G13ComputeJobResources{event_slot: 5, stamp_value: 0x100, submitted: true}
		mut render := G13RenderJobResources{vertex_event_slot: 6, fragment_event_slot: 7,
			vertex_stamp_value: 0x100, fragment_stamp_value: 0x100, submitted: true,
			context: &vm, vm_slot: 8}
		mut mgr := GpuManager{
			hw_config: hw.HwConfig{gpu_gen: .g13, firmware_abi: abi}
			g13_channels: &graph
			g13_compute_jobs: [&culprit, &other, &already_done]
			g13_render_jobs: [&render]
		}
		offset := fw.g13_globals_pending_stamps_offset(abi) or { panic('pending stamps') }
		mut pending := unsafe { &fw.G13PendingStamp(u64(&globals) + offset) }
		shift := if abi == .v12_3 { u32(3) } else { u32(4) }
		for index := u32(0); index < 5; index++ {
			unsafe { pending[index] = fw.G13PendingStamp{info: ((index + 3) << shift) | 1, wait_value: 0x100} }
		}
		event.set_completed(5, true)
		assert mgr.recover_g13_fault(3, 3)
		assert status.halted == 0 && status.resume == 1 && mgr.state == .running
		assert culprit.error.status == 3 && other.error.status == 5
		assert already_done.error.status == 0 && render.error.status == 5
		// A later fault on a shared workqueue stamp must preserve earlier
		// completed work, even while its newer job is still pending.
		mut prior := G13ComputeJobResources{event_slot: 3, stamp_value: 0x100, submitted: true}
		mut later := G13ComputeJobResources{event_slot: 3, stamp_value: 0x200, submitted: true}
		mgr.g13_compute_jobs << &prior
		mgr.g13_compute_jobs << &later
		event.set_value(3, 0x100)
		mgr.mark_g13_slot_error_locked(3, 0x200, G13JobError{status: 3})
		assert prior.error.status == 0 && later.error.status == 3
		event.set_completed(3, false)
		assert mgr.trace.len == 0, 'recovery must retain all command backing'
		for index := u32(0); index < 5; index++ {
			assert unsafe { pending[index].info == 0 && pending[index].wait_value == 0 }
		}
		event.set_completed(5, false)
		// Fault details survive resume and a dependency killed on the other stage.
		mgr.res.fault_valid = true
		mgr.res.fault = FaultInfo{address: 0x123400, unit_code: 7, reason_code: 2,
			sideband: 3, level: 1, unknown_5: 2, read: true, vm_slot: 8}
		unsafe {
			pending[0] = fw.G13PendingStamp{info: (u32(6) << shift) | 1, wait_value: 0x100}
			pending[1] = fw.G13PendingStamp{info: (u32(7) << shift) | 1, wait_value: 0x100}
		}
		status.halted = 1
		status.resume = 0
		assert mgr.recover_g13_fault(6, 3)
		assert render.error.status == 4 && render.error.address == 0x123400
		assert render.error.fault_type == 2 && render.error.is_read == 1
		assert render.error.fence_error() == -5
		assert G13JobError{status: 3}.fence_error() == -110
		assert G13JobError{status: 5}.fence_error() == -125
		assert G13JobError{status: 6}.fence_error() == -19
		// A fault at the software VM's number belongs to another ASID.
		render.error = G13JobError{}
		mgr.mark_g13_slot_error_locked(3, 0x100, G13JobError{status: 4, vm_slot: vm.id})
		mgr.mark_g13_slot_error_locked(6, 0x100, G13JobError{status: 4, vm_slot: vm.id})
		assert culprit.error.status == 5
		assert render.error.status == 5
		mgr.mark_g13_slot_error_locked(3, 0x100, mgr.g13_fault_error(3))
		assert culprit.error.status == 4 && culprit.error.address == 0x123400
		// The worker's pre-drain health check must let the queued error own
		// recovery instead of stopping the ASC before handle_event can run.
		mut error_header := channel.RingHeader{write_ptr: 1}
		mut error_ring := [4]fw.FwEventMsg{}
		error_ring[0].tag = fw.fw_event_fault
		mgr.channels.event = channel.new_rx_channel('event', 1, u64(&error_header), 1, u64(&error_ring), 4, 0x38)
		status.halted = 1
		status.resume = 0
		unsafe { pending[255] = fw.G13PendingStamp{info: (u32(3) << shift) | 1, wait_value: 0x100} }
		assert mgr.check_g13_firmware_health()
		mgr.handle_event()
		assert mgr.state == .running && status.resume == 1 && status.halted == 0
		assert unsafe { pending[255].info == 0 && pending[255].wait_value == 0 }
		// An unacknowledged halt may not be resumed; truncated Globals may
		// not be read at all. Callers fall back to stop-before-free shutdown.
		status.resume = 0
		assert !mgr.recover_g13_fault(-1, 2)
		assert status.resume == 0
		graph.globals.size = offset
		status.halted = 1
		assert !mgr.recover_g13_fault(-1, 2)
		assert status.halted == 1 && status.resume == 0
	}
	mut header := channel.RingHeader{}
	mut messages := [4]fw.FwRecoverChannel{}
	mut resources := G13QueueResources{}
	resources.subqueues[2].info.va = 0x123000
	mut job := G13ComputeJobResources{queue: &resources, event_slot: 8, stamp_value: 0x100, submitted: true}
	mut mgr := GpuManager{g13_compute_jobs: [&job], auto_ack: true}
	mgr.channels.device_ctrl = channel.new_tx_channel('dc', 1, u64(&header), 1, u64(&messages), 4, 0x30)
	assert mgr.recover_g13_channel(2, 8, 0x100, 1)
	assert job.error.status == 7 && job.error.extra == 1
	assert messages[0].tag == 0xe && messages[0].pipe_type == 2
	assert messages[0].work_queue == 0x123000 && messages[0].event_value == 0x100
	assert header.read_ptr == header.write_ptr && mgr.trace.len == 0
	assert !mgr.recover_g13_channel(3, 8, 0x100, 1)
	assert header.write_ptr == 1
	assert sizeof(fw.FwRecoverChannel) == 0x30
	println('G13 recovery: pending stamps, fault isolation, halt/resume, channel ACK and error codes passed')
}

fn check_retirement() {
	mut state := fw.G13WorkQueueRingState{ cpu_wptr: 1, gpu_doneptr: 1 }
	mut resources := G13QueueResources{}
	resources.subqueues[2] = G13Subqueue{
		state: SharedBuffer{phys: u64(&state)}
		command_sequence: 1281
	}
	mut mgr := GpuManager{ hw_config: hw.HwConfig{ gpu_gen: .g13 } }
	before := katomic.barriers()
	assert mgr.retire_g13_subqueue_locked(&resources, 2, 1281, 0)
	assert state.cpu_freeptr == 0 && katomic.barriers() == before + 1
	// Reaping an older job after wrap must not roll the free pointer back.
	assert mgr.retire_g13_subqueue_locked(&resources, 2, 1280, 1279)
	assert state.cpu_freeptr == 0 && katomic.barriers() == before + 1
	assert !mgr.retire_g13_subqueue_locked(&resources, 2, 1282, 1)
	assert mgr.state == .error
	mgr.state = .running
	resources.subqueues[2].retired_sequence = 0
	state.gpu_doneptr = 1280
	assert !mgr.retire_g13_subqueue_locked(&resources, 2, 1, 0)
	assert state.cpu_freeptr == 0 && katomic.barriers() == before + 1
	ack := fw.make_grow_tvb_ack(2, 3, 4, 0x12345678)
	assert sizeof(fw.FwGrowTVBAck) == 0x30
	assert __offsetof(fw.FwGrowTVBAck, halt_count) == 0x18
	assert ack.halt_count == 0x12345678 && ack.subpipe == 0
}

fn check_publishers() {
	for broken in -1 .. 8 {
		mut vertex_outer := channel.RingHeader{}
		mut fragment_outer := channel.RingHeader{}
		mut vertex_messages := [4]fw.FwRunWorkQueueMsg{}
		mut fragment_messages := [4]fw.FwRunWorkQueueMsg{}
		mut vertex_state := fw.G13WorkQueueRingState{}
		mut fragment_state := fw.G13WorkQueueRingState{}
		mut vertex_ring := [1280]u64{}
		mut fragment_ring := [1280]u64{}
		mut resources := G13QueueResources{}
		resources.subqueues[0] = G13Subqueue{
			state: SharedBuffer{ phys: u64(&vertex_state) }
			ring:  SharedBuffer{ phys: unsafe { u64(&vertex_ring) } }
			info:  SharedBuffer{ va: 0x1000 }
		}
		resources.subqueues[1] = G13Subqueue{
			state: SharedBuffer{ phys: u64(&fragment_state) }
			ring:  SharedBuffer{ phys: unsafe { u64(&fragment_ring) } }
			info:  SharedBuffer{ va: 0x2000 }
		}
		mut graph := G13ChannelAllocations{}
		mut context := Context{}
		mut mgr := GpuManager{ hw_config: hw.HwConfig{ gpu_gen: .g13 }, g13_channels: &graph }
		mgr.channels.pipes[0] = channel.new_tx_channel('vertex', 1, u64(&vertex_outer), 1, u64(&vertex_messages), 4, 0x30)
		mgr.channels.pipes[1] = channel.new_tx_channel('fragment', 1, u64(&fragment_outer), 1, u64(&fragment_messages), 4, 0x30)
		match broken {
			0 { vertex_outer.read_ptr = 4 }
			1 { vertex_outer.write_ptr = ~u32(0) }
			2 { fragment_outer.read_ptr = 4 }
			3 { fragment_outer.write_ptr = ~u32(0) }
			4 { vertex_state.cpu_wptr = 1280 }
			5 { vertex_state.gpu_doneptr = ~u32(0) }
			6 { fragment_state.cpu_wptr = 1280 }
			7 { fragment_state.gpu_doneptr = ~u32(0) }
			else {}
		}
		mut job := G13RenderJobResources{
			queue:       &resources
			context:     &context
			barrier:     SharedBuffer{ va: 11 }
			fragment:    SharedBuffer{ va: 22 }
			init_buffer: SharedBuffer{ va: 33 }
			vertex:      SharedBuffer{ va: 44 }
			tvb_size_bytes: 8 * fw.g13_tvb_block_size
		}
		before := katomic.barriers()
		published := mgr.publish_g13_render_job_locked(mut job)
		if broken == -1 {
			assert published && mgr.rings == 2 && katomic.barriers() == before + 2
			assert vertex_ring[0] == 33 && vertex_ring[1] == 44
			assert fragment_ring[0] == 11 && fragment_ring[1] == 22
			assert vertex_outer.write_ptr == 1 && fragment_outer.write_ptr == 1
			assert job.vertex_ring_slot == 1 && job.fragment_ring_slot == 1
			assert job.vertex_retirement_sequence == 2 && job.fragment_retirement_sequence == 2
			assert resources.render_buffer.bound_blocks == 8 && !resources.render_buffer.needs_bind
			job.vertex.va = 55
			job.init_buffer.va = 66
			assert mgr.publish_g13_render_job_locked(mut job)
			assert vertex_ring[2] == 55 && vertex_ring[3] == 0, 'unchanged TVB must not be rebound between overlapping scenes'
			assert vertex_state.cpu_wptr == 3 && job.vertex_retirement_sequence == 3
			assert fragment_state.cpu_wptr == 4 && job.fragment_retirement_sequence == 4
			job.tvb_size_bytes = 16 * fw.g13_tvb_block_size
			job.vertex.va = 88
			job.init_buffer.va = 77
			assert mgr.publish_g13_render_job_locked(mut job)
			assert vertex_ring[3] == 77 && vertex_ring[4] == 88
			assert resources.render_buffer.bound_blocks == 16 && vertex_state.cpu_wptr == 5
			assert job.vertex_retirement_sequence == 5 && job.fragment_retirement_sequence == 6
		} else {
			assert !published && mgr.state == .error && mgr.rings == 0
			assert katomic.barriers() == before
			assert vertex_ring == [1280]u64{} && fragment_ring == [1280]u64{}
			assert vertex_messages[0].work_queue_addr == 0 && fragment_messages[0].work_queue_addr == 0
			assert resources.render_buffer.needs_bind && resources.render_buffer.bound_blocks == 0
		}
		// Every failure path must have released the locks it reserved.
		mgr.channels.pipes[0].lock.acquire()
		mgr.channels.pipes[0].lock.release()
		mgr.channels.pipes[1].lock.acquire()
		mgr.channels.pipes[1].lock.release()
		resources.subqueues[0].lock.acquire()
		resources.subqueues[0].lock.release()
		resources.subqueues[1].lock.acquire()
		resources.subqueues[1].lock.release()
	}
	for broken in -1 .. 4 {
		mut outer := channel.RingHeader{}
		mut messages := [4]fw.FwRunWorkQueueMsg{}
		mut state := fw.G13WorkQueueRingState{}
		mut ring := [1280]u64{}
		mut resources := G13QueueResources{}
		resources.subqueues[2] = G13Subqueue{
			state: SharedBuffer{ phys: u64(&state) }
			ring:  SharedBuffer{ phys: unsafe { u64(&ring) } }
			info:  SharedBuffer{ va: 0x1000 }
		}
		mut mgr := GpuManager{ hw_config: hw.HwConfig{ gpu_gen: .g13 } }
		mgr.channels.pipes[2] = channel.new_tx_channel('compute', 1, u64(&outer), 1, u64(&messages), 4, 0x30)
		match broken {
			0 { outer.read_ptr = 4 }
			1 { outer.write_ptr = ~u32(0) }
			2 { state.cpu_wptr = 1280 }
			3 { state.gpu_doneptr = ~u32(0) }
			else {}
		}
		before := katomic.barriers()
		published := mgr.submit_g13_queue_commands(&resources, 2, [alloc.g13_private_start + 0x4000, u64(0), 0]!, 1, 0)
		if broken == -1 {
			assert published && mgr.rings == 1 && katomic.barriers() == before + 2
			assert ring[0] == alloc.g13_private_start + 0x4000
			assert outer.write_ptr == 1 && state.cpu_wptr == 1
			assert resources.subqueues[2].command_sequence == 1
			assert resources.subqueues[2].last_command_slot == 0
		} else {
			assert !published && mgr.state == .error && mgr.rings == 0
			assert ring == [1280]u64{} && messages[0].work_queue_addr == 0
			assert katomic.barriers() == before
		}
		mgr.channels.pipes[2].lock.acquire()
		mgr.channels.pipes[2].lock.release()
		resources.subqueues[2].lock.acquire()
		resources.subqueues[2].lock.release()
	}
}
