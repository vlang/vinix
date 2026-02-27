@[has_globals]
module gpu

// GPU Manager -- top-level GPU control
// Handles RTKit endpoints, firmware initialization, ring buffer setup,
// and work submission coordination
// Translates gpu.rs from the Asahi Linux GPU driver

import apple.rtkit
import apple.dart
import gpu.agx.regs
import gpu.agx.hw
import gpu.agx.mmu
import gpu.agx.channel
import gpu.agx.alloc
import gpu.agx.fw
import gpu.agx.queue
import gpu.agx.event
import memory
import lib
import klock
import sched

// RTKit endpoint IDs for GPU firmware
pub const ep_firmware = u32(0x20)
pub const ep_doorbell = u32(0x21)

// GPU message types (encoded in bits [63:56] by rtkit.send_msg)
pub const msg_init = u8(0x81)
pub const msg_tx_doorbell = u8(0x83)
pub const msg_fwctl = u8(0x84)
pub const msg_halt = u8(0x85)

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
	res         regs.GpuResources
	hw_config   hw.HwConfig
	rtk         rtkit.RTKit
	gpu_dart    dart.DART
	channels    GpuChannels
	allocs      alloc.HeapAllocator
	initdata_va   u64
	initdata_phys u64
	state       GpuState
		lock        klock.Lock
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

pub fn new_gpu_manager(res &regs.GpuResources, cfg &hw.HwConfig, rtk &rtkit.RTKit, d &dart.DART) ?&GpuManager {
	version, core_count := res.get_gpu_id()
	println('agx: GPU ID version=0x${version:x} cores=${core_count}')

	mut mgr := &GpuManager{
		res:       unsafe { *res }
		hw_config: unsafe { *cfg }
		rtk:       unsafe { *rtk }
		gpu_dart:  unsafe { *d }
		state:     .idle
		allocs:    alloc.new_heap('agx-shared', alloc.gpu_shared_start, alloc.gpu_shared_end)
	}

	return mgr
}

struct SharedBuffer {
	va   u64
	phys u64
	size u64
}

@[inline]
fn pipe_index(priority u32, cmd_type u32) u32 {
	return (priority % 4) * 3 + (cmd_type % 3)
}

fn (mut mgr GpuManager) alloc_shared_buffer(size u64) ?SharedBuffer {
	pages := lib.div_roundup(size, page_size)
	phys := u64(memory.pmm_alloc(pages))
	if phys == 0 {
		return none
	}

	unsafe {
		C.memset(voidptr(phys + higher_half), 0, pages * page_size)
	}

	va := mgr.allocs.alloc(size, alloc.gpu_page_size) or {
		return none
	}

	if !mgr.gpu_dart.map(va, phys, size) {
		return none
	}

	if uat_mgr != unsafe { nil } {
		if !uat_mgr.map_kernel(va, phys, size, 0x43) {
			return none
		}
	}

	return SharedBuffer{
		va:   va
		phys: phys
		size: size
	}
}

