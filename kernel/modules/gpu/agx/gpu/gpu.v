@[has_globals]
module gpu

// GPU Manager -- top-level GPU control
// Handles RTKit endpoints, firmware initialization, ring buffer setup,
// and work submission coordination
// Translates gpu.rs from the Asahi Linux GPU driver

import apple.rtkit
import apple.mailbox
import gpu.agx.regs
import gpu.agx.hw
import gpu.agx.mmu
import gpu.agx.pgtable
import gpu.agx.channel
import gpu.agx.alloc
import gpu.agx.fw
import gpu.agx.queue
import gpu.agx.event
import memory
import klock
import sched

// RTKit endpoint IDs for GPU firmware
pub const ep_firmware = u32(0x20)
pub const ep_doorbell = u32(0x21)

// GPU endpoint messages occupy bits 55:48; the low 44 bits carry an IOVA.
pub const msg_init = u64(0x81) << 48
pub const msg_tx_doorbell = u64(0x83) << 48
pub const msg_fwctl = u64(0x84) << 48
pub const msg_halt = u64(0x85) << 48
const msg_address_mask = (u64(1) << 44) - 1

// G13 v12.3 doorbell selectors. Pipe doorbells use the pipe type in bits 1:0
// and the priority index in bits 3:2; firmware-global controls occupy 0x10+.
pub const doorbell_kick_firmware = u32(0x10)
pub const doorbell_device_control = u32(0x11)

const g13_channel_allocation_count = 18
const g13_device_control_index = 0
const g13_fw_control_index = 1
const g13_event_index = 2
const g13_fw_log_index = 3
const g13_ktrace_index = 4
const g13_stats_index = 5
const g13_pipe_base_index = 6

// GPU states
pub enum GpuState {
	idle     = 0
	starting = 1
	running  = 2
	error    = 3
	stopped  = 4
}

// All GPU firmware communication channels
pub struct GpuChannels {
pub mut:
	device_ctrl channel.TxChannel
	event       channel.RxChannel
	fw_log      channel.RxChannel
	fw_ctrl     channel.TxChannel
	ktrace      channel.RxChannel
	stats       channel.RxChannel
	pipes       [12]channel.TxChannel // 4 priorities x 3 types (vertex/fragment/compute)
}

pub struct GpuManager {
pub mut:
	res            regs.GpuResources
	hw_config      hw.HwConfig
	rtk            rtkit.RTKit
	secondary_rtk  rtkit.RTKit
	firmware_roles u32
	channels       GpuChannels
	allocs         alloc.HeapAllocator
	initdata_va    u64
	initdata_phys  u64
	state          GpuState
	lock           klock.Lock
mut:
	g13_channels &G13ChannelAllocations = unsafe { nil }
	g17_graph    &G17FirmwareGraph = unsafe { nil }
	g17_queues   []&G17QueueResources
}

__global (
	global_gpu_mgr = unsafe { &GpuManager(nil) }
)

pub fn set_global_manager(mgr &GpuManager) {
	global_gpu_mgr = unsafe { mgr }
}

pub fn get_global_manager() ?&GpuManager {
	if global_gpu_mgr == unsafe { nil } {
		return none
	}
	return global_gpu_mgr
}

pub fn new_gpu_manager(res &regs.GpuResources, cfg &hw.HwConfig, rtk &rtkit.RTKit,
	secondary_rtk &rtkit.RTKit) ?&GpuManager {
	if res.firmware_role_count == 0 || res.firmware_role_count > 2 {
		return none
	}
	if res.firmware_role_count == 2 && secondary_rtk.mbox.base == 0 {
		return none
	}
	version, core_count := res.get_gpu_id()
	println('agx: GPU ID version=0x${version:x} cores=${core_count}')

	mut mgr := &GpuManager{
		res: unsafe { *res }
		hw_config: unsafe { *cfg }
		rtk: unsafe { *rtk }
		secondary_rtk: unsafe { *secondary_rtk }
		firmware_roles: res.firmware_role_count
		state: .idle
		allocs: alloc.new_heap('agx-shared', alloc.gpu_shared_start, alloc.gpu_shared_end)
	}

	return mgr
}

