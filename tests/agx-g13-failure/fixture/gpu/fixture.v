@[has_globals]
module gpu

import gpu.agx.channel
import gpu.agx.fw
import gpu.agx.hw
import gpu.agx.alloc
import katomic
import klock

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
}

fn (buffer &SharedBuffer) cpu_address() voidptr { return voidptr(buffer.phys) }

struct G13ChannelAllocations {
mut:
	fw_status SharedBuffer
}

struct FaultInfo {
	read        bool
	address     u64
	unit_code   u32
	vm_slot     u32
	reason_code u32
}

struct Resources {}

fn (_ &Resources) get_g13_fault_info() ?FaultInfo { return none }

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
}

struct G13Subqueue {
mut:
	state  SharedBuffer
	ring   SharedBuffer
	info   SharedBuffer
	is_new bool = true
	lock   klock.Lock
}

struct G13QueueResources {
mut:
	released     bool
	priority     u32
	channel_mask u32 = 7
	subqueues    [3]G13Subqueue
}

struct Context {
	active bool = true
}

struct G13RenderJobResources {
mut:
	queue               &G13QueueResources = unsafe { nil }
	context             &Context           = unsafe { nil }
	barrier             SharedBuffer
	fragment            SharedBuffer
	init_buffer         SharedBuffer
	vertex              SharedBuffer
	vertex_event_slot   u32
	fragment_event_slot u32
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
	check_publishers()
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
		}
		before := katomic.barriers()
		published := mgr.publish_g13_render_job_locked(mut job)
		if broken == -1 {
			assert published && mgr.rings == 2 && katomic.barriers() == before + 2
			assert vertex_ring[0] == 33 && vertex_ring[1] == 44
			assert fragment_ring[0] == 11 && fragment_ring[1] == 22
			assert vertex_outer.write_ptr == 1 && fragment_outer.write_ptr == 1
		} else {
			assert !published && mgr.state == .error && mgr.rings == 0
			assert katomic.barriers() == before
			assert vertex_ring == [1280]u64{} && fragment_ring == [1280]u64{}
			assert vertex_messages[0].work_queue_addr == 0 && fragment_messages[0].work_queue_addr == 0
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
		published := mgr.submit_g13_queue_commands(&resources, 2, [alloc.g13_private_start + 0x4000], 0)
		if broken == -1 {
			assert published && mgr.rings == 1 && katomic.barriers() == before + 2
			assert ring[0] == alloc.g13_private_start + 0x4000
			assert outer.write_ptr == 1 && state.cpu_wptr == 1
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