fn (mut mgr GpuManager) init_channels() bool {
	// Device control TX
	devctl_entry := u32(sizeof(fw.FwDeviceControlMsg))
	devctl_size := u64(sizeof(channel.RingHeader)) + u64(fw.device_control_size) * u64(devctl_entry)
	devctl := mgr.alloc_shared_buffer(devctl_size) or { return false }
	mgr.channels.device_ctrl = channel.new_tx_channel('devctl', devctl.va, devctl.phys,
		fw.device_control_size, devctl_entry)

	// Firmware control TX
	fwctl_entry := u32(sizeof(fw.FwFwCtlMsg))
	fwctl_size := u64(sizeof(channel.RingHeader)) + u64(fw.fw_ctl_size) * u64(fwctl_entry)
	fwctl := mgr.alloc_shared_buffer(fwctl_size) or { return false }
	mgr.channels.fw_ctrl = channel.new_tx_channel('fwctl', fwctl.va, fwctl.phys, fw.fw_ctl_size,
		fwctl_entry)

	// Event RX
	event_entry := u32(sizeof(fw.FwEventMsg))
	event_size := u64(sizeof(channel.RingHeader)) + u64(fw.event_size) * u64(event_entry)
	ev := mgr.alloc_shared_buffer(event_size) or { return false }
	mgr.channels.event = channel.new_rx_channel('event', ev.va, ev.phys, fw.event_size, event_entry)

	// Log/Ktrace/Stats RX channels
	log_entry := u32(sizeof(fw.FwLogMsg))
	log_size := u64(sizeof(channel.RingHeader)) + u64(fw.fw_log_size) * u64(log_entry)
	log := mgr.alloc_shared_buffer(log_size) or { return false }
	mgr.channels.fw_log = channel.new_rx_channel('fwlog', log.va, log.phys, fw.fw_log_size, log_entry)

	ktrace_entry := u32(sizeof(fw.FwKTraceMsg))
	ktrace_size := u64(sizeof(channel.RingHeader)) + u64(fw.ktrace_size) * u64(ktrace_entry)
	ktrace := mgr.alloc_shared_buffer(ktrace_size) or { return false }
	mgr.channels.ktrace = channel.new_rx_channel('ktrace', ktrace.va, ktrace.phys, fw.ktrace_size,
		ktrace_entry)

	stats_entry := u32(sizeof(fw.FwStatsMsg))
	stats_size := u64(sizeof(channel.RingHeader)) + u64(fw.stats_size) * u64(stats_entry)
	stats := mgr.alloc_shared_buffer(stats_size) or { return false }
	mgr.channels.stats = channel.new_rx_channel('stats', stats.va, stats.phys, fw.stats_size, stats_entry)

	// 12 pipe channels: 4 priorities x (vertex, fragment, compute)
	for i := u32(0); i < 12; i++ {
		entry_size := match i % 3 {
			0 { u32(sizeof(fw.FwVertexCmd)) }
			1 { u32(sizeof(fw.FwFragmentCmd)) }
			else { u32(sizeof(fw.FwComputeCmd)) }
		}
		pipe_bytes := u64(sizeof(channel.RingHeader)) + u64(fw.pipe_size) * u64(entry_size)
		pipe := mgr.alloc_shared_buffer(pipe_bytes) or { return false }
		mgr.channels.pipes[i] = channel.new_tx_channel('pipe${i}', pipe.va, pipe.phys, fw.pipe_size,
			entry_size)
	}

	return true
}

// Full GPU initialization sequence
pub fn (mut mgr GpuManager) init() bool {
	mgr.lock.acquire()
	defer {
		mgr.lock.release()
	}

	mgr.state = .starting
	println('agx: Starting GPU initialization')

	// Step 1: Initialize DART IOMMU
	mgr.gpu_dart.init()

	// Step 2: Start the ASC CPU via ASC_CTL
	mgr.res.start_cpu()

	// Step 3: RTKit boot handshake
	if !mgr.rtk.boot() {
		C.printf(c'agx: RTKit boot failed\n')
		mgr.state = .error
		return false
	}

	// Step 4: Start GPU-specific firmware endpoint (0x20)
	if !mgr.rtk.start_endpoint(u8(ep_firmware)) {
		C.printf(c'agx: Failed to start firmware endpoint\n')
		mgr.state = .error
		return false
	}

	// Step 5: Start doorbell endpoint (0x21)
	if !mgr.rtk.start_endpoint(u8(ep_doorbell)) {
		C.printf(c'agx: Failed to start doorbell endpoint\n')
		mgr.state = .error
		return false
	}

	// Step 6: Initialize firmware communication channels
	if !mgr.init_channels() {
		C.printf(c'agx: Failed to initialize channels\n')
		mgr.state = .error
		return false
	}

	// Step 7: Allocate and initialize firmware init data
	if !mgr.init_firmware_data() {
		C.printf(c'agx: Failed to initialize firmware data\n')
		mgr.state = .error
		return false
	}

	// Step 8: Build and send MSG_INIT with initdata VA
	if !mgr.send_fw_msg(msg_init, mgr.initdata_va) {
		C.printf(c'agx: Failed to send MSG_INIT\n')
		mgr.state = .error
		return false
	}

	// Step 9: Wait for MSG_INIT acknowledgment
	_ := mgr.rtk.recv_msg_blocking(10000000) or {
		C.printf(c'agx: Timeout waiting for INIT ack\n')
		mgr.state = .error
		return false
	}

	// Step 10: Ring doorbell to kick firmware
	mgr.kick_firmware()

	mgr.state = .running
	spawn event_worker(mut mgr)
	println('agx: GPU firmware initialized and running')
	return true
}