fn (mut mgr GpuManager) boot_firmware_role(role u32) bool {
	return match role {
		0 { mgr.rtk.boot() }
		1 {
			if mgr.firmware_roles == 2 {
				mgr.secondary_rtk.boot()
			} else {
				false
			}
		}
		else { false }
	}
}

fn (mut mgr GpuManager) start_firmware_endpoint(role u32, endpoint u8) bool {
	return match role {
		0 { mgr.rtk.start_endpoint(endpoint) }
		1 {
			if mgr.firmware_roles == 2 {
				mgr.secondary_rtk.start_endpoint(endpoint)
			} else {
				false
			}
		}
		else { false }
	}
}

fn (mut mgr GpuManager) send_role_message(role u32, endpoint u8, message u64) bool {
	return match role {
		0 { mgr.rtk.send_message(endpoint, message) }
		1 {
			if mgr.firmware_roles == 2 {
				mgr.secondary_rtk.send_message(endpoint, message)
			} else {
				false
			}
		}
		else { false }
	}
}

fn (mut mgr GpuManager) recv_role_message(role u32) ?mailbox.MboxMsg {
	return match role {
		0 { mgr.rtk.recv_msg() }
		1 {
			if mgr.firmware_roles == 2 {
				mgr.secondary_rtk.recv_msg()
			} else {
				none
			}
		}
		else { none }
	}
}

fn (mut mgr GpuManager) stop_firmware_cpus(count u32) {
	mut remaining := count
	for remaining > 0 {
		remaining--
		mgr.res.stop_cpu(remaining)
	}
}

struct SharedBuffer {
mut:
	va   u64
	phys u64
	size u64
}

struct G13ChannelAllocations {
mut:
	states           [g13_channel_allocation_count]SharedBuffer
	rings            [g13_channel_allocation_count]SharedBuffer
	allocated        u32
	initdata         SharedBuffer
	unknown_buffer   SharedBuffer
	runtime_pointers SharedBuffer
	globals          SharedBuffer
	fw_status        SharedBuffer
	fwlog_payload    SharedBuffer
}

@[inline]
fn pipe_index(priority u32, cmd_type u32) u32 {
	return (priority % 4) * 3 + (cmd_type % 3)
}

@[inline]
fn pipe_doorbell(priority u32, cmd_type u32) u32 {
	return (priority % 4) << 2 | (cmd_type % 3)
}

fn (mut mgr GpuManager) alloc_shared_buffer_with_protection(size u64,
	protection u64) ?SharedBuffer {
	if size == 0 || size > u64(-1) - (alloc.gpu_page_size - 1) || uat_mgr == unsafe { nil } {
		return none
	}
	aligned_size := (size + alloc.gpu_page_size - 1) & ~(alloc.gpu_page_size - 1)
	pages := aligned_size / page_size
	phys := u64(memory.pmm_alloc_aligned_fallible(pages, 4))
	if phys == 0 {
		return none
	}

	unsafe {
		C.memset(voidptr(phys + higher_half), 0, aligned_size)
	}

	va := mgr.allocs.alloc(size, alloc.gpu_page_size) or {
		memory.pmm_free(voidptr(phys), pages)
		return none
	}

	if !uat_mgr.map_kernel(va, phys, aligned_size, protection) {
		mgr.allocs.release(va)
		mgr.allocs.gc()
		memory.pmm_free(voidptr(phys), pages)
		return none
	}

	return SharedBuffer{
		va: va
		phys: phys
		size: aligned_size
	}
}

fn (mut mgr GpuManager) alloc_shared_buffer(size u64) ?SharedBuffer {
	return mgr.alloc_shared_buffer_with_protection(size, pgtable.gpu_prot_fw_gpu_shared_rw)
}

// Release a driver-owned shared allocation after its firmware consumer has
// stopped. The caller batches heap GC so a complete reverse-order unwind can
// collapse the whole virtual-address suffix in one pass.
fn (mut mgr GpuManager) free_shared_buffer(mut buffer SharedBuffer) {
	if buffer.va != 0 {
		if uat_mgr != unsafe { nil } && buffer.size != 0 {
			uat_mgr.unmap_kernel(buffer.va, buffer.size)
		}
		mgr.allocs.release(buffer.va)
	}
	if buffer.phys != 0 && buffer.size != 0 {
		memory.pmm_free(voidptr(buffer.phys), buffer.size / page_size)
	}
	buffer = SharedBuffer{}
}

fn (mut mgr GpuManager) alloc_g13_channel_pair(mut allocations G13ChannelAllocations,
	index u32, state_size u64, ring_size u64, ring_protection u64) bool {
	if index != allocations.allocated || index >= g13_channel_allocation_count {
		return false
	}
	mut state := mgr.alloc_shared_buffer(state_size) or { return false }
	ring := mgr.alloc_shared_buffer_with_protection(ring_size, ring_protection) or {
		mgr.free_shared_buffer(mut state)
		return false
	}
	allocations.states[index] = state
	allocations.rings[index] = ring
	allocations.allocated++
	return true
}

fn (mut mgr GpuManager) free_g13_channel_allocations(mut allocations G13ChannelAllocations) {
	mgr.free_shared_buffer(mut allocations.initdata)
	mgr.free_shared_buffer(mut allocations.fwlog_payload)
	mgr.free_shared_buffer(mut allocations.fw_status)
	mgr.free_shared_buffer(mut allocations.globals)
	mgr.free_shared_buffer(mut allocations.runtime_pointers)
	mgr.free_shared_buffer(mut allocations.unknown_buffer)
	mut count := allocations.allocated
	for count > 0 {
		count--
		mgr.free_shared_buffer(mut allocations.rings[count])
		mgr.free_shared_buffer(mut allocations.states[count])
	}
	mgr.allocs.gc()
}

fn (mut mgr GpuManager) release_g13_channels() {
	if mgr.g13_channels == unsafe { nil } {
		return
	}
	mgr.channels = GpuChannels{}
	mut allocations := unsafe { mgr.g13_channels }
	mgr.g13_channels = unsafe { nil }
	mgr.free_g13_channel_allocations(mut allocations)
}

fn (mut mgr GpuManager) allocate_g13_channels() ?&G13ChannelAllocations {
	mut allocations := &G13ChannelAllocations{}
	mut complete := false
	defer {
		if !complete {
			mgr.free_g13_channel_allocations(mut allocations)
		}
	}

	if !mgr.alloc_g13_channel_pair(mut allocations, g13_device_control_index, sizeof(channel.RingHeader), u64(fw.device_control_size) * sizeof(fw.FwDeviceControlMsg), pgtable.gpu_prot_fw_private_rw) {
		return none
	}
	if !mgr.alloc_g13_channel_pair(mut allocations, g13_fw_control_index, sizeof(channel.FwCtlRingHeader), u64(fw.fw_ctl_size) * sizeof(fw.FwFwCtlMsg), pgtable.gpu_prot_fw_gpu_shared_rw) {
		return none
	}
	if !mgr.alloc_g13_channel_pair(mut allocations, g13_event_index, sizeof(channel.RingHeader), u64(fw.event_size) * sizeof(fw.FwEventMsg), pgtable.gpu_prot_fw_gpu_shared_rw) {
		return none
	}
	// Firmware logging has six independent state/ring subchannels.
	if !mgr.alloc_g13_channel_pair(mut allocations, g13_fw_log_index, 6 * sizeof(channel.RingHeader), 6 * u64(fw.fw_log_size) * sizeof(fw.FwLogMsg), pgtable.gpu_prot_fw_gpu_shared_rw) {
		return none
	}
	if !mgr.alloc_g13_channel_pair(mut allocations, g13_ktrace_index, sizeof(channel.RingHeader), u64(fw.ktrace_size) * sizeof(fw.FwKTraceMsg), pgtable.gpu_prot_fw_gpu_shared_rw) {
		return none
	}
	if !mgr.alloc_g13_channel_pair(mut allocations, g13_stats_index, sizeof(channel.RingHeader), u64(fw.stats_size) * sizeof(fw.FwStatsMsg), pgtable.gpu_prot_fw_gpu_shared_rw) {
		return none
	}
	for pipe := u32(0); pipe < 12; pipe++ {
		if !mgr.alloc_g13_channel_pair(mut allocations, g13_pipe_base_index + pipe, sizeof(channel.RingHeader), u64(fw.pipe_size) * sizeof(fw.FwRunWorkQueueMsg), pgtable.gpu_prot_fw_private_rw) {
			return none
		}
	}
	complete = true
	return allocations
}