fn (mut mgr GpuManager) init_firmware_data() bool {
	initdata_size := u64(0x10000) // 64KB firmware init blob
	initdata_pages := lib.div_roundup(initdata_size, page_size)

	initdata_phys := u64(memory.pmm_alloc(initdata_pages))
	if initdata_phys == 0 {
		C.printf(c'agx: Failed to allocate initdata memory\n')
		return false
	}

	// Zero-initialise
	unsafe {
		C.memset(voidptr(initdata_phys + higher_half), 0, initdata_size)
	}

	mgr.initdata_phys = initdata_phys

	// Allocate a VA from the shared heap and map via the kernel page table
	initdata_va := mgr.allocs.alloc(initdata_size, alloc.gpu_page_size) or {
		C.printf(c'agx: Failed to allocate initdata VA\n')
		return false
	}
	// Map into GPU VA space via DART and UAT.
	if !mgr.gpu_dart.map(initdata_va, initdata_phys, initdata_size) {
		C.printf(c'agx: Failed to map initdata in DART\n')
		return false
	}

	if uat_mgr != unsafe { nil } {
		if !uat_mgr.map_kernel(initdata_va, initdata_phys, initdata_size, 0x43) {
			C.printf(c'agx: Failed to map initdata into kernel UAT\n')
			return false
		}
	}

	mgr.initdata_va = initdata_va

	// Build minimal initdata tree used by firmware bootstrap.
	channel_base := mgr.channels.device_ctrl.ring_base
	log_base := mgr.channels.fw_log.ring_base
	ktrace_base := mgr.channels.ktrace.ring_base
	stats_base := mgr.channels.stats.ring_base

	mut init := fw.build_initdata(&mgr.hw_config, channel_base, log_base, ktrace_base, stats_base)
	init.region_a_addr = initdata_va + 0x400
	init.region_b_addr = initdata_va + 0x800
	init.region_c_addr = initdata_va + 0xC00
	init.fw_status_addr = initdata_va + 0x1000

	region_a := fw.build_region_a(channel_base, log_base,
		mgr.channels.fw_log.ring_size * mgr.channels.fw_log.entry_size, ktrace_base,
		mgr.channels.ktrace.ring_size * mgr.channels.ktrace.entry_size, stats_base,
		mgr.channels.stats.ring_size * mgr.channels.stats.entry_size)
	region_b := fw.build_region_b(&mgr.hw_config)
	region_c := fw.RegionC{}
	status := fw.FwStatus{}

	base := initdata_phys + higher_half
	unsafe {
		C.memcpy(voidptr(base), &init, sizeof(fw.InitData))
		C.memcpy(voidptr(base + 0x400), &region_a, sizeof(fw.RegionA))
		C.memcpy(voidptr(base + 0x800), &region_b, sizeof(fw.RegionB))
		C.memcpy(voidptr(base + 0xC00), &region_c, sizeof(fw.RegionC))
		C.memcpy(voidptr(base + 0x1000), &status, sizeof(fw.FwStatus))
	}

	return true
}

// Ring the firmware doorbell to trigger processing
pub fn (mut mgr GpuManager) kick_firmware() {
	mgr.send_fw_msg(msg_tx_doorbell, 0)
}