fn (mut mgr GpuManager) init_channels() bool {
	if sizeof(channel.RingHeader) != 0x30 || sizeof(channel.FwCtlRingHeader) != 0x20
		|| !fw.validate_g13_channel_layouts() {
		C.printf(c'agx: G13 channel ABI layout validation failed\n')
		return false
	}
	if mgr.g13_channels != unsafe { nil } {
		return false
	}
	mut allocations := mgr.allocate_g13_channels() or { return false }

	dev_state := &allocations.states[g13_device_control_index]
	dev_ring := &allocations.rings[g13_device_control_index]
	mgr.channels.device_ctrl = channel.new_tx_channel('devctl', dev_state.va, dev_state.phys, dev_ring.va, dev_ring.phys, fw.device_control_size, u32(sizeof(fw.FwDeviceControlMsg)))
	fwctl_state := &allocations.states[g13_fw_control_index]
	fwctl_ring := &allocations.rings[g13_fw_control_index]
	mgr.channels.fw_ctrl = channel.new_fwctl_tx_channel('fwctl', fwctl_state.va, fwctl_state.phys, fwctl_ring.va, fwctl_ring.phys, fw.fw_ctl_size, u32(sizeof(fw.FwFwCtlMsg)))
	event_state := &allocations.states[g13_event_index]
	event_ring := &allocations.rings[g13_event_index]
	mgr.channels.event = channel.new_rx_channel('event', event_state.va, event_state.phys, event_ring.va, event_ring.phys, fw.event_size, u32(sizeof(fw.FwEventMsg)))
	log_state := &allocations.states[g13_fw_log_index]
	log_ring := &allocations.rings[g13_fw_log_index]
	mgr.channels.fw_log = channel.new_rx_channel_with_subchannels('fwlog', log_state.va, log_state.phys, log_ring.va, log_ring.phys, fw.fw_log_size, u32(sizeof(fw.FwLogMsg)), 6)
	ktrace_state := &allocations.states[g13_ktrace_index]
	ktrace_ring := &allocations.rings[g13_ktrace_index]
	mgr.channels.ktrace = channel.new_rx_channel('ktrace', ktrace_state.va, ktrace_state.phys, ktrace_ring.va, ktrace_ring.phys, fw.ktrace_size, u32(sizeof(fw.FwKTraceMsg)))
	stats_state := &allocations.states[g13_stats_index]
	stats_ring := &allocations.rings[g13_stats_index]
	mgr.channels.stats = channel.new_rx_channel('stats', stats_state.va, stats_state.phys, stats_ring.va, stats_ring.phys, fw.stats_size, u32(sizeof(fw.FwStatsMsg)))
	for pipe := u32(0); pipe < 12; pipe++ {
		state := &allocations.states[g13_pipe_base_index + pipe]
		ring := &allocations.rings[g13_pipe_base_index + pipe]
		mgr.channels.pipes[pipe] = channel.new_tx_channel('pipe${pipe}', state.va, state.phys, ring.va, ring.phys, fw.pipe_size, u32(sizeof(fw.FwRunWorkQueueMsg)))
	}
	mgr.g13_channels = allocations
	return true
}

fn (mut mgr GpuManager) fail_g13_initialization() bool {
	mgr.stop_firmware_cpus(mgr.firmware_roles)
	mgr.release_g13_channels()
	mgr.initdata_va = 0
	mgr.initdata_phys = 0
	mgr.state = .error
	return false
}

// Full GPU initialization sequence
pub fn (mut mgr GpuManager) init() bool {
	mgr.lock.acquire()
	defer {
		mgr.lock.release()
	}

	mgr.state = .starting
	println('agx: Starting GPU initialization')
	if mgr.hw_config.firmware_abi == .g17_26_5_partial {
		return mgr.init_g17()
	}

	// Step 1: Start every firmware role's independent ASC CPU via ASC_CTL.
	for role := u32(0); role < mgr.firmware_roles; role++ {
		if !mgr.res.start_cpu(role) {
			C.printf(c'agx: Failed to start ASC role %u\n', role)
			mgr.stop_firmware_cpus(role)
			mgr.state = .error
			return false
		}
	}
	if mgr.hw_config.gpu_gen == .g13 {
		identity := mgr.res.get_g13_identity() or {
			C.printf(c'agx: Invalid G13 identity registers\n')
			mgr.stop_firmware_cpus(mgr.firmware_roles)
			mgr.state = .error
			return false
		}
		if !mgr.hw_config.apply_g13_identity(identity.revision_code, identity.num_clusters, identity.num_cores_per_cluster, identity.num_frags_per_cluster, identity.num_gps_per_cluster, identity.total_active_cores, identity.core_masks) {
			C.printf(c'agx: G13 identity exceeds t8103 hardware limits\n')
			mgr.stop_firmware_cpus(mgr.firmware_roles)
			mgr.state = .error
			return false
		}
		C.printf(c'agx: G13 topology: %u/%u active cores, mask 0x%x\n', identity.total_active_cores, identity.num_cores_per_cluster * identity.num_clusters, identity.core_masks[0])
	}

	// Step 2: Negotiate the RTKit transport independently for every role.
	for role := u32(0); role < mgr.firmware_roles; role++ {
		if !mgr.boot_firmware_role(role) {
			C.printf(c'agx: RTKit boot failed for role %u\n', role)
			return mgr.fail_g13_initialization()
		}
	}

	// Step 3: Start GPU-specific firmware endpoint (0x20) on each role.
	for role := u32(0); role < mgr.firmware_roles; role++ {
		if !mgr.start_firmware_endpoint(role, u8(ep_firmware)) {
			C.printf(c'agx: Failed to start firmware endpoint for role %u\n', role)
			return mgr.fail_g13_initialization()
		}
	}

	// Step 4: Start doorbell endpoint (0x21) on each role.
	for role := u32(0); role < mgr.firmware_roles; role++ {
		if !mgr.start_firmware_endpoint(role, u8(ep_doorbell)) {
			C.printf(c'agx: Failed to start doorbell endpoint for role %u\n', role)
			return mgr.fail_g13_initialization()
		}
	}

	// The firmware side of the uPPL handoff becomes available only after the
	// RTKit endpoints are running.
	if uat_mgr == unsafe { nil } || !uat_mgr.initialize_handoff() {
		C.printf(c'agx: UAT firmware handoff failed\n')
		return mgr.fail_g13_initialization()
	}

	// Step 5: Initialize firmware communication channels
	if !mgr.init_channels() {
		C.printf(c'agx: Failed to initialize channels\n')
		return mgr.fail_g13_initialization()
	}

	// Step 6: Allocate and initialize firmware init data
	if !mgr.init_firmware_data() {
		C.printf(c'agx: Failed to initialize firmware data\n')
		return mgr.fail_g13_initialization()
	}

	// Step 7: Publish the v12.3 Initialize command before making InitData live.
	initialize := fw.make_device_control_initialize()
	if !mgr.channels.device_ctrl.enqueue(voidptr(&initialize)) {
		C.printf(c'agx: Failed to queue device-control Initialize\n')
		return mgr.fail_g13_initialization()
	}

	// Step 8: Build and send MSG_INIT with initdata VA.
	if !mgr.send_fw_msg(msg_init, mgr.initdata_va) {
		C.printf(c'agx: Failed to send MSG_INIT\n')
		return mgr.fail_g13_initialization()
	}

	// Step 9: Ring the device-control doorbell, then wake the firmware. MSG_INIT
	// has no synchronous reply; consuming an arbitrary RTKit message as an
	// acknowledgement can steal the first real firmware notification.
	if !mgr.ring_device_control() || !mgr.kick_firmware() {
		C.printf(c'agx: Failed to ring G13 initialization doorbells\n')
		return mgr.fail_g13_initialization()
	}

	mgr.state = .running
	spawn event_worker(mut mgr)
	println('agx: GPU firmware initialized and running')
	return true
}