// Send a firmware message via RTKit
pub fn (mut mgr GpuManager) send_fw_msg(msg_type u8, data u64) bool {
	return mgr.rtk.send_msg(u8(ep_firmware), msg_type, data)
}

// Process an event from the event channel
pub fn (mut mgr GpuManager) handle_event() {
	mut buf := [64]u8{}
	for mgr.channels.event.dequeue(voidptr(&buf[0])) {
		// Dispatch based on event type at offset 4
		event_type := unsafe { *&u32(&buf[4]) }
		match event_type {
			fw.fw_event_init {
				println('agx: Firmware init event received')
			}
			fw.fw_event_vertex_done, fw.fw_event_fragment_done, fw.fw_event_compute_done,
			fw.fw_event_stamp {
				gpu_event_mgr.scan_completions()
			}
			fw.fw_event_error {
				C.printf(c'agx: GPU firmware error event\n')
				info := mgr.res.get_fault_info()
				C.printf(c'agx: Fault addr=0x%llx unit=%d\n', info.addr, info.unit_code)
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
				tag:      fw.cmd_type_run_vertex
				cmd_type: fw.cmd_type_run_vertex
				flags:    cmd.flags
			}
			scene_addr:     cmd.scene_addr
			buf_addr:       cmd.vertex_buf_addr
			buf_size:       cmd.vertex_buf_size
			tvb_addr:       cmd.tvb_addr
			vertex_count:   cmd.vertex_count
			instance_count: cmd.instance_count
			stamp_addr:     cmd.stamp_addr
			stamp_value:    cmd.stamp_value
			result_addr:    cmd.result_addr
			result_size:    cmd.result_size
		}
		idx := pipe_index(pipe_prio, 0)
		if !mgr.channels.pipes[idx].enqueue(voidptr(&vertex)) {
			return false
		}
	}

	if cmd.flags & queue.render_flag_fragment != 0 {
		fragment := fw.FwFragmentCmd{
			header: fw.FwCmdHeader{
				tag:      fw.cmd_type_run_fragment
				cmd_type: fw.cmd_type_run_fragment
				flags:    cmd.flags
			}
			scene_addr:  cmd.scene_addr
			buf_addr:    cmd.frag_buf_addr
			buf_size:    cmd.frag_buf_size
			width:       cmd.width
			height:      cmd.height
			tile_width:  cmd.tile_width
			tile_height: cmd.tile_height
			stamp_addr:  cmd.stamp_addr
			stamp_value: cmd.stamp_value
			result_addr: cmd.result_addr
			result_size: cmd.result_size
			layers:      cmd.layers
			samples:     cmd.samples
		}
		idx := pipe_index(pipe_prio, 1)
		if !mgr.channels.pipes[idx].enqueue(voidptr(&fragment)) {
			return false
		}
	}

	mgr.kick_firmware()
	return true
}

pub fn (mut mgr GpuManager) submit_compute(cmd &queue.ComputeCommand, priority u32) bool {
	if mgr.state != .running {
		return false
	}

	compute := fw.FwComputeCmd{
		header: fw.FwCmdHeader{
			tag:      fw.cmd_type_run_compute
			cmd_type: fw.cmd_type_run_compute
			flags:    cmd.flags
		}
		buf_addr:        cmd.compute_buf_addr
		buf_size:        cmd.compute_buf_size
		wg_x:            cmd.wg_x
		wg_y:            cmd.wg_y
		wg_z:            cmd.wg_z
		grid_x:          cmd.grid_x
		grid_y:          cmd.grid_y
		grid_z:          cmd.grid_z
		shared_mem_size: cmd.shared_mem_size
		stamp_addr:      cmd.stamp_addr
		stamp_value:     cmd.stamp_value
		result_addr:     cmd.result_addr
		result_size:     cmd.result_size
	}

	idx := pipe_index(priority % 4, 2)
	if !mgr.channels.pipes[idx].enqueue(voidptr(&compute)) {
		return false
	}

	mgr.kick_firmware()
	return true
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
	mgr.res.stop_cpu()
	println('agx: GPU shutdown complete')
}