fn (mut mgr GpuManager) init_firmware_data() bool {
	if mgr.hw_config.firmware_abi == .g17_26_5_partial {
		return mgr.init_g17_firmware_data()
	}
	if mgr.g13_channels == unsafe { nil } || !fw.validate_g13_initdata_layouts() {
		C.printf(c'agx: G13 InitData outer layout validation failed\n')
		return false
	}
	mut graph := unsafe { mgr.g13_channels }
	if graph.initdata.va != 0 {
		return false
	}

	graph.unknown_buffer = mgr.alloc_shared_buffer_with_protection(0x4000, pgtable.gpu_prot_fw_shared_ro) or {
		return false
	}
	graph.runtime_pointers = mgr.alloc_shared_buffer_with_protection(fw.g13_runtime_pointers_size, pgtable.gpu_prot_fw_private_rw) or {
		return false
	}
	graph.globals = mgr.alloc_shared_buffer_with_protection(fw.g13_globals_size, pgtable.gpu_prot_fw_private_rw) or {
		return false
	}
	graph.fw_status = mgr.alloc_shared_buffer(sizeof(fw.G13FwStatus)) or {
		return false
	}
	graph.fwlog_payload = mgr.alloc_shared_buffer(u64(fw.g13_fwlog_subchannels) * u64(fw.g13_fwlog_payload_count) * sizeof(fw.FwLogPayloadMsg)) or {
		return false
	}
	graph.initdata = mgr.alloc_shared_buffer_with_protection(fw.g13_initdata_size, pgtable.gpu_prot_fw_private_rw) or {
		return false
	}

	unsafe {
		mut runtime := &fw.G13RuntimePointers(graph.runtime_pointers.phys + higher_half)
		for priority := u32(0); priority < 4; priority++ {
			base := priority * 3
			runtime.pipes[priority].vertex = fw.make_g13_ring_pointers(mgr.channels.pipes[base].state_base, mgr.channels.pipes[base].ring_base)
			runtime.pipes[priority].fragment = fw.make_g13_ring_pointers(mgr.channels.pipes[base + 1].state_base, mgr.channels.pipes[base + 1].ring_base)
			runtime.pipes[priority].compute = fw.make_g13_ring_pointers(mgr.channels.pipes[base + 2].state_base, mgr.channels.pipes[base + 2].ring_base)
		}
		runtime.device_control = fw.make_g13_ring_pointers(mgr.channels.device_ctrl.state_base, mgr.channels.device_ctrl.ring_base)
		runtime.event = fw.make_g13_ring_pointers(mgr.channels.event.state_base, mgr.channels.event.ring_base)
		runtime.fw_log = fw.make_g13_ring_pointers(mgr.channels.fw_log.state_base, mgr.channels.fw_log.ring_base)
		runtime.ktrace = fw.make_g13_ring_pointers(mgr.channels.ktrace.state_base, mgr.channels.ktrace.ring_base)
		runtime.stats = fw.make_g13_ring_pointers(mgr.channels.stats.state_base, mgr.channels.stats.ring_base)
		runtime.fwlog_buffer = graph.fwlog_payload.va
		// RuntimeScratch::unk_6b38 is 0xff in the reference 12.3 builder.
		runtime.gpu_scratch[0x68b8] = 0xff

		mut globals := &fw.G13Globals(graph.globals.phys + higher_half)
		globals.unk_028 = 1
		globals.unk_02c = 1
		globals.unk_034 = 120

		mut status := &fw.G13FwStatus(graph.fw_status.phys + higher_half)
		status.fwctl = fw.make_g13_ring_pointers(mgr.channels.fw_ctrl.state_base, mgr.channels.fw_ctrl.ring_base)
	}

	initdata := fw.build_g13_initdata(graph.unknown_buffer.va, graph.runtime_pointers.va, graph.globals.va, graph.fw_status.va, mgr.hw_config.uat_oas) or { return false }
	unsafe {
		C.memcpy(voidptr(graph.initdata.phys + higher_half), &initdata, sizeof(fw.G13InitData))
	}
	mgr.initdata_va = graph.initdata.va
	mgr.initdata_phys = graph.initdata.phys
	return true
}

// Ring the firmware doorbell for a specific channel to trigger processing.
// Doorbells are delivered on the dedicated doorbell endpoint (0x21) and carry
// the channel id; they are NOT the firmware-control endpoint (0x20) used for
// INIT/FWCTL. Ring state must already be published before this is called.
pub fn (mut mgr GpuManager) send_doorbell(channel_id u32) bool {
	return mgr.send_doorbell_to_role(0, channel_id)
}

pub fn (mut mgr GpuManager) send_doorbell_to_role(role u32, channel_id u32) bool {
	return mgr.send_role_message(role, u8(ep_doorbell), msg_tx_doorbell | (u64(channel_id) & msg_address_mask))
}

// Wake the G13 firmware after updating global submission state.
pub fn (mut mgr GpuManager) kick_firmware() bool {
	return mgr.send_doorbell(doorbell_kick_firmware)
}

// Notify G13 firmware that a device-control command is available.
pub fn (mut mgr GpuManager) ring_device_control() bool {
	return mgr.send_doorbell(doorbell_device_control)
}

// Notify one of the four priority instances of a G13 work pipe.
fn (mut mgr GpuManager) ring_pipe(priority u32, cmd_type u32) bool {
	return mgr.send_doorbell(pipe_doorbell(priority, cmd_type))
}

// Send a firmware-control message via RTKit on the firmware endpoint (0x20).
pub fn (mut mgr GpuManager) send_fw_msg(message u64, data u64) bool {
	return mgr.send_fw_msg_to_role(0, message, data)
}

pub fn (mut mgr GpuManager) send_fw_msg_to_role(role u32, message u64, data u64) bool {
	return mgr.send_role_message(role, u8(ep_firmware), message | (data & msg_address_mask))
}

// Process an event from the event channel
pub fn (mut mgr GpuManager) handle_event() {
	mut buf := [64]u8{}
	for mgr.channels.event.dequeue(voidptr(&buf[0])) {
		// EventMsg is a repr(C, u32) enum: its discriminant is the first word.
		event_type := unsafe { *&u32(&buf[0]) }
		match event_type {
			fw.fw_event_flag {
				gpu_event_mgr.scan_completions()
			}
			fw.fw_event_fault {
				C.printf(c'agx: GPU firmware error event\n')
				info := mgr.res.get_fault_info()
				C.printf(c'agx: Fault addr=0x%llx unit=%d\n', info.addr, info.unit_code)
				mgr.state = .error
			}
			fw.fw_event_timeout {
				C.printf(c'agx: GPU firmware timeout event\n')
				mgr.state = .error
			}
			fw.fw_event_grow_tvb {
				C.printf(c'agx: GrowTVB event is not implemented\n')
				mgr.state = .error
			}
			else {
				C.printf(c'agx: Unhandled event type %d\n', event_type)
			}
		}
	}
}

pub fn (mut mgr GpuManager) submit_render(cmd &queue.RenderCommand, priority u32) bool {
	if mgr.state != .running {
		return false
	}

	pipe_prio := priority % 4
	if cmd.flags & queue.render_flag_vertex != 0 {
		vertex := fw.FwVertexCmd{
			header: fw.FwCmdHeader{
				tag: fw.cmd_type_run_vertex
				cmd_type: fw.cmd_type_run_vertex
				flags: cmd.flags
			}
			scene_addr: cmd.scene_addr
			buf_addr: cmd.vertex_buf_addr
			buf_size: cmd.vertex_buf_size
			tvb_addr: cmd.tvb_addr
			vertex_count: cmd.vertex_count
			instance_count: cmd.instance_count
			stamp_addr: cmd.stamp_addr
			stamp_value: cmd.stamp_value
			result_addr: cmd.result_addr
			result_size: cmd.result_size
		}
		idx := pipe_index(pipe_prio, 0)
		if !mgr.channels.pipes[idx].enqueue(voidptr(&vertex)) {
			return false
		}
		if !mgr.ring_pipe(pipe_prio, 0) {
			return false
		}
	}

	if cmd.flags & queue.render_flag_fragment != 0 {
		fragment := fw.FwFragmentCmd{
			header: fw.FwCmdHeader{
				tag: fw.cmd_type_run_fragment
				cmd_type: fw.cmd_type_run_fragment
				flags: cmd.flags
			}
			scene_addr: cmd.scene_addr
			buf_addr: cmd.frag_buf_addr
			buf_size: cmd.frag_buf_size
			width: cmd.width
			height: cmd.height
			tile_width: cmd.tile_width
			tile_height: cmd.tile_height
			stamp_addr: cmd.stamp_addr
			stamp_value: cmd.stamp_value
			result_addr: cmd.result_addr
			result_size: cmd.result_size
			layers: cmd.layers
			samples: cmd.samples
		}
		idx := pipe_index(pipe_prio, 1)
		if !mgr.channels.pipes[idx].enqueue(voidptr(&fragment)) {
			return false
		}
		if !mgr.ring_pipe(pipe_prio, 1) {
			return false
		}
	}
	return true
}

pub fn (mut mgr GpuManager) submit_compute(cmd &queue.ComputeCommand, priority u32) bool {
	if mgr.state != .running {
		return false
	}

	compute := fw.FwComputeCmd{
		header: fw.FwCmdHeader{
			tag: fw.cmd_type_run_compute
			cmd_type: fw.cmd_type_run_compute
			flags: cmd.flags
		}
		buf_addr: cmd.compute_buf_addr
		buf_size: cmd.compute_buf_size
		wg_x: cmd.wg_x
		wg_y: cmd.wg_y
		wg_z: cmd.wg_z
		grid_x: cmd.grid_x
		grid_y: cmd.grid_y
		grid_z: cmd.grid_z
		shared_mem_size: cmd.shared_mem_size
		stamp_addr: cmd.stamp_addr
		stamp_value: cmd.stamp_value
		result_addr: cmd.result_addr
		result_size: cmd.result_size
	}

	idx := pipe_index(priority % 4, 2)
	if !mgr.channels.pipes[idx].enqueue(voidptr(&compute)) {
		return false
	}

	return mgr.ring_pipe(priority % 4, 2)
}

fn event_worker(mut mgr GpuManager) {
	for mgr.state == .running {
		mgr.handle_event()
		gpu_event_mgr.scan_completions()
		sched.yield(false)
	}
}

// Shutdown the GPU
pub fn (mut mgr GpuManager) shutdown() {
	mgr.lock.acquire()
	defer {
		mgr.lock.release()
	}

	mgr.state = .stopped
	mgr.send_fw_msg(msg_halt, 0)
	mgr.stop_firmware_cpus(mgr.firmware_roles)
	mgr.release_g13_channels()
	mgr.release_all_g17_queue_resources()
	mgr.release_g17_firmware_graph()
	println('agx: GPU shutdown complete')
}
