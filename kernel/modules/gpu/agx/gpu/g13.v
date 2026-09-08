// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module gpu

// Queue-owned object graph for the G13/macOS 12.3 firmware ABI. All buffers
// are driver-owned and stay mapped until the DRM queue is explicitly destroyed
// or its file is closed.

import gpu.agx.fw
import gpu.agx.alloc
import gpu.agx.command as agxcommand
import gpu.agx.compute as agxcompute
import gpu.agx.pgtable
import gpu.agx.event
import gpu.agx.mmu
import gpu.agx.render as agxrender
import katomic
import klock

pub const g13_queue_channel_vertex = u32(1) << 0
pub const g13_queue_channel_fragment = u32(1) << 1
pub const g13_queue_channel_compute = u32(1) << 2
const g13_queue_channel_mask = g13_queue_channel_vertex | g13_queue_channel_fragment | g13_queue_channel_compute
const g13_tvb_max_size = u64(862_322_688)
const g13_tvb_max_blocks = u32(g13_tvb_max_size / fw.g13_tvb_block_size)
const g13_tvb_max_blocks_nomemless = g13_tvb_max_blocks / u32(3)
const g13_tvb_max_pages = g13_tvb_max_blocks * fw.g13_tvb_pages_per_block

struct G13EventResources {
mut:
	driver_stamps   SharedBuffer
	firmware_stamps SharedBuffer
	initialized     bool
}

struct G13SubQueueResources {
mut:
	state      SharedBuffer
	ring       SharedBuffer
	gpu_buffer SharedBuffer
	info       SharedBuffer
	pipe_type  u32
	is_new     bool
	lock       klock.Lock
}

struct G13RenderBufferResources {
mut:
	context       &mmu.UatContext = unsafe { nil }
	slot          u32
	slot_reserved bool
	info          SharedBuffer
	block_control SharedBuffer
	counter       SharedBuffer
	stats         SharedBuffer
	kernel_buffer SharedBuffer
	page_list     &mmu.UatBuffer = unsafe { nil }
	block_list    &mmu.UatBuffer = unsafe { nil }
	blocks        []&mmu.UatBuffer
	initialized   bool
}

struct G13TileInfo {
mut:
	tiles_x            u32
	tiles_y            u32
	tiles              u32
	tiles_per_mtile_x  u32
	tiles_per_mtile_y  u32
	utiles_per_mtile_x u32
	utiles_per_mtile_y u32
	tilemap_size       u64
	tail_pointer_size  u64
	layermeta_size     u64
	min_tvb_blocks     u32
	utile_config       u32
	params             fw.G13TilingParameters
}

pub struct G13ComputeJobResources {
pub mut:
	event_slot         u32
	stamp_value        u32
	event_sequence     u64
	command            SharedBuffer
	microsequence      SharedBuffer
	timestamps         SharedBuffer
	preempt            &mmu.UatBuffer = unsafe { nil }
	context            &mmu.UatContext = unsafe { nil }
	queue              &G13QueueResources = unsafe { nil }
	event_reserved     bool
	mappings_published bool
	quarantined        bool
	submitted          bool
	pending_counted    bool
	released           bool
	completion         fn (&G13ComputeJobResources, bool, voidptr) = unsafe { nil }
	completion_data    voidptr
	completion_result  fw.G13JobTimestamps
	completion_ready   bool
}

struct G13RenderSceneResources {
mut:
	scene              SharedBuffer
	timestamps         SharedBuffer
	user_buffer        &mmu.UatBuffer = unsafe { nil }
	heapmeta           &mmu.UatBuffer = unsafe { nil }
	tilemap            &mmu.UatBuffer = unsafe { nil }
	tail_pointer_cache &mmu.UatBuffer = unsafe { nil }
	preempt            &mmu.UatBuffer = unsafe { nil }
	aux_framebuffer    &mmu.UatBuffer = unsafe { nil }
}

pub struct G13RenderResultValues {
pub:
	vertex_start      u64
	vertex_end        u64
	fragment_start    u64
	fragment_end      u64
	tvb_size_bytes    u64
	tvb_usage_bytes   u64
	num_tvb_overflows u32
	overflowed        bool
}

pub struct G13RenderJobResources {
pub mut:
	vertex_event_slot       u32
	fragment_event_slot     u32
	vertex_stamp_value      u32
	fragment_stamp_value    u32
	vertex_event_sequence   u64
	fragment_event_sequence u64
	init_buffer             SharedBuffer
	barrier                 SharedBuffer
	vertex                  SharedBuffer
	fragment                SharedBuffer
	vertex_microsequence    SharedBuffer
	fragment_microsequence  SharedBuffer
	scene                   G13RenderSceneResources
	queue                   &G13QueueResources = unsafe { nil }
	context                 &mmu.UatContext = unsafe { nil }
	vertex_event_reserved   bool
	fragment_event_reserved bool
	mappings_published      bool
	quarantined             bool
	submitted               bool
	pending_counted         bool
	released                bool
	completion              fn (&G13RenderJobResources, bool, voidptr) = unsafe { nil }
	completion_data         voidptr
	tvb_size_bytes          u64
	completion_result       G13RenderResultValues
	completion_result_ready bool
}

pub struct G13QueueResources {
pub:
	queue_id     u32
	channel_mask u32
	priority     u32
mut:
	context            SharedBuffer
	notifier_list      SharedBuffer
	threshold          SharedBuffer
	notifier           SharedBuffer
	subqueues          [3]G13SubQueueResources
	event_sequences    [3]u64
	render_buffer      G13RenderBufferResources
	vm                 &mmu.UatContext = unsafe { nil }
	mappings_published bool
	quarantined        bool
	render_job_active  bool
	released           bool
}

// The firmware samples pending_submissions to decide whether the GPU may
// sleep. Manager serialization makes the host-side update a single-writer
// operation; katomic load/store retain the acquire/release ordering required
// by the shared firmware ABI.
fn (mut mgr GpuManager) g13_pending_submissions_locked() ?&u32 {
	if mgr.g13_channels == unsafe { nil } {
		return none
	}
	graph := mgr.g13_channels
	if graph.globals.phys == 0
		|| graph.globals.size < fw.g13_globals_pending_submissions_offset + sizeof(u32) {
		return none
	}
	return unsafe {
		&u32(graph.globals.phys + higher_half + fw.g13_globals_pending_submissions_offset)
	}
}

fn (mut mgr GpuManager) begin_g13_operation_locked() bool {
	if mgr.state != .running || mgr.hw_config.gpu_gen != .g13 {
		return false
	}
	mut pending := mgr.g13_pending_submissions_locked() or { return false }
	old_pending := katomic.load(pending)
	if old_pending == ~u32(0) {
		return false
	}
	katomic.store(mut pending, old_pending + 1)
	if !mgr.kick_firmware() {
		katomic.store(mut pending, old_pending)
		C.printf(c'agx: failed to wake G13 firmware for submission\n')
		mgr.state = .error
		return false
	}
	return true
}

fn (mut mgr GpuManager) end_g13_operation_locked() bool {
	mut pending := mgr.g13_pending_submissions_locked() or { return false }
	old_pending := katomic.load(pending)
	if old_pending == 0 {
		C.printf(c'agx: G13 pending submission counter underflow\n')
		if mgr.state == .running {
			mgr.state = .error
		}
		return false
	}
	katomic.store(mut pending, old_pending - 1)
	return true
}

fn (mut mgr GpuManager) flush_g13_kernel_buffer(buffer &SharedBuffer) bool {
	if buffer == unsafe { nil } || buffer.va == 0 || buffer.size == 0 {
		return false
	}
	return mgr.flush_g13_uat_range(mmu.uat_kernel_flush_slot, buffer.va, buffer.size)
}

fn (mut mgr GpuManager) flush_g13_queue_mappings(resources &G13QueueResources) bool {
	if !mgr.flush_g13_kernel_buffer(&resources.context)
		|| !mgr.flush_g13_kernel_buffer(&resources.notifier_list)
		|| !mgr.flush_g13_kernel_buffer(&resources.threshold)
		|| !mgr.flush_g13_kernel_buffer(&resources.notifier) {
		return false
	}
	for pipe_type := u32(0); pipe_type < 3; pipe_type++ {
		if resources.channel_mask & (u32(1) << pipe_type) == 0 {
			continue
		}
		queue := &resources.subqueues[pipe_type]
		if !mgr.flush_g13_kernel_buffer(&queue.gpu_buffer)
			|| !mgr.flush_g13_kernel_buffer(&queue.state)
			|| !mgr.flush_g13_kernel_buffer(&queue.ring)
			|| !mgr.flush_g13_kernel_buffer(&queue.info) {
			return false
		}
	}
	if resources.render_buffer.initialized {
		buffer := &resources.render_buffer
		if !mgr.flush_g13_kernel_buffer(&buffer.info)
			|| !mgr.flush_g13_kernel_buffer(&buffer.block_control)
			|| !mgr.flush_g13_kernel_buffer(&buffer.counter)
			|| !mgr.flush_g13_kernel_buffer(&buffer.stats)
			|| !mgr.flush_g13_kernel_buffer(&buffer.kernel_buffer)
			|| !mgr.flush_g13_uat_range(resources.vm.id, buffer.page_list.va, buffer.page_list.size)
			|| !mgr.flush_g13_uat_range(resources.vm.id, buffer.block_list.va, buffer.block_list.size) {
			return false
		}
	}
	return true
}

@[inline]
fn g13_div_round_up(value u32, divisor u32) u32 {
	return value / divisor + if value % divisor != 0 { u32(1) } else { u32(0) }
}

@[inline]
fn g13_align_u32(value u32, alignment u32) u32 {
	return (value + alignment - 1) & ~(alignment - 1)
}

fn g13_tile_info(width u32, height u32, layers u32, utile_width u32,
	utile_height u32, samples u32, ppp_control u32, helper_cfg u32) ?G13TileInfo {
	if width == 0 || height == 0 || width > 16384 || height > 16384 || layers == 0
		|| layers > 2048 || !((utile_width == 32 && utile_height == 32)
		|| (utile_width == 32 && utile_height == 16)
		|| (utile_width == 16 && utile_height == 16)) {
		return none
	}
	sample_bits := match samples {
		1 { u32(0) }
		2 { u32(1) }
		4 { u32(2) }
		else {
			return none
		}
	}
	utiles_per_tile_x := u32(32) / utile_width
	utiles_per_tile_y := u32(32) / utile_height
	utiles_per_tile := utiles_per_tile_x * utiles_per_tile_y
	tiles_x := g13_div_round_up(width, 32)
	tiles_y := g13_div_round_up(height, 32)
	tiles := tiles_x * tiles_y
	tiles_per_mtile_x := g13_align_u32(g13_div_round_up(tiles_x, 4), 4)
	tiles_per_mtile_y := g13_align_u32(g13_div_round_up(tiles_y, 4), 4)
	tiles_per_mtile := tiles_per_mtile_x * tiles_per_mtile_y
	region_size := g13_align_u32(5 * tiles_per_mtile * utiles_per_tile, 4) / 4
	tail_pointer_stride := 8 * utiles_per_tile * tiles_per_mtile / 4
	tilemap_size := u64(4) * region_size * u64(16) * layers
	tail_pointer_size := u64(4) * tail_pointer_stride * u64(16) * layers
	min_tvb_blocks := g13_align_u32(g13_div_round_up(tiles, 128), 8)
	mut utile_config := ((utile_width / 16) << 12) | ((utile_height / 16) << 14)
	utile_config |= sample_bits
	return G13TileInfo{
		tiles_x: tiles_x
		tiles_y: tiles_y
		tiles: tiles
		tiles_per_mtile_x: tiles_per_mtile_x
		tiles_per_mtile_y: tiles_per_mtile_y
		utiles_per_mtile_x: tiles_per_mtile_x * utiles_per_tile_x
		utiles_per_mtile_y: tiles_per_mtile_y * utiles_per_tile_y
		tilemap_size: tilemap_size
		tail_pointer_size: tail_pointer_size
		layermeta_size: if layers > 1 { u64(0x100) } else { u64(0) }
		min_tvb_blocks: min_tvb_blocks
		utile_config: utile_config
		params: fw.G13TilingParameters{
			region_size: region_size
			unk_4: 0x88
			ppp_control: ppp_control
			x_max: u16(width - 1)
			y_max: u16(height - 1)
			te_screen: ((tiles_y - 1) << 12) | (tiles_x - 1)
			te_mtile_1: 3 * tiles_per_mtile_x | (2 * tiles_per_mtile_x << 9) | (tiles_per_mtile_x << 18)
			te_mtile_2: 3 * tiles_per_mtile_y | (2 * tiles_per_mtile_y << 9) | (tiles_per_mtile_y << 18)
			tiles_per_mtile: tiles_per_mtile
			tail_pointer_stride: tail_pointer_stride
			unk_24: 0x100
			unk_28: if layers > 1 { 0xe000 | (layers - 1) } else { u32(0x8000) }
			helper_cfg: helper_cfg
		}
	}
}

fn (mut mgr GpuManager) reserve_g13_tvb_slot() ?u32 {
	for slot := u32(0); slot < fw.g13_tvb_slot_count; slot++ {
		if !mgr.g13_tvb_slots[slot] {
			mgr.g13_tvb_slots[slot] = true
			return slot
		}
	}
	return none
}

// Caller holds mgr.lock. No submitted job may still reference this buffer.
fn (mut mgr GpuManager) free_g13_render_buffer_locked(mut buffer G13RenderBufferResources) {
	if !buffer.initialized && !buffer.slot_reserved && buffer.info.va == 0
		&& buffer.page_list == unsafe { nil } {
		return
	}
	if buffer.context != unsafe { nil } {
		mut context := unsafe { buffer.context }
		for index := buffer.blocks.len - 1; index >= 0; index-- {
			context.release_driver_buffer(buffer.blocks[index])
		}
		buffer.blocks.clear()
		context.release_driver_buffer(buffer.block_list)
		context.release_driver_buffer(buffer.page_list)
	}
	mgr.free_shared_buffer(mut buffer.kernel_buffer)
	mgr.free_shared_buffer(mut buffer.stats)
	mgr.free_shared_buffer(mut buffer.counter)
	mgr.free_shared_buffer(mut buffer.block_control)
	mgr.free_shared_buffer(mut buffer.info)
	if buffer.slot_reserved && buffer.slot < fw.g13_tvb_slot_count {
		mgr.g13_tvb_slots[buffer.slot] = false
	}
	buffer = G13RenderBufferResources{}
	mgr.g13_private.gc()
	mgr.g13_shared.gc()
}

fn (mut mgr GpuManager) initialize_g13_render_buffer(mut resources G13QueueResources,
	ctx &mmu.UatContext) bool {
	if ctx == unsafe { nil } || !ctx.active || ctx.id == 0 || !fw.validate_g13_buffer_layouts()
		|| mgr.hw_config.preempt1_size == 0 || mgr.hw_config.preempt2_size == 0
		|| mgr.hw_config.preempt3_size == 0 {
		return false
	}
	mut buffer := &resources.render_buffer
	buffer.context = unsafe { ctx }
	buffer.slot = mgr.reserve_g13_tvb_slot() or { return false }
	buffer.slot_reserved = true
	mut complete := false
	defer {
		if !complete {
			mgr.free_g13_render_buffer_locked(mut buffer)
		}
	}
	mut context := unsafe { ctx }
	buffer.info = mgr.alloc_g13_buffer_with_protection(sizeof(fw.G13BufferInfo), pgtable.gpu_prot_fw_private_rw) or { return false }
	buffer.block_control = mgr.alloc_g13_shared_buffer(sizeof(fw.G13BufferBlockControl)) or {
		return false
	}
	buffer.counter = mgr.alloc_g13_shared_buffer(sizeof(fw.G13BufferCounter)) or { return false }
	buffer.stats = mgr.alloc_g13_shared_buffer(sizeof(fw.G13BufferStats)) or { return false }
	buffer.kernel_buffer = mgr.alloc_g13_shared_buffer(0x40) or { return false }
	buffer.page_list = context.alloc_driver_buffer_aligned(u64(g13_tvb_max_pages) * sizeof(u32), true, fw.g13_tvb_page_size) or {
		return false
	}
	buffer.block_list = context.alloc_driver_buffer_aligned(u64(g13_tvb_max_blocks) * u64(2) * sizeof(u32), true, fw.g13_tvb_page_size) or {
		return false
	}
	unsafe {
		mut info := &fw.G13BufferInfo(buffer.info.cpu_address())
		info.cur_id = -1
		info.page_list = buffer.page_list.va
		info.page_list_size = g13_tvb_max_pages * u32(sizeof(u32))
		info.max_blocks = g13_tvb_max_blocks
		info.block_list = buffer.block_list.va
		info.block_control = buffer.block_control.va
		info.block_size = u32(fw.g13_tvb_block_size)
		info.counter = buffer.counter.va
		info.unk_80 = 1
		info.max_pages = g13_tvb_max_pages
		info.max_pages_nomemless = g13_tvb_max_blocks_nomemless * fw.g13_tvb_pages_per_block
		mut stats := &fw.G13BufferStats(buffer.stats.cpu_address())
		stats.reset = 1
	}
	buffer.initialized = true
	complete = true
	return true
}

// Grow the queue's TVB to the minimum needed by a scene. The page and block
// tables are updated only after every new block has a valid, acknowledged UAT
// mapping, so firmware never observes a half-committed heap extension.
fn (mut mgr GpuManager) ensure_g13_tvb_blocks(mut buffer G13RenderBufferResources,
	minimum u32, firmware_active bool) bool {
	if !buffer.initialized || buffer.context == unsafe { nil } || minimum == 0
		|| minimum > g13_tvb_max_blocks || u32(buffer.blocks.len) >= minimum {
		return buffer.initialized && u32(buffer.blocks.len) >= minimum
	}
	mut context := unsafe { buffer.context }
	for u32(buffer.blocks.len) < minimum {
		block := context.alloc_driver_buffer_aligned(fw.g13_tvb_block_size, false, fw.g13_tvb_page_size) or {
			return false
		}
		if !mgr.flush_g13_uat_range(context.id, block.va, block.size) {
			context.release_driver_buffer(block)
			return false
		}
		index := u32(buffer.blocks.len)
		unsafe {
			mut pages := &u32(buffer.page_list.cpu_address())
			mut blocks := &u32(buffer.block_list.cpu_address())
			page_number := u32(block.va >> fw.g13_tvb_page_shift)
			blocks[index * 2] = page_number
			for page := u32(0); page < fw.g13_tvb_pages_per_block; page++ {
				pages[index * fw.g13_tvb_pages_per_block + page] = page_number + page
			}
			buffer.blocks << block
			new_count := index + 1
			page_count := new_count * fw.g13_tvb_pages_per_block
			// Publishing wptr last makes all newly populated table entries visible
			// before firmware is allowed to allocate from the added block.
			mut control := &fw.G13BufferBlockControl(buffer.block_control.cpu_address())
			katomic.store(mut &control.total, new_count)
			katomic.store(mut &control.wptr, new_count)
			// During a GrowTVB request firmware owns the active Info counters. It
			// learns about added blocks exclusively through BlockControl.
			if !firmware_active {
				mut info := &fw.G13BufferInfo(buffer.info.cpu_address())
				katomic.store(mut &info.page_count, page_count)
				katomic.store(mut &info.block_count, new_count)
				katomic.store(mut &info.last_page, page_count - 1)
			}
		}
	}
	return true
}

// Service firmware's synchronous tiled-buffer growth request. The ACK is
// required even if the slot cannot be grown, otherwise the firmware remains
// blocked forever waiting for device control.
fn (mut mgr GpuManager) handle_g13_grow_tvb(event_msg &fw.FwGrowTVBEvent) {
	if event_msg == unsafe { nil } {
		return
	}
	mgr.lock.acquire()
	defer {
		mgr.lock.release()
	}
	if mgr.state != .running || mgr.hw_config.gpu_gen != .g13 {
		return
	}

	mut found := false
	mut grew := false
	if event_msg.buffer_slot < fw.g13_tvb_slot_count && event_msg.vm_slot != 0 {
		for resources in mgr.g13_queues {
			if resources.released || resources.vm == unsafe { nil }
				|| resources.vm.id != event_msg.vm_slot || !resources.render_buffer.initialized
				|| resources.render_buffer.slot != event_msg.buffer_slot {
				continue
			}
			found = true
			mut buffer := unsafe { &resources.render_buffer }
			current := u32(buffer.blocks.len)
			target := if current > g13_tvb_max_blocks - u32(10) {
				g13_tvb_max_blocks
			} else {
				current + u32(10)
			}
			if target > current {
				grew = mgr.ensure_g13_tvb_blocks(mut buffer, target, true)
			}
			break
		}
	}
	if !found {
		C.printf(c'agx: GrowTVB requested unknown slot=%u vm=%u\n', event_msg.buffer_slot, event_msg.vm_slot)
	} else if !grew {
		C.printf(c'agx: failed to grow TVB slot=%u vm=%u\n', event_msg.buffer_slot, event_msg.vm_slot)
	}

	ack := fw.make_grow_tvb_ack(event_msg.buffer_slot, event_msg.vm_slot, event_msg.counter)
	if !mgr.channels.device_ctrl.enqueue(voidptr(&ack)) || !mgr.ring_device_control() {
		C.printf(c'agx: failed to acknowledge GrowTVB slot=%u vm=%u\n', event_msg.buffer_slot, event_msg.vm_slot)
		mgr.state = .error
	}
}

// Allocate the two event-counter arrays in their correct cacheability classes.
// This runs after the UAT exists but before either firmware or DRM queues start.
pub fn (mut mgr GpuManager) initialize_g13_event_resources() bool {
	mgr.lock.acquire()
	defer {
		mgr.lock.release()
	}
	if mgr.state != .idle || mgr.hw_config.gpu_gen != .g13 || mgr.g13_events.initialized {
		return false
	}
	bytes := u64(event.max_stamps) * event.stamp_size
	mgr.g13_events.driver_stamps = mgr.alloc_g13_shared_buffer(bytes) or { return false }
	mgr.g13_events.firmware_stamps = mgr.alloc_g13_buffer_with_protection(bytes, pgtable.gpu_prot_fw_private_rw) or {
		mgr.free_shared_buffer(mut mgr.g13_events.driver_stamps)
		return false
	}
	if !event.configure_event_manager(mgr.g13_events.driver_stamps.va, mgr.g13_events.driver_stamps.phys, mgr.g13_events.firmware_stamps.va, mgr.g13_events.firmware_stamps.phys) {
		mgr.free_shared_buffer(mut mgr.g13_events.firmware_stamps)
		mgr.free_shared_buffer(mut mgr.g13_events.driver_stamps)
		return false
	}
	mgr.g13_events.initialized = true
	return true
}

// Caller holds mgr.lock or owns the unpublished manager.
fn (mut mgr GpuManager) release_g13_event_resources_locked() {
	if !mgr.g13_events.initialized {
		return
	}
	event.reset_event_manager()
	mgr.free_shared_buffer(mut mgr.g13_events.firmware_stamps)
	mgr.free_shared_buffer(mut mgr.g13_events.driver_stamps)
	mgr.g13_events.initialized = false
	mgr.g13_private.gc()
	mgr.g13_shared.gc()
}

fn (mut mgr GpuManager) initialize_g13_subqueue(mut resources G13QueueResources,
	pipe_type u32) bool {
	if pipe_type >= 3 || resources.channel_mask & (u32(1) << pipe_type) == 0 {
		return false
	}
	mut queue := &resources.subqueues[pipe_type]
	queue.pipe_type = pipe_type
	queue.gpu_buffer = mgr.alloc_g13_buffer_with_protection(fw.g13_gpu_buffer_size, pgtable.gpu_prot_fw_private_rw) or { return false }
	queue.state = mgr.alloc_g13_shared_buffer(sizeof(fw.G13WorkQueueRingState)) or {
		return false
	}
	queue.ring = mgr.alloc_g13_shared_buffer(u64(fw.g13_workqueue_entries) * sizeof(u64)) or {
		return false
	}
	queue.info = mgr.alloc_g13_buffer_with_protection(sizeof(fw.G13WorkQueueInfo), pgtable.gpu_prot_fw_private_rw) or { return false }
	priority := fw.g13_workqueue_priority(resources.priority) or { return false }
	unsafe {
		mut state := &fw.G13WorkQueueRingState(queue.state.cpu_address())
		state.rb_size = fw.g13_workqueue_entries
		mut info := &fw.G13WorkQueueInfo(queue.info.cpu_address())
		info.state = queue.state.va
		info.ring = queue.ring.va
		info.notifier_list = resources.notifier_list.va
		info.gpu_buffer = queue.gpu_buffer.va
		info.event_id = -1
		info.priority = priority
		info.unk_4c = -1
		info.uuid = resources.queue_id
		info.unk_54 = -1
		info.gpu_context = resources.context.va
	}
	queue.is_new = true
	return true
}

fn (mut mgr GpuManager) invalidate_g13_queue_mappings_locked(mut resources G13QueueResources) bool {
	if mgr.state != .running || resources.vm == unsafe { nil } || !resources.vm.active {
		return false
	}
	mut context := unsafe { resources.vm }
	mut buffer := &resources.render_buffer
	if buffer.initialized {
		for block in buffer.blocks {
			if !context.unmap_driver_buffer(block) {
				return false
			}
		}
		if !context.unmap_driver_buffer(buffer.block_list)
			|| !context.unmap_driver_buffer(buffer.page_list) {
			return false
		}
		unmap_shared_buffer(mut buffer.kernel_buffer)
		unmap_shared_buffer(mut buffer.stats)
		unmap_shared_buffer(mut buffer.counter)
		unmap_shared_buffer(mut buffer.block_control)
		unmap_shared_buffer(mut buffer.info)
	}
	for pipe_type := u32(0); pipe_type < 3; pipe_type++ {
		if resources.channel_mask & (u32(1) << pipe_type) == 0 {
			continue
		}
		mut queue := &resources.subqueues[pipe_type]
		unmap_shared_buffer(mut queue.info)
		unmap_shared_buffer(mut queue.ring)
		unmap_shared_buffer(mut queue.state)
		unmap_shared_buffer(mut queue.gpu_buffer)
	}
	unmap_shared_buffer(mut resources.notifier)
	unmap_shared_buffer(mut resources.threshold)
	unmap_shared_buffer(mut resources.notifier_list)
	unmap_shared_buffer(mut resources.context)

	if buffer.initialized {
		for block in buffer.blocks {
			if !mgr.flush_g13_uat_range(context.id, block.va, block.size) {
				return false
			}
		}
		if !mgr.flush_g13_uat_range(context.id, buffer.block_list.va, buffer.block_list.size)
			|| !mgr.flush_g13_uat_range(context.id, buffer.page_list.va, buffer.page_list.size)
			|| !mgr.flush_g13_uat_range(mmu.uat_kernel_flush_slot, buffer.kernel_buffer.va, buffer.kernel_buffer.size)
			|| !mgr.flush_g13_uat_range(mmu.uat_kernel_flush_slot, buffer.stats.va, buffer.stats.size)
			|| !mgr.flush_g13_uat_range(mmu.uat_kernel_flush_slot, buffer.counter.va, buffer.counter.size)
			|| !mgr.flush_g13_uat_range(mmu.uat_kernel_flush_slot, buffer.block_control.va, buffer.block_control.size)
			|| !mgr.flush_g13_uat_range(mmu.uat_kernel_flush_slot, buffer.info.va, buffer.info.size) {
			return false
		}
	}
	for pipe_type := u32(0); pipe_type < 3; pipe_type++ {
		if resources.channel_mask & (u32(1) << pipe_type) == 0 {
			continue
		}
		queue := &resources.subqueues[pipe_type]
		if !mgr.flush_g13_uat_range(mmu.uat_kernel_flush_slot, queue.info.va, queue.info.size)
			|| !mgr.flush_g13_uat_range(mmu.uat_kernel_flush_slot, queue.ring.va, queue.ring.size)
			|| !mgr.flush_g13_uat_range(mmu.uat_kernel_flush_slot, queue.state.va, queue.state.size)
			|| !mgr.flush_g13_uat_range(mmu.uat_kernel_flush_slot, queue.gpu_buffer.va, queue.gpu_buffer.size) {
			return false
		}
	}
	return mgr.flush_g13_uat_range(mmu.uat_kernel_flush_slot, resources.notifier.va, resources.notifier.size)
		&& mgr.flush_g13_uat_range(mmu.uat_kernel_flush_slot, resources.threshold.va, resources.threshold.size)
		&& mgr.flush_g13_uat_range(mmu.uat_kernel_flush_slot, resources.notifier_list.va, resources.notifier_list.size)
		&& mgr.flush_g13_uat_range(mmu.uat_kernel_flush_slot, resources.context.va, resources.context.size)
}

fn (mut mgr GpuManager) free_g13_queue_resources_locked(mut resources G13QueueResources,
	invalidate bool) bool {
	if resources.released {
		return true
	}
	if invalidate && !mgr.invalidate_g13_queue_mappings_locked(mut resources) {
		return false
	}
	resources.released = true
	mgr.free_g13_render_buffer_locked(mut resources.render_buffer)
	for index := 2; index >= 0; index-- {
		mut queue := &resources.subqueues[index]
		queue.lock.acquire()
		mgr.free_shared_buffer(mut queue.info)
		mgr.free_shared_buffer(mut queue.ring)
		mgr.free_shared_buffer(mut queue.state)
		mgr.free_shared_buffer(mut queue.gpu_buffer)
		queue.lock.release()
	}
	mgr.free_shared_buffer(mut resources.notifier)
	mgr.free_shared_buffer(mut resources.threshold)
	mgr.free_shared_buffer(mut resources.notifier_list)
	mgr.free_shared_buffer(mut resources.context)
	mgr.g13_private.gc()
	mgr.g13_shared.gc()
	return true
}

// Publish a complete command batch into a queue-owned ring, then emit one
// RunWorkQueue message containing the final write pointer. InitBuffer+Vertex
// and Barrier+Fragment must become visible atomically as pairs. Holding the
// outer ring lock across both publications prevents a full outer ring from
// stranding already-visible inner commands.
fn (mut mgr GpuManager) submit_g13_queue_commands(resources &G13QueueResources,
	pipe_type u32, command_vas []u64, event_slot u32) bool {
	if resources == unsafe { nil } || resources.released || mgr.state != .running
		|| mgr.hw_config.gpu_gen != .g13 || pipe_type >= 3 || command_vas.len == 0
		|| command_vas.len >= int(fw.g13_workqueue_entries)
		|| event_slot >= event.max_stamps
		|| resources.channel_mask & (u32(1) << pipe_type) == 0
		|| resources.priority >= 4 {
		return false
	}
	for command_va in command_vas {
		if !((command_va >= alloc.g13_gpu_readonly_start
			&& command_va < alloc.g13_gpu_readonly_end)
			|| (command_va >= alloc.g13_private_start && command_va < alloc.g13_private_end)) {
			return false
		}
	}
	outer_index := pipe_index(resources.priority, pipe_type)
	mut outer := &mgr.channels.pipes[outer_index]
	outer.lock.acquire()
	if outer.ring_size == 0 || outer.entry_size != sizeof(fw.FwRunWorkQueueMsg)
		|| outer.state_phys == 0 || outer.ring_phys == 0 {
		outer.lock.release()
		return false
	}
	outer_read := unsafe { &u32(outer.state_phys + higher_half) }
	mut outer_write := unsafe { &u32(outer.state_phys + higher_half + outer.write_off) }
	outer_wp := katomic.load(outer_write)
	outer_rp := katomic.load(outer_read)
	outer_next := (outer_wp + 1) % outer.ring_size
	if outer_next == outer_rp {
		outer.lock.release()
		return false
	}

	mut owned := unsafe { resources }
	mut queue := &owned.subqueues[pipe_type]
	queue.lock.acquire()
	if owned.released || queue.state.phys == 0 || queue.ring.phys == 0 || queue.info.va == 0 {
		queue.lock.release()
		outer.lock.release()
		return false
	}
	mut state := unsafe { &fw.G13WorkQueueRingState(queue.state.cpu_address()) }
	inner_wp := katomic.load(&state.cpu_wptr)
	inner_done := katomic.load(&state.gpu_doneptr)
	inner_used := (inner_wp + fw.g13_workqueue_entries - inner_done) % fw.g13_workqueue_entries
	inner_free := fw.g13_workqueue_entries - inner_used - 1
	if u32(command_vas.len) > inner_free {
		queue.lock.release()
		outer.lock.release()
		return false
	}
	mut inner_next := inner_wp
	for command_va in command_vas {
		unsafe {
			mut entry := &u64(queue.ring.phys + higher_half + u64(inner_next) * sizeof(u64))
			*entry = command_va
		}
		inner_next = (inner_next + 1) % fw.g13_workqueue_entries
	}
	katomic.store(mut &state.cpu_wptr, inner_next)

	message := fw.FwRunWorkQueueMsg{
		pipe_type: pipe_type
		work_queue_addr: queue.info.va
		write_ptr: inner_next
		event_slot: event_slot
		is_new: if queue.is_new { u8(1) } else { u8(0) }
	}
	unsafe {
		destination := voidptr(outer.ring_phys + higher_half + u64(outer_wp) * outer.entry_size)
		C.memcpy(destination, &message, sizeof(fw.FwRunWorkQueueMsg))
	}
	katomic.store(mut outer_write, outer_next)
	queue.is_new = false
	queue.lock.release()
	outer.lock.release()
	if !mgr.ring_pipe(resources.priority, pipe_type) {
		// Both rings already own the command at this point. Keep reporting the
		// ownership transfer as successful so the caller retains its backing,
		// but stop further submissions because firmware was not notified.
		C.printf(c'agx: failed to ring G13 work-pipe doorbell\n')
		mgr.state = .error
	}
	return true
}

fn (mut mgr GpuManager) submit_g13_queue_command(resources &G13QueueResources,
	pipe_type u32, command_va u64, event_slot u32) bool {
	return mgr.submit_g13_queue_commands(resources, pipe_type, [command_va], event_slot)
}

fn build_g13_attachments(count u32,
	input [16]agxcommand.Attachment) ?fw.G13MicroseqAttachments {
	if count > fw.g13_max_attachments {
		return none
	}
	mut attachments := fw.G13MicroseqAttachments{}
	for index := u32(0); index < count; index++ {
		attachment := input[index]
		if attachment.order < 1 || attachment.order > 6 {
			return none
		}
		attachments.list[index] = fw.G13MicroseqAttachment{
			address: attachment.address
			size: attachment.cache_lines
			unk_c: 0x17
			unk_e: attachment.order
		}
	}
	attachments.count = count
	return attachments
}

fn (mut mgr GpuManager) release_g13_render_scene_backing_locked(mut scene G13RenderSceneResources,
	ctx &mmu.UatContext, unmapped bool) {
	if ctx != unsafe { nil } {
		mut context := unsafe { ctx }
		context.release_driver_buffer(scene.aux_framebuffer)
		context.release_driver_buffer(scene.preempt)
		context.release_driver_buffer(scene.tail_pointer_cache)
		context.release_driver_buffer(scene.tilemap)
		context.release_driver_buffer(scene.heapmeta)
		context.release_driver_buffer(scene.user_buffer)
	}
	if unmapped {
		mgr.release_shared_buffer_backing(mut scene.timestamps)
		mgr.release_shared_buffer_backing(mut scene.scene)
	} else {
		mgr.free_shared_buffer(mut scene.timestamps)
		mgr.free_shared_buffer(mut scene.scene)
	}
	scene = G13RenderSceneResources{}
	mgr.g13_shared.gc()
}

fn (mut mgr GpuManager) free_g13_render_scene_locked(mut scene G13RenderSceneResources,
	ctx &mmu.UatContext) {
	mgr.release_g13_render_scene_backing_locked(mut scene, ctx, false)
}

fn (mut mgr GpuManager) allocate_g13_render_scene_locked(resources &G13QueueResources,
	tile &G13TileInfo) ?G13RenderSceneResources {
	if resources == unsafe { nil } || resources.vm == unsafe { nil }
		|| !resources.render_buffer.initialized || mgr.hw_config.num_clusters != 1 {
		return none
	}
	mut buffer := unsafe { &resources.render_buffer }
	if !mgr.ensure_g13_tvb_blocks(mut buffer, tile.min_tvb_blocks, false) {
		return none
	}
	ctx := resources.vm
	mut context := unsafe { ctx }
	mut scene := G13RenderSceneResources{}
	mut complete := false
	defer {
		if !complete {
			mgr.free_g13_render_scene_locked(mut scene, ctx)
		}
	}
	scene.user_buffer = context.alloc_driver_buffer_aligned(0x80, false, fw.g13_tvb_page_size) or { return none }
	scene.heapmeta = context.alloc_driver_buffer_aligned(0x200 + tile.layermeta_size, false, fw.g13_tvb_page_size) or {
		return none
	}
	scene.tilemap = context.alloc_driver_buffer_aligned(tile.tilemap_size, false, fw.g13_tvb_page_size) or { return none }
	scene.tail_pointer_cache = context.alloc_driver_buffer_aligned(tile.tail_pointer_size, true, fw.g13_tvb_page_size) or {
		return none
	}
	preempt_size := mgr.hw_config.preempt1_size + mgr.hw_config.preempt2_size + mgr.hw_config.preempt3_size
	scene.preempt = context.alloc_driver_buffer_aligned(preempt_size, false, fw.g13_tvb_page_size) or { return none }
	scene.aux_framebuffer = context.alloc_driver_buffer_aligned(0x8000, false, fw.g13_tvb_page_size) or { return none }
	scene.scene = mgr.alloc_g13_shared_buffer(sizeof(fw.G13BufferScene)) or { return none }
	scene.timestamps = mgr.alloc_g13_shared_buffer(sizeof(fw.G13RenderTimestamps)) or {
		return none
	}
	unsafe {
		mut raw := &fw.G13BufferScene(scene.scene.cpu_address())
		raw.user_buffer = scene.user_buffer.va
		raw.stats = resources.render_buffer.stats.va
	}
	complete = true
	return scene
}

fn (mut mgr GpuManager) free_g13_render_job_locked(mut job G13RenderJobResources,
	invalidate bool) bool {
	if job.released {
		return true
	}
	if invalidate {
		if mgr.state != .running || job.context == unsafe { nil } || !job.context.active {
			return false
		}
		mut context := unsafe { job.context }
		if !context.unmap_driver_buffer(job.scene.aux_framebuffer)
			|| !context.unmap_driver_buffer(job.scene.preempt)
			|| !context.unmap_driver_buffer(job.scene.tail_pointer_cache)
			|| !context.unmap_driver_buffer(job.scene.tilemap)
			|| !context.unmap_driver_buffer(job.scene.heapmeta)
			|| !context.unmap_driver_buffer(job.scene.user_buffer) {
			return false
		}
		unmap_shared_buffer(mut job.fragment)
		unmap_shared_buffer(mut job.vertex)
		unmap_shared_buffer(mut job.barrier)
		unmap_shared_buffer(mut job.init_buffer)
		unmap_shared_buffer(mut job.fragment_microsequence)
		unmap_shared_buffer(mut job.vertex_microsequence)
		unmap_shared_buffer(mut job.scene.timestamps)
		unmap_shared_buffer(mut job.scene.scene)
		// Every per-scene and context-zero translation must be acknowledged as
		// gone before any of its physical backing can return to the PMM.
		if !mgr.flush_g13_uat_range(context.id, job.scene.aux_framebuffer.va, job.scene.aux_framebuffer.size)
			|| !mgr.flush_g13_uat_range(context.id, job.scene.preempt.va, job.scene.preempt.size)
			|| !mgr.flush_g13_uat_range(context.id, job.scene.tail_pointer_cache.va, job.scene.tail_pointer_cache.size)
			|| !mgr.flush_g13_uat_range(context.id, job.scene.tilemap.va, job.scene.tilemap.size)
			|| !mgr.flush_g13_uat_range(context.id, job.scene.heapmeta.va, job.scene.heapmeta.size)
			|| !mgr.flush_g13_uat_range(context.id, job.scene.user_buffer.va, job.scene.user_buffer.size)
			|| !mgr.flush_g13_uat_range(mmu.uat_kernel_flush_slot, job.fragment.va, job.fragment.size)
			|| !mgr.flush_g13_uat_range(mmu.uat_kernel_flush_slot, job.vertex.va, job.vertex.size)
			|| !mgr.flush_g13_uat_range(mmu.uat_kernel_flush_slot, job.barrier.va, job.barrier.size)
			|| !mgr.flush_g13_uat_range(mmu.uat_kernel_flush_slot, job.init_buffer.va, job.init_buffer.size)
			|| !mgr.flush_g13_uat_range(mmu.uat_kernel_flush_slot, job.fragment_microsequence.va, job.fragment_microsequence.size)
			|| !mgr.flush_g13_uat_range(mmu.uat_kernel_flush_slot, job.vertex_microsequence.va, job.vertex_microsequence.size)
			|| !mgr.flush_g13_uat_range(mmu.uat_kernel_flush_slot, job.scene.timestamps.va, job.scene.timestamps.size)
			|| !mgr.flush_g13_uat_range(mmu.uat_kernel_flush_slot, job.scene.scene.va, job.scene.scene.size) {
			return false
		}
	}
	job.released = true
	if job.vertex_event_reserved {
		event.release_stamp(job.vertex_event_slot)
		job.vertex_event_reserved = false
	}
	if job.fragment_event_reserved {
		event.release_stamp(job.fragment_event_slot)
		job.fragment_event_reserved = false
	}
	if invalidate {
		mgr.release_shared_buffer_backing(mut job.fragment)
		mgr.release_shared_buffer_backing(mut job.vertex)
		mgr.release_shared_buffer_backing(mut job.barrier)
		mgr.release_shared_buffer_backing(mut job.init_buffer)
		mgr.release_shared_buffer_backing(mut job.fragment_microsequence)
		mgr.release_shared_buffer_backing(mut job.vertex_microsequence)
	} else {
		mgr.free_shared_buffer(mut job.fragment)
		mgr.free_shared_buffer(mut job.vertex)
		mgr.free_shared_buffer(mut job.barrier)
		mgr.free_shared_buffer(mut job.init_buffer)
		mgr.free_shared_buffer(mut job.fragment_microsequence)
		mgr.free_shared_buffer(mut job.vertex_microsequence)
	}
	mgr.release_g13_render_scene_backing_locked(mut job.scene, job.context, invalidate)
	if job.queue != unsafe { nil } {
		mut queue := unsafe { job.queue }
		queue.render_job_active = false
	}
	mgr.g13_gpu_readonly.gc()
	mgr.g13_private.gc()
	mgr.g13_shared.gc()
	return true
}

fn complete_g13_render_job(mut job G13RenderJobResources, successful bool) {
	if job.completion == unsafe { nil } {
		return
	}
	callback := job.completion
	data := job.completion_data
	job.completion = unsafe { nil }
	job.completion_data = unsafe { nil }
	callback(job, successful, data)
}

// Construct the complete paired vertex/tiler and fragment object graph for a
// single-cluster G13 render pass. It remains unpublished until
// submit_g13_render_job() transfers both queue batches to firmware.
pub fn (mut mgr GpuManager) prepare_g13_render_job(resources &G13QueueResources,
	input &agxrender.Command) ?&G13RenderJobResources {
	if resources == unsafe { nil } || resources.released || resources.vm == unsafe { nil }
		|| !resources.vm.active || resources.channel_mask & g13_queue_channel_vertex == 0
		|| resources.channel_mask & g13_queue_channel_fragment == 0
		|| input.flags & ~agxrender.supported_flags != 0 || mgr.hw_config.num_clusters != 1
		|| !fw.validate_g13_vertex_layouts() || !fw.validate_g13_fragment_layouts()
		|| !fw.validate_g13_buffer_layouts() || !fw.validate_g13_microsequence_layouts() {
		return none
	}
	vertex_attachments := build_g13_attachments(input.vertex_attachment_count, input.vertex_attachments) or { return none }
	fragment_attachments := build_g13_attachments(input.fragment_attachment_count, input.fragment_attachments) or { return none }
	tile := g13_tile_info(input.framebuffer_width, input.framebuffer_height, input.layers, input.utile_width, input.utile_height, input.samples, input.ppp_control, input.vertex_helper_cfg) or { return none }

	mgr.lock.acquire()
	defer {
		mgr.lock.release()
	}
	if mgr.state != .running || mgr.hw_config.gpu_gen != .g13
		|| mgr.g13_channels == unsafe { nil } || resources.released
		|| resources.render_job_active {
		return none
	}
	mut queue := unsafe { resources }
	queue.render_job_active = true
	mut job := &G13RenderJobResources{
		queue: unsafe { resources }
		context: unsafe { resources.vm }
	}
	mut complete := false
	defer {
		if !complete {
			if !mgr.free_g13_render_job_locked(mut job, job.mappings_published) {
				job.quarantined = true
				mgr.g13_render_jobs << job
			}
		}
	}
	job.vertex_event_slot = event.reserve_stamp() or { return none }
	job.vertex_event_reserved = true
	job.fragment_event_slot = event.reserve_stamp() or { return none }
	job.fragment_event_reserved = true
	job.vertex_stamp_value = event.advance_stamp(job.vertex_event_slot) or { return none }
	job.fragment_stamp_value = event.advance_stamp(job.fragment_event_slot) or { return none }
	job.vertex_event_sequence = queue.event_sequences[0]
	queue.event_sequences[0]++
	job.fragment_event_sequence = queue.event_sequences[1]
	queue.event_sequences[1]++
	job.scene = mgr.allocate_g13_render_scene_locked(resources, &tile) or { return none }
	job.tvb_size_bytes = u64(resources.render_buffer.blocks.len) * fw.g13_tvb_block_size

	job.init_buffer = mgr.alloc_g13_buffer_with_protection(sizeof(fw.G13InitBufferCommand), pgtable.gpu_prot_fw_private_rw) or { return none }
	job.barrier = mgr.alloc_g13_buffer_with_protection(sizeof(fw.G13BarrierCommand), pgtable.gpu_prot_fw_private_rw) or { return none }
	job.vertex = mgr.alloc_g13_buffer_with_protection(sizeof(fw.G13RunVertex), pgtable.gpu_prot_gpu_ro_fw_private_rw) or { return none }
	job.fragment = mgr.alloc_g13_buffer_with_protection(sizeof(fw.G13RunFragment), pgtable.gpu_prot_gpu_ro_fw_private_rw) or { return none }
	vertex_microsequence_size := if input.has_result { u64(0x260) } else { u64(0x1f8) }
	fragment_microsequence_size := if input.has_result { u64(0x2a0) } else { u64(0x238) }
	job.vertex_microsequence = mgr.alloc_g13_buffer_with_protection(vertex_microsequence_size, pgtable.gpu_prot_fw_private_rw) or { return none }
	job.fragment_microsequence = mgr.alloc_g13_buffer_with_protection(fragment_microsequence_size, pgtable.gpu_prot_fw_private_rw) or { return none }

	ctx := resources.vm
	buffer := &resources.render_buffer
	vertex_queue := &resources.subqueues[0]
	fragment_queue := &resources.subqueues[1]
	if buffer.info.va == 0 || buffer.kernel_buffer.va == 0 || vertex_queue.info.va == 0
		|| fragment_queue.info.va == 0 || mgr.g13_channels.stats_vertex.va == 0
		|| mgr.g13_channels.stats_fragment.va == 0 {
		return none
	}
	tile_config := u64(0x280) | if input.layers > 1 { u64(1) } else { u64(0) } | if input.flags & agxrender.process_empty_tiles != 0 {
		u64(0x10000)
	} else {
		u64(0)
	}
	preempt_2 := job.scene.preempt.va + mgr.hw_config.preempt1_size
	preempt_3 := preempt_2 + mgr.hw_config.preempt2_size
	aux_info := fw.G13AuxFramebufferInfo{
		iogpu_unk_214: input.iogpu_unk_214
		width: input.framebuffer_width
		height: input.framebuffer_height
	}
	unsafe {
		mut init := &fw.G13InitBufferCommand(job.init_buffer.cpu_address())
		*init = fw.G13InitBufferCommand{
			tag: fw.cmd_type_init_buffer
			vm_slot: ctx.id
			buffer_slot: buffer.slot
			block_count: u32(buffer.blocks.len)
			buffer: buffer.info.va
			stamp_value: job.vertex_stamp_value
		}
		mut barrier := &fw.G13BarrierCommand(job.barrier.cpu_address())
		*barrier = fw.G13BarrierCommand{
			tag: fw.cmd_type_barrier
			wait_stamp: event.firmware_stamp_address(job.vertex_event_slot)
			wait_value: job.vertex_stamp_value
			wait_slot: job.vertex_event_slot
			stamp_self: job.fragment_stamp_value
			uuid: input.fragment_command_id
		}

		mut vertex := &fw.G13RunVertex(job.vertex.cpu_address())
		*vertex = fw.G13RunVertex{
			tag: fw.cmd_type_run_vertex
			vm_slot: ctx.id
			notifier: resources.notifier.va
			buffer_slot: buffer.slot
			buffer: buffer.info.va
			scene: job.scene.scene.va
			unk_buffer: buffer.kernel_buffer.va
			job_params_1: fw.G13VertexJobParameters1{
				unk_0: 0x200
				unk_8: 0x1e3ce508
				unk_c: 0x1e3ce508
				tvb_tilemap: job.scene.tilemap.va
				tail_pointer_cache: job.scene.tail_pointer_cache.va
				tvb_heapmeta: job.scene.heapmeta.va | u64(0x8000000000000000)
				iogpu_unk_54: 0x3a0012006b0003
				iogpu_unk_56: 1
				utile_config: tile.utile_config
				ppp_multisamplectl: input.ppp_multisamplectl
				tvb_layermeta: job.scene.heapmeta.va + u64(0x200)
				preempt_buf_1: job.scene.preempt.va
				preempt_buf_2: preempt_2
				unk_80: 1
				preempt_buf_3: preempt_3 | u64(0x4000000000000)
				encoder: input.encoder_ptr
				tiling_control: mgr.hw_config.render_tiling_control
				pipeline_base: input.vertex_usc_base
				unk_f0: 0x1c
				unk_f8: 0x8c60
				helper_program: input.vertex_helper_program
				helper_arg: input.vertex_helper_arg
				unk_118: 0x1c
			}
			tiling_params: tile.params
			tail_pointer_cache: job.scene.tail_pointer_cache.va
			tail_pointer_size: tile.tail_pointer_size
			microsequence: job.vertex_microsequence.va
			microsequence_size: u32(vertex_microsequence_size)
			fragment_stamp_slot: job.fragment_event_slot
			fragment_stamp_value: job.fragment_stamp_value
			job_params_2: fw.G13VertexJobParameters2{
				preempt_buf_1: job.scene.preempt.va
			}
			encoder_params: fw.G13EncoderParams{
				encoder_id: input.encoder_id
				unk_mask: 0xffffffff
				sampler_array: input.vertex_sampler_array
				sampler_count: input.vertex_sampler_count
				sampler_max: input.vertex_sampler_max
			}
			spills: if input.flags & agxrender.vertex_spills != 0 { u32(1) } else { u32(0) }
			meta: fw.G13JobMeta{
				no_preemption: if input.flags & agxrender.no_preemption != 0 {
					u8(1)
				} else {
					u8(0)
				}
				stamp: event.driver_stamp_address(job.vertex_event_slot)
				fw_stamp: event.firmware_stamp_address(job.vertex_event_slot)
				stamp_value: job.vertex_stamp_value
				stamp_slot: job.vertex_event_slot
				flush_stamps: if input.flush_stamps { u32(1) } else { u32(0) }
				uuid: input.vertex_command_id
				event_sequence: u32(job.vertex_event_sequence)
			}
			start_ts: job.scene.timestamps.va
			end_ts: job.scene.timestamps.va + u64(8)
			client_sequence: u8(resources.queue_id & 0xff)
		}
		vertex.job_params_1.core_mask[0] = mgr.hw_config.core_mask_list[0]

		mut fragment := &fw.G13RunFragment(job.fragment.cpu_address())
		*fragment = fw.G13RunFragment{
			tag: fw.cmd_type_run_fragment
			vm_slot: ctx.id
			microsequence: job.fragment_microsequence.va
			microsequence_size: u32(fragment_microsequence_size)
			notifier: resources.notifier.va
			buffer: buffer.info.va
			scene: job.scene.scene.va
			unk_buffer: buffer.kernel_buffer.va
			tvb_tilemap: job.scene.tilemap.va
			ppp_multisamplectl: input.ppp_multisamplectl
			samples: input.samples
			tiles_per_mtile_y: u16(tile.tiles_per_mtile_y)
			tiles_per_mtile_x: u16(tile.tiles_per_mtile_x)
			merge_upper_x: input.merge_upper_x
			merge_upper_y: input.merge_upper_y
			tile_count: tile.tiles
			job_params_1: fw.G13FragmentJobParameters1{
				utile_config: tile.utile_config
				clear_pipeline: fw.G13ClearPipelineBinding{
					pipeline_bind: input.load_pipeline_bind
					address: input.load_pipeline
				}
				ppp_multisamplectl: input.ppp_multisamplectl
				scissor_array: input.scissor_array
				depth_bias_array: input.depth_bias_array
				aux_fb_info: aux_info
				depth_dimensions: input.depth_dimensions
				visibility_result_buffer: input.visibility_result_buffer
				zls_control: input.zls_control
				depth_buffer_ptr_1: input.depth_buffer_load
				depth_buffer_ptr_2: input.depth_buffer_store
				stencil_buffer_ptr_1: input.stencil_buffer_load
				stencil_buffer_ptr_2: input.stencil_buffer_store
				depth_buffer_stride_1: input.depth_buffer_load_stride
				depth_buffer_stride_2: input.depth_buffer_store_stride
				stencil_buffer_stride_1: input.stencil_buffer_load_stride
				stencil_buffer_stride_2: input.stencil_buffer_store_stride
				depth_meta_buffer_ptr_1: input.depth_meta_buffer_load
				depth_meta_buffer_stride_1: input.depth_meta_buffer_load_stride
				depth_meta_buffer_ptr_2: input.depth_meta_buffer_store
				depth_meta_buffer_stride_2: input.depth_meta_buffer_store_stride
				stencil_meta_buffer_ptr_1: input.stencil_meta_buffer_load
				stencil_meta_buffer_stride_1: input.stencil_meta_buffer_load_stride
				stencil_meta_buffer_ptr_2: input.stencil_meta_buffer_store
				stencil_meta_buffer_stride_2: input.stencil_meta_buffer_store_stride
				tvb_tilemap: job.scene.tilemap.va
				tvb_layermeta: job.scene.heapmeta.va + u64(0x200)
				mtile_stride_dwords: (u64(4) * tile.params.region_size) << 24
				tvb_heapmeta: job.scene.heapmeta.va
				tile_config: tile_config
				aux_fb: job.scene.aux_framebuffer.va
				pipeline_base: input.fragment_usc_base
				unk_140: 0x8c60
				helper_program: input.fragment_helper_program
				helper_arg: input.fragment_helper_arg
				unk_158: 0x1c
			}
			job_params_2: fw.G13FragmentJobParameters2{
				store_pipeline_bind: input.store_pipeline_bind
				store_pipeline_addr: input.store_pipeline
				merge_upper_x: input.merge_upper_x
				merge_upper_y: input.merge_upper_y
				utiles_per_mtile_y: u16(tile.utiles_per_mtile_y)
				utiles_per_mtile_x: u16(tile.utiles_per_mtile_x)
				tile_counts: ((tile.tiles_y - 1) << 12) | (tile.tiles_x - 1)
				tib_blocks: input.tib_blocks
				isp_bgobjdepth: input.isp_bgobjdepth
				isp_bgobjvals: input.isp_bgobjvals | 0x400
				unk_3c: 1
				helper_cfg: input.fragment_helper_cfg
			}
			job_params_3: fw.G13FragmentJobParameters3{
				depth_bias_array: fw.G13ArrayAddress{
					pointer: input.depth_bias_array
				}
				scissor_array: fw.G13ArrayAddress{
					pointer: input.scissor_array
				}
				visibility_result_buffer: input.visibility_result_buffer
				unk_reload_pipeline: fw.G13ClearPipelineBinding{
					pipeline_bind: input.partial_reload_pipeline_bind
					address: input.partial_reload_pipeline
				}
				reload_pipeline: fw.G13ClearPipelineBinding{
					pipeline_bind: input.partial_reload_pipeline_bind
					address: input.partial_reload_pipeline
				}
				zls_control: input.zls_control
				depth_buffer_ptr_1: input.depth_buffer_load
				depth_buffer_stride_3: input.depth_buffer_partial_stride
				depth_meta_buffer_stride_3: input.depth_meta_buffer_partial_stride
				depth_buffer_ptr_2: input.depth_buffer_store
				depth_buffer_ptr_3: input.depth_buffer_partial
				depth_meta_buffer_ptr_3: input.depth_meta_buffer_partial
				stencil_buffer_ptr_1: input.stencil_buffer_load
				stencil_buffer_stride_3: input.stencil_buffer_partial_stride
				stencil_meta_buffer_stride_3: input.stencil_meta_buffer_partial_stride
				stencil_buffer_ptr_2: input.stencil_buffer_store
				stencil_buffer_ptr_3: input.stencil_buffer_partial
				stencil_meta_buffer_ptr_3: input.stencil_meta_buffer_partial
				tib_blocks: input.tib_blocks
				aux_fb_info: aux_info
				tile_config: tile_config
				unk_partial_store_pipeline: fw.g13_store_pipeline_binding(input.partial_store_pipeline_bind, input.partial_store_pipeline)
				partial_store_pipeline: fw.g13_store_pipeline_binding(input.partial_store_pipeline_bind, input.partial_store_pipeline)
				isp_bgobjdepth: input.isp_bgobjdepth
				isp_bgobjvals: input.isp_bgobjvals
				sample_size: input.sample_size
				depth_dimensions: input.depth_dimensions
			}
			encoder_params: fw.G13EncoderParams{
				unk_8: if input.flags & agxrender.set_when_reloading_z_or_s != 0 {
					u32(1)
				} else {
					u32(0)
				}
				encoder_id: input.encoder_id
				unk_mask: 0xffffffff
				sampler_array: input.fragment_sampler_array
				sampler_count: input.fragment_sampler_count
				sampler_max: input.fragment_sampler_max
			}
			process_empty_tiles: if input.flags & agxrender.process_empty_tiles != 0 {
				u32(1)
			} else {
				u32(0)
			}
			no_clear_pipeline_textures: if input.flags & agxrender.no_clear_pipeline_textures != 0 {
				u32(1)
			} else {
				u32(0)
			}
			msaa_zs: if input.flags & agxrender.msaa_zs != 0 { u32(1) } else { u32(0) }
			meta: fw.G13JobMeta{
				no_preemption: if input.flags & agxrender.no_preemption != 0 {
					u8(1)
				} else {
					u8(0)
				}
				stamp: event.driver_stamp_address(job.fragment_event_slot)
				fw_stamp: event.firmware_stamp_address(job.fragment_event_slot)
				stamp_value: job.fragment_stamp_value
				stamp_slot: job.fragment_event_slot
				flush_stamps: if input.flush_stamps { u32(1) } else { u32(0) }
				uuid: input.fragment_command_id
				event_sequence: u32(job.fragment_event_sequence)
			}
			unk_buf_10: 1
			start_ts: job.scene.timestamps.va + u64(0x10)
			end_ts: job.scene.timestamps.va + u64(0x18)
			client_sequence: u8(resources.queue_id & 0xff)
		}

		vertex_start := fw.G13MicroseqStartVertex{
			header: fw.g13_useq_start_vertex
			tiling_params: job.vertex.va + fw.g13_vertex_tiling_params_offset
			job_params_1: job.vertex.va + fw.g13_vertex_job_params_1_offset
			buffer: buffer.info.va
			scene: job.scene.scene.va
			stats: mgr.g13_channels.stats_vertex.va + u64(4)
			work_queue: vertex_queue.info.va
			vm_slot: ctx.id
			unk_38: 1
			event_generation: resources.queue_id
			buffer_slot: buffer.slot
			event_sequence: job.vertex_event_sequence
			unk_pointer: job.vertex.va + fw.g13_vertex_unk_pointee_offset
			unk_job_buffer: job.vertex.va + fw.g13_vertex_unk_buf_0_offset
			uuid: input.vertex_command_id
			attachments: vertex_attachments
			// This word is padding in the macOS 12.3 microsequence ABI. The
			// single-cluster marker only occupies it starting with 13.0 beta 4.
			unk_178: 0
		}
		mut vertex_offset := u64(0)
		C.memcpy(voidptr(job.vertex_microsequence.phys + higher_half + vertex_offset), voidptr(&vertex_start), sizeof(fw.G13MicroseqStartVertex))
		vertex_offset += sizeof(fw.G13MicroseqStartVertex)
		if input.has_result {
			vertex_ts_start := fw.G13MicroseqTimestamp{
				header: fw.g13_useq_timestamp | (u32(1) << 31)
				cur_ts: job.vertex.va + fw.g13_vertex_cur_ts_offset
				start_ts: job.vertex.va + fw.g13_vertex_start_ts_offset
				update_ts: job.vertex.va + fw.g13_vertex_start_ts_offset
				work_queue: vertex_queue.info.va
				uuid: input.vertex_command_id
			}
			C.memcpy(voidptr(job.vertex_microsequence.phys + higher_half + vertex_offset), voidptr(&vertex_ts_start), sizeof(fw.G13MicroseqTimestamp))
			vertex_offset += sizeof(fw.G13MicroseqTimestamp)
		}
		vertex_wait := fw.G13MicroseqSimpleOp{
			header: fw.g13_wait_for_idle_header(fw.g13_useq_pipe_vertex) or { return none }
		}
		C.memcpy(voidptr(job.vertex_microsequence.phys + higher_half + vertex_offset), voidptr(&vertex_wait), sizeof(fw.G13MicroseqSimpleOp))
		vertex_offset += sizeof(fw.G13MicroseqSimpleOp)
		if input.has_result {
			vertex_ts_end := fw.G13MicroseqTimestamp{
				header: fw.g13_useq_timestamp
				cur_ts: job.vertex.va + fw.g13_vertex_cur_ts_offset
				start_ts: job.vertex.va + fw.g13_vertex_start_ts_offset
				update_ts: job.vertex.va + fw.g13_vertex_end_ts_offset
				work_queue: vertex_queue.info.va
				uuid: input.vertex_command_id
			}
			C.memcpy(voidptr(job.vertex_microsequence.phys + higher_half + vertex_offset), voidptr(&vertex_ts_end), sizeof(fw.G13MicroseqTimestamp))
			vertex_offset += sizeof(fw.G13MicroseqTimestamp)
		}
		vertex_finalize := fw.G13MicroseqFinalizeVertex{
			header: fw.g13_useq_finalize_vertex
			scene: job.scene.scene.va
			buffer: buffer.info.va
			stats: mgr.g13_channels.stats_vertex.va + u64(4)
			work_queue: vertex_queue.info.va
			vm_slot: ctx.id
			unk_pointer: job.vertex.va + fw.g13_vertex_unk_pointee_offset
			uuid: input.vertex_command_id
			fw_stamp: event.firmware_stamp_address(job.vertex_event_slot)
			stamp_value: job.vertex_stamp_value
			restart_branch_offset: -i32(vertex_offset)
			has_attachments: if input.vertex_attachment_count != 0 { u32(1) } else { u32(0) }
		}
		C.memcpy(voidptr(job.vertex_microsequence.phys + higher_half + vertex_offset), voidptr(&vertex_finalize), sizeof(fw.G13MicroseqFinalizeVertex))
		vertex_offset += sizeof(fw.G13MicroseqFinalizeVertex)
		retire := fw.G13MicroseqSimpleOp{
			header: fw.g13_useq_retire_stamp
		}
		C.memcpy(voidptr(job.vertex_microsequence.phys + higher_half + vertex_offset), voidptr(&retire), sizeof(fw.G13MicroseqSimpleOp))
		vertex_offset += sizeof(fw.G13MicroseqSimpleOp)
		if vertex_offset != vertex_microsequence_size {
			return none
		}

		fragment_start := fw.G13MicroseqStartFragment{
			header: fw.g13_useq_start_fragment
			job_params_2: job.fragment.va + fw.g13_fragment_job_params_2_offset
			job_params_1: job.fragment.va + fw.g13_fragment_job_params_1_offset
			scene: job.scene.scene.va
			stats: mgr.g13_channels.stats_fragment.va + u64(8)
			busy_flag: job.fragment.va + fw.g13_fragment_busy_flag_offset
			tvb_overflow_count: job.fragment.va + fw.g13_fragment_overflow_count_offset
			unk_pointer: job.fragment.va + fw.g13_fragment_unk_pointee_offset
			work_queue: fragment_queue.info.va
			work_item: job.fragment.va
			vm_slot: ctx.id
			unk_50: 1
			event_generation: resources.queue_id
			buffer_slot: buffer.slot
			event_sequence: job.fragment_event_sequence
			unk_758_flag: job.fragment.va + fw.g13_fragment_unk_758_flag_offset
			unk_job_buffer: job.fragment.va + fw.g13_fragment_unk_buf_0_offset
			uuid: input.fragment_command_id
			attachments: fragment_attachments
		}
		mut fragment_offset := u64(0)
		C.memcpy(voidptr(job.fragment_microsequence.phys + higher_half + fragment_offset), voidptr(&fragment_start), sizeof(fw.G13MicroseqStartFragment))
		fragment_offset += sizeof(fw.G13MicroseqStartFragment)
		if input.has_result {
			fragment_ts_start := fw.G13MicroseqTimestamp{
				header: fw.g13_useq_timestamp | (u32(1) << 31)
				cur_ts: job.fragment.va + fw.g13_fragment_cur_ts_offset
				start_ts: job.fragment.va + fw.g13_fragment_start_ts_offset
				update_ts: job.fragment.va + fw.g13_fragment_start_ts_offset
				work_queue: fragment_queue.info.va
				uuid: input.fragment_command_id
			}
			C.memcpy(voidptr(job.fragment_microsequence.phys + higher_half + fragment_offset), voidptr(&fragment_ts_start), sizeof(fw.G13MicroseqTimestamp))
			fragment_offset += sizeof(fw.G13MicroseqTimestamp)
		}
		fragment_wait := fw.G13MicroseqSimpleOp{
			header: fw.g13_wait_for_idle_header(fw.g13_useq_pipe_fragment) or { return none }
		}
		C.memcpy(voidptr(job.fragment_microsequence.phys + higher_half + fragment_offset), voidptr(&fragment_wait), sizeof(fw.G13MicroseqSimpleOp))
		fragment_offset += sizeof(fw.G13MicroseqSimpleOp)
		if input.has_result {
			fragment_ts_end := fw.G13MicroseqTimestamp{
				header: fw.g13_useq_timestamp
				cur_ts: job.fragment.va + fw.g13_fragment_cur_ts_offset
				start_ts: job.fragment.va + fw.g13_fragment_start_ts_offset
				update_ts: job.fragment.va + fw.g13_fragment_end_ts_offset
				work_queue: fragment_queue.info.va
				uuid: input.fragment_command_id
			}
			C.memcpy(voidptr(job.fragment_microsequence.phys + higher_half + fragment_offset), voidptr(&fragment_ts_end), sizeof(fw.G13MicroseqTimestamp))
			fragment_offset += sizeof(fw.G13MicroseqTimestamp)
		}
		fragment_finalize := fw.G13MicroseqFinalizeFragment{
			header: fw.g13_useq_finalize_fragment
			uuid: input.fragment_command_id
			fw_stamp: event.firmware_stamp_address(job.fragment_event_slot)
			stamp_value: job.fragment_stamp_value
			scene: job.scene.scene.va
			buffer: buffer.info.va
			unk_2c: 1
			stats: mgr.g13_channels.stats_fragment.va + u64(8)
			unk_pointer: job.fragment.va + fw.g13_fragment_unk_pointee_offset
			busy_flag: job.fragment.va + fw.g13_fragment_busy_flag_offset
			work_queue: fragment_queue.info.va
			work_item: job.fragment.va
			vm_slot: ctx.id
			unk_758_flag: job.fragment.va + fw.g13_fragment_unk_758_flag_offset
			restart_branch_offset: -i32(fragment_offset)
			has_attachments: if input.fragment_attachment_count != 0 { u32(1) } else { u32(0) }
		}
		C.memcpy(voidptr(job.fragment_microsequence.phys + higher_half + fragment_offset), voidptr(&fragment_finalize), sizeof(fw.G13MicroseqFinalizeFragment))
		fragment_offset += sizeof(fw.G13MicroseqFinalizeFragment)
		C.memcpy(voidptr(job.fragment_microsequence.phys + higher_half + fragment_offset), voidptr(&retire), sizeof(fw.G13MicroseqSimpleOp))
		fragment_offset += sizeof(fw.G13MicroseqSimpleOp)
		if fragment_offset != fragment_microsequence_size {
			return none
		}
	}

	// From the first flush onward, cancellation must invalidate the complete
	// graph before its physical backing can be reused.
	job.mappings_published = true
	if !mgr.flush_g13_uat_range(ctx.id, job.scene.user_buffer.va, job.scene.user_buffer.size)
		|| !mgr.flush_g13_uat_range(ctx.id, job.scene.heapmeta.va, job.scene.heapmeta.size)
		|| !mgr.flush_g13_uat_range(ctx.id, job.scene.tilemap.va, job.scene.tilemap.size)
		|| !mgr.flush_g13_uat_range(ctx.id, job.scene.tail_pointer_cache.va, job.scene.tail_pointer_cache.size)
		|| !mgr.flush_g13_uat_range(ctx.id, job.scene.preempt.va, job.scene.preempt.size)
		|| !mgr.flush_g13_uat_range(ctx.id, job.scene.aux_framebuffer.va, job.scene.aux_framebuffer.size)
		|| !mgr.flush_g13_kernel_buffer(&job.scene.scene)
		|| !mgr.flush_g13_kernel_buffer(&job.scene.timestamps)
		|| !mgr.flush_g13_kernel_buffer(&job.init_buffer)
		|| !mgr.flush_g13_kernel_buffer(&job.barrier)
		|| !mgr.flush_g13_kernel_buffer(&job.vertex)
		|| !mgr.flush_g13_kernel_buffer(&job.fragment)
		|| !mgr.flush_g13_kernel_buffer(&job.vertex_microsequence)
		|| !mgr.flush_g13_kernel_buffer(&job.fragment_microsequence) {
		return none
	}
	complete = true
	return job
}

pub fn (mut mgr GpuManager) release_g13_render_job(job &G13RenderJobResources) {
	if job == unsafe { nil } {
		return
	}
	mgr.lock.acquire()
	mut owned := unsafe { job }
	if !owned.submitted {
		complete_g13_render_job(mut owned, false)
		if !mgr.free_g13_render_job_locked(mut owned, owned.mappings_published)
			&& !owned.quarantined {
			owned.quarantined = true
			mgr.g13_render_jobs << owned
		}
	}
	mgr.lock.release()
}

// Install the one-shot completion callback before publishing a prepared job.
// The callback runs with the manager lock held, while the firmware result
// backing is still valid. It must not call back into GpuManager.
pub fn (mut mgr GpuManager) set_g13_render_completion(job &G13RenderJobResources,
	callback fn (&G13RenderJobResources, bool, voidptr), data voidptr) bool {
	if job == unsafe { nil } || callback == unsafe { nil } {
		return false
	}
	mgr.lock.acquire()
	defer {
		mgr.lock.release()
	}
	mut owned := unsafe { job }
	if owned.released || owned.submitted || owned.quarantined
		|| owned.completion != unsafe { nil } {
		return false
	}
	owned.completion = callback
	owned.completion_data = data
	return true
}

// Publish both halves of a render pass only after all four rings have enough
// space. The fragment queue is made runnable first, matching the v12.3 Asahi
// ordering; its barrier keeps it asleep until the vertex stamp retires.
fn (mut mgr GpuManager) publish_g13_render_job_locked(mut job G13RenderJobResources) bool {
	if job.queue == unsafe { nil } || job.context == unsafe { nil } || !job.context.active
		|| job.queue.released || job.queue.priority >= 4 || mgr.state != .running
		|| mgr.g13_channels == unsafe { nil } {
		return false
	}
	queue := job.queue
	vertex_outer_index := pipe_index(queue.priority, 0)
	fragment_outer_index := pipe_index(queue.priority, 1)
	mut vertex_outer := &mgr.channels.pipes[vertex_outer_index]
	mut fragment_outer := &mgr.channels.pipes[fragment_outer_index]
	vertex_outer.lock.acquire()
	fragment_outer.lock.acquire()

	mut owned_queue := unsafe { queue }
	mut vertex_queue := &owned_queue.subqueues[0]
	mut fragment_queue := &owned_queue.subqueues[1]
	vertex_queue.lock.acquire()
	fragment_queue.lock.acquire()

	mut valid := !owned_queue.released
		&& vertex_outer.ring_size >= 2
		&& fragment_outer.ring_size >= 2
		&& vertex_outer.entry_size == sizeof(fw.FwRunWorkQueueMsg)
		&& fragment_outer.entry_size == sizeof(fw.FwRunWorkQueueMsg)
		&& vertex_outer.state_phys != 0 && vertex_outer.ring_phys != 0
		&& fragment_outer.state_phys != 0 && fragment_outer.ring_phys != 0
		&& vertex_queue.state.phys != 0 && vertex_queue.ring.phys != 0
		&& fragment_queue.state.phys != 0 && fragment_queue.ring.phys != 0
		&& vertex_queue.info.va != 0 && fragment_queue.info.va != 0

	mut vertex_outer_wp := u32(0)
	mut vertex_outer_next := u32(0)
	mut fragment_outer_wp := u32(0)
	mut fragment_outer_next := u32(0)
	mut vertex_inner_wp := u32(0)
	mut vertex_inner_next := u32(0)
	mut fragment_inner_wp := u32(0)
	mut fragment_inner_next := u32(0)
	if valid {
		vertex_outer_read := unsafe { &u32(vertex_outer.state_phys + higher_half) }
		vertex_outer_write := unsafe {
			&u32(vertex_outer.state_phys + higher_half + vertex_outer.write_off)
		}
		fragment_outer_read := unsafe { &u32(fragment_outer.state_phys + higher_half) }
		fragment_outer_write := unsafe {
			&u32(fragment_outer.state_phys + higher_half + fragment_outer.write_off)
		}
		vertex_outer_wp = katomic.load(vertex_outer_write)
		fragment_outer_wp = katomic.load(fragment_outer_write)
		vertex_outer_next = (vertex_outer_wp + 1) % vertex_outer.ring_size
		fragment_outer_next = (fragment_outer_wp + 1) % fragment_outer.ring_size
		valid = vertex_outer_next != katomic.load(vertex_outer_read)
			&& fragment_outer_next != katomic.load(fragment_outer_read)
	}
	if valid {
		vertex_state := unsafe {
			&fw.G13WorkQueueRingState(vertex_queue.state.cpu_address())
		}
		fragment_state := unsafe {
			&fw.G13WorkQueueRingState(fragment_queue.state.cpu_address())
		}
		vertex_inner_wp = katomic.load(&vertex_state.cpu_wptr)
		fragment_inner_wp = katomic.load(&fragment_state.cpu_wptr)
		vertex_done := katomic.load(&vertex_state.gpu_doneptr)
		fragment_done := katomic.load(&fragment_state.gpu_doneptr)
		vertex_used := (vertex_inner_wp + fw.g13_workqueue_entries - vertex_done) % fw.g13_workqueue_entries
		fragment_used := (fragment_inner_wp + fw.g13_workqueue_entries - fragment_done) % fw.g13_workqueue_entries
		valid = fw.g13_workqueue_entries - vertex_used - 1 >= 2
			&& fw.g13_workqueue_entries - fragment_used - 1 >= 2
		vertex_inner_next = (vertex_inner_wp + 2) % fw.g13_workqueue_entries
		fragment_inner_next = (fragment_inner_wp + 2) % fw.g13_workqueue_entries
	}
	if !valid {
		fragment_queue.lock.release()
		vertex_queue.lock.release()
		fragment_outer.lock.release()
		vertex_outer.lock.release()
		return false
	}

	unsafe {
		mut fragment_entry_0 := &u64(fragment_queue.ring.phys + higher_half + u64(fragment_inner_wp) * sizeof(u64))
		mut fragment_entry_1 := &u64(fragment_queue.ring.phys + higher_half + u64((fragment_inner_wp + 1) % fw.g13_workqueue_entries) * sizeof(u64))
		*fragment_entry_0 = job.barrier.va
		*fragment_entry_1 = job.fragment.va
		mut vertex_entry_0 := &u64(vertex_queue.ring.phys + higher_half + u64(vertex_inner_wp) * sizeof(u64))
		mut vertex_entry_1 := &u64(vertex_queue.ring.phys + higher_half + u64((vertex_inner_wp + 1) % fw.g13_workqueue_entries) * sizeof(u64))
		*vertex_entry_0 = job.init_buffer.va
		*vertex_entry_1 = job.vertex.va
	}
	mut fragment_state := unsafe {
		&fw.G13WorkQueueRingState(fragment_queue.state.cpu_address())
	}
	mut vertex_state := unsafe { &fw.G13WorkQueueRingState(vertex_queue.state.cpu_address()) }
	katomic.store(mut &fragment_state.cpu_wptr, fragment_inner_next)
	katomic.store(mut &vertex_state.cpu_wptr, vertex_inner_next)

	fragment_message := fw.FwRunWorkQueueMsg{
		pipe_type: 1
		work_queue_addr: fragment_queue.info.va
		write_ptr: fragment_inner_next
		event_slot: job.fragment_event_slot
		is_new: if fragment_queue.is_new { u8(1) } else { u8(0) }
	}
	vertex_message := fw.FwRunWorkQueueMsg{
		pipe_type: 0
		work_queue_addr: vertex_queue.info.va
		write_ptr: vertex_inner_next
		event_slot: job.vertex_event_slot
		is_new: if vertex_queue.is_new { u8(1) } else { u8(0) }
	}
	unsafe {
		fragment_destination := voidptr(fragment_outer.ring_phys + higher_half + u64(fragment_outer_wp) * fragment_outer.entry_size)
		C.memcpy(fragment_destination, &fragment_message, sizeof(fw.FwRunWorkQueueMsg))
		vertex_destination := voidptr(vertex_outer.ring_phys + higher_half + u64(vertex_outer_wp) * vertex_outer.entry_size)
		C.memcpy(vertex_destination, &vertex_message, sizeof(fw.FwRunWorkQueueMsg))
	}
	mut fragment_outer_write := unsafe {
		&u32(fragment_outer.state_phys + higher_half + fragment_outer.write_off)
	}
	mut vertex_outer_write := unsafe {
		&u32(vertex_outer.state_phys + higher_half + vertex_outer.write_off)
	}
	katomic.store(mut fragment_outer_write, fragment_outer_next)
	katomic.store(mut vertex_outer_write, vertex_outer_next)
	fragment_queue.is_new = false
	vertex_queue.is_new = false

	fragment_queue.lock.release()
	vertex_queue.lock.release()
	fragment_outer.lock.release()
	vertex_outer.lock.release()

	fragment_rang := mgr.ring_pipe(queue.priority, 1)
	vertex_rang := mgr.ring_pipe(queue.priority, 0)
	if !fragment_rang || !vertex_rang {
		// Both queue pairs already own the commands. Retain all job backing and
		// stop new submissions even when either notification fails.
		C.printf(c'agx: failed to ring paired G13 render doorbells\n')
		mgr.state = .error
	}
	return true
}

// Transfer a prepared render pass to firmware. The manager retains the full
// object graph until both vertex and fragment stamps have completed.
pub fn (mut mgr GpuManager) submit_g13_render_job(job &G13RenderJobResources) bool {
	if job == unsafe { nil } {
		return false
	}
	mgr.lock.acquire()
	defer {
		mgr.lock.release()
	}
	mut owned := unsafe { job }
	if owned.released || owned.submitted || owned.quarantined
		|| !owned.vertex_event_reserved
		|| !owned.fragment_event_reserved || owned.queue == unsafe { nil }
		|| owned.queue.released || owned.context == unsafe { nil } || !owned.context.active
		|| owned.queue.threshold.phys == 0 || owned.queue.render_buffer.counter.phys == 0 {
		return false
	}
	mut threshold := unsafe { &u64(owned.queue.threshold.cpu_address()) }
	old_threshold := katomic.load(threshold)
	katomic.store(mut threshold, old_threshold + u64(2))
	mut tvb_count := unsafe { &u32(owned.queue.render_buffer.counter.cpu_address()) }
	old_tvb_count := katomic.load(tvb_count)
	katomic.store(mut tvb_count, old_tvb_count + u32(1))
	if !mgr.begin_g13_operation_locked() {
		katomic.store(mut tvb_count, old_tvb_count)
		katomic.store(mut threshold, old_threshold)
		return false
	}
	owned.pending_counted = true
	if !mgr.publish_g13_render_job_locked(mut owned) {
		mgr.end_g13_operation_locked()
		owned.pending_counted = false
		katomic.store(mut tvb_count, old_tvb_count)
		katomic.store(mut threshold, old_threshold)
		return false
	}
	owned.submitted = true
	mgr.g13_render_jobs << owned
	return true
}

fn (mut mgr GpuManager) reap_g13_render_jobs() {
	mgr.lock.acquire()
	for index := mgr.g13_render_jobs.len - 1; index >= 0; index-- {
		job := mgr.g13_render_jobs[index]
		if !job.quarantined && (!event.stamp_completed(job.vertex_event_slot)
			|| !event.stamp_completed(job.fragment_event_slot)) {
			continue
		}
		mut owned := unsafe { job }
		owned.completion_result = read_g13_render_result(owned)
		owned.completion_result_ready = true
		if owned.pending_counted {
			mgr.end_g13_operation_locked()
			owned.pending_counted = false
		}
		if mgr.free_g13_render_job_locked(mut owned, true) {
			mgr.g13_render_jobs.delete(index)
			complete_g13_render_job(mut owned, true)
		} else {
			owned.quarantined = true
			complete_g13_render_job(mut owned, false)
		}
	}
	mgr.lock.release()
}

// Firmware is stopped before this is called, so all outstanding render
// command backing can be released without a live UAT invalidation handshake.
fn (mut mgr GpuManager) release_all_g13_render_jobs() {
	for index := mgr.g13_render_jobs.len - 1; index >= 0; index-- {
		mut job := unsafe { mgr.g13_render_jobs[index] }
		if job.pending_counted {
			mgr.end_g13_operation_locked()
			job.pending_counted = false
		}
		complete_g13_render_job(mut job, false)
		mgr.free_g13_render_job_locked(mut job, false)
	}
	mgr.g13_render_jobs.clear()
}

pub fn (job &G13RenderJobResources) timestamp_values() fw.G13RenderTimestamps {
	if job == unsafe { nil } || job.released || job.scene.timestamps.phys == 0 {
		return fw.G13RenderTimestamps{}
	}
	return unsafe { *&fw.G13RenderTimestamps(job.scene.timestamps.cpu_address()) }
}

pub fn (job &G13RenderJobResources) result_values() G13RenderResultValues {
	if job == unsafe { nil } {
		return G13RenderResultValues{}
	}
	if job.completion_result_ready {
		return job.completion_result
	}
	return read_g13_render_result(job)
}

fn read_g13_render_result(job &G13RenderJobResources) G13RenderResultValues {
	if job == unsafe { nil } || job.released || job.scene.timestamps.phys == 0
		|| job.scene.scene.phys == 0 || job.fragment.phys == 0 {
		return G13RenderResultValues{}
	}
	timestamps := unsafe { &fw.G13RenderTimestamps(job.scene.timestamps.cpu_address()) }
	scene := unsafe { &fw.G13BufferScene(job.scene.scene.cpu_address()) }
	fragment := unsafe { &fw.G13RunFragment(job.fragment.cpu_address()) }
	return G13RenderResultValues{
		vertex_start: timestamps.vertex.start
		vertex_end: timestamps.vertex.end
		fragment_start: timestamps.fragment.start
		fragment_end: timestamps.fragment.end
		tvb_size_bytes: job.tvb_size_bytes
		tvb_usage_bytes: u64(scene.total_page_count) * fw.g13_tvb_page_size
		num_tvb_overflows: fragment.tvb_overflow_count
		overflowed: scene.total_page_count > scene.pass_page_count
	}
}

fn (mut mgr GpuManager) free_g13_compute_job_locked(mut job G13ComputeJobResources,
	invalidate bool) bool {
	if job.released {
		return true
	}
	if invalidate {
		if mgr.state != .running || job.context == unsafe { nil } || job.preempt == unsafe { nil } {
			return false
		}
		mut context := unsafe { job.context }
		if !context.unmap_driver_buffer(job.preempt) {
			return false
		}
		unmap_shared_buffer(mut job.command)
		unmap_shared_buffer(mut job.microsequence)
		unmap_shared_buffer(mut job.timestamps)
		// Do not return any physical backing to the PMM until firmware has
		// discarded every removed translation.
		if !mgr.flush_g13_uat_range(context.id, job.preempt.va, job.preempt.size)
			|| !mgr.flush_g13_uat_range(mmu.uat_kernel_flush_slot, job.command.va, job.command.size)
			|| !mgr.flush_g13_uat_range(mmu.uat_kernel_flush_slot, job.microsequence.va, job.microsequence.size)
			|| !mgr.flush_g13_uat_range(mmu.uat_kernel_flush_slot, job.timestamps.va, job.timestamps.size) {
			return false
		}
	}
	job.released = true
	if job.event_reserved {
		event.release_stamp(job.event_slot)
		job.event_reserved = false
	}
	if job.context != unsafe { nil } && job.preempt != unsafe { nil } {
		mut context := unsafe { job.context }
		context.release_driver_buffer(job.preempt)
	}
	if invalidate {
		mgr.release_shared_buffer_backing(mut job.command)
		mgr.release_shared_buffer_backing(mut job.microsequence)
		mgr.release_shared_buffer_backing(mut job.timestamps)
	} else {
		mgr.free_shared_buffer(mut job.command)
		mgr.free_shared_buffer(mut job.microsequence)
		mgr.free_shared_buffer(mut job.timestamps)
	}
	mgr.g13_gpu_readonly.gc()
	mgr.g13_private.gc()
	mgr.g13_shared.gc()
	return true
}

fn complete_g13_compute_job(mut job G13ComputeJobResources, successful bool) {
	if job.completion == unsafe { nil } {
		return
	}
	callback := job.completion
	data := job.completion_data
	job.completion = unsafe { nil }
	job.completion_data = unsafe { nil }
	callback(job, successful, data)
}

// Construct one byte-exact G13 v12.3 compute command and its microsequence.
// This prepares owned backing only; the caller must retain it through event
// completion and explicitly publish it with submit_g13_compute_job().
pub fn (mut mgr GpuManager) prepare_g13_compute_job(resources &G13QueueResources,
	ctx &mmu.UatContext, input &agxcompute.Command) ?&G13ComputeJobResources {
	if resources == unsafe { nil } || resources.released || ctx == unsafe { nil }
		|| !ctx.active || ctx.id == 0 || input.flags & ~agxcompute.supported_flags != 0
		|| resources.channel_mask & g13_queue_channel_compute == 0
		|| mgr.hw_config.compute_preempt1_size == 0 || !fw.validate_g13_compute_layouts()
		|| !fw.validate_g13_microsequence_layouts() || !fw.validate_g13_job_layouts() {
		return none
	}
	attachments := build_g13_attachments(input.attachment_count, input.attachments) or { return none }

	mgr.lock.acquire()
	defer {
		mgr.lock.release()
	}
	if mgr.state != .running || mgr.hw_config.gpu_gen != .g13
		|| mgr.g13_channels == unsafe { nil } || resources.released {
		return none
	}
	mut job := &G13ComputeJobResources{
		context: unsafe { ctx }
		queue: unsafe { resources }
	}
	mut complete := false
	defer {
		if !complete {
			if !mgr.free_g13_compute_job_locked(mut job, job.mappings_published) {
				job.quarantined = true
				mgr.g13_compute_jobs << job
			}
		}
	}

	job.event_slot = event.reserve_stamp() or { return none }
	job.event_reserved = true
	job.stamp_value = event.advance_stamp(job.event_slot) or { return none }
	preempt_size := mgr.hw_config.compute_preempt1_size + u64(32)
	mut user_context := unsafe { ctx }
	job.preempt = user_context.alloc_driver_buffer_aligned(preempt_size, false, fw.g13_tvb_page_size) or { return none }
	job.command = mgr.alloc_g13_buffer_with_protection(sizeof(fw.G13RunCompute), pgtable.gpu_prot_gpu_ro_fw_private_rw) or { return none }
	logical_microsequence_size := if input.has_result { u64(0x228) } else { u64(0x1c0) }
	job.microsequence = mgr.alloc_g13_buffer_with_protection(logical_microsequence_size, pgtable.gpu_prot_fw_private_rw) or { return none }
	job.timestamps = mgr.alloc_g13_shared_buffer(sizeof(fw.G13JobTimestamps)) or { return none }

	mut owned_queue := unsafe { resources }
	job.event_sequence = owned_queue.event_sequences[2]
	owned_queue.event_sequences[2]++
	compute_queue := &owned_queue.subqueues[2]
	stats_compute := mgr.g13_channels.stats_compute.va
	if compute_queue.info.va == 0 || stats_compute == 0 {
		return none
	}

	preempt_2_offset := mgr.hw_config.compute_preempt1_size
	preempt_3_offset := preempt_2_offset + u64(8)
	preempt_4_offset := preempt_3_offset + u64(8)
	preempt_5_offset := preempt_4_offset + u64(8)
	unsafe {
		mut run := &fw.G13RunCompute(job.command.cpu_address())
		*run = fw.G13RunCompute{
			tag: fw.cmd_type_run_compute
			vm_slot: ctx.id
			notifier: resources.notifier.va
			job_params_1: fw.G13ComputeJobParameters1{
				preempt_buf_1: job.preempt.va
				encoder: input.encoder_ptr
				preempt_buf_2: job.preempt.va + preempt_2_offset
				preempt_buf_3: job.preempt.va + preempt_3_offset
				preempt_buf_4: job.preempt.va + preempt_4_offset
				preempt_buf_5: job.preempt.va + preempt_5_offset
				pipeline_base: input.usc_base
				unk_38: 0x8c60
				helper_program: input.helper_program
				helper_arg: input.helper_arg
				helper_cfg: input.helper_cfg
				unk_58: 1
				iogpu_unk_40: input.iogpu_unk_40
			}
			microsequence: job.microsequence.va
			microsequence_size: u32(logical_microsequence_size)
			job_params_2: fw.G13ComputeJobParameters2{
				preempt_buf_1: job.preempt.va
				encoder_end: input.encoder_end
			}
			encoder_params: fw.G13EncoderParams{
				encoder_id: input.encoder_id
				unk_mask: input.unk_mask
				sampler_array: input.sampler_array
				sampler_count: input.sampler_count
				sampler_max: input.sampler_max
			}
			meta: fw.G13JobMeta{
				no_preemption: if input.flags & agxcompute.no_preemption != 0 {
					u8(1)
				} else {
					u8(0)
				}
				stamp: event.driver_stamp_address(job.event_slot)
				fw_stamp: event.firmware_stamp_address(job.event_slot)
				stamp_value: job.stamp_value
				stamp_slot: job.event_slot
				flush_stamps: if input.flush_stamps { u32(1) } else { u32(0) }
				uuid: input.command_id
				event_sequence: u32(job.event_sequence)
			}
			start_ts: job.timestamps.va
			end_ts: job.timestamps.va + u64(8)
			client_sequence: u8(resources.queue_id & 0xff)
		}

		start := fw.G13MicroseqStartCompute{
			header: fw.g13_useq_start_compute
			unk_pointer: job.command.va + fw.g13_compute_unk_pointee_offset
			job_params_1: job.command.va + fw.g13_compute_job_params_1_offset
			stats: stats_compute
			work_queue: compute_queue.info.va
			vm_slot: ctx.id
			unk_28: 1
			event_generation: resources.queue_id
			event_sequence: job.event_sequence
			job_params_2: job.command.va + fw.g13_compute_job_params_2_offset
			uuid: input.command_id
			attachments: attachments
		}
		mut micro_offset := u64(0)
		C.memcpy(voidptr(job.microsequence.phys + higher_half + micro_offset), voidptr(&start), sizeof(fw.G13MicroseqStartCompute))
		micro_offset += sizeof(fw.G13MicroseqStartCompute)
		if input.has_result {
			start_timestamp := fw.G13MicroseqTimestamp{
				header: fw.g13_useq_timestamp | (u32(1) << 31)
				cur_ts: job.command.va + fw.g13_compute_cur_ts_offset
				start_ts: job.command.va + fw.g13_compute_start_ts_offset
				update_ts: job.command.va + fw.g13_compute_start_ts_offset
				work_queue: compute_queue.info.va
				uuid: input.command_id
			}
			C.memcpy(voidptr(job.microsequence.phys + higher_half + micro_offset), voidptr(&start_timestamp), sizeof(fw.G13MicroseqTimestamp))
			micro_offset += sizeof(fw.G13MicroseqTimestamp)
		}
		wait := fw.G13MicroseqSimpleOp{
			header: fw.g13_wait_for_idle_header(fw.g13_useq_pipe_compute) or { return none }
		}
		C.memcpy(voidptr(job.microsequence.phys + higher_half + micro_offset), voidptr(&wait), sizeof(fw.G13MicroseqSimpleOp))
		micro_offset += sizeof(fw.G13MicroseqSimpleOp)
		if input.has_result {
			end_timestamp := fw.G13MicroseqTimestamp{
				header: fw.g13_useq_timestamp
				cur_ts: job.command.va + fw.g13_compute_cur_ts_offset
				start_ts: job.command.va + fw.g13_compute_start_ts_offset
				update_ts: job.command.va + fw.g13_compute_end_ts_offset
				work_queue: compute_queue.info.va
				uuid: input.command_id
			}
			C.memcpy(voidptr(job.microsequence.phys + higher_half + micro_offset), voidptr(&end_timestamp), sizeof(fw.G13MicroseqTimestamp))
			micro_offset += sizeof(fw.G13MicroseqTimestamp)
		}
		finalize := fw.G13MicroseqFinalizeCompute{
			header: fw.g13_useq_finalize_compute
			stats: stats_compute
			work_queue: compute_queue.info.va
			vm_slot: ctx.id
			job_params_2: job.command.va + fw.g13_compute_job_params_2_offset
			uuid: input.command_id
			fw_stamp: event.firmware_stamp_address(job.event_slot)
			stamp_value: job.stamp_value
			restart_branch_offset: -i32(micro_offset)
			has_attachments: if input.attachment_count != 0 { u32(1) } else { u32(0) }
		}
		C.memcpy(voidptr(job.microsequence.phys + higher_half + micro_offset), voidptr(&finalize), sizeof(fw.G13MicroseqFinalizeCompute))
		micro_offset += sizeof(fw.G13MicroseqFinalizeCompute)
		retire := fw.G13MicroseqSimpleOp{
			header: fw.g13_useq_retire_stamp
		}
		C.memcpy(voidptr(job.microsequence.phys + higher_half + micro_offset), voidptr(&retire), sizeof(fw.G13MicroseqSimpleOp))
		micro_offset += sizeof(fw.G13MicroseqSimpleOp)
		if micro_offset != logical_microsequence_size {
			return none
		}
	}

	job.mappings_published = true
	if !mgr.flush_g13_uat_range(ctx.id, job.preempt.va, job.preempt.size)
		|| !mgr.flush_g13_kernel_buffer(&job.command)
		|| !mgr.flush_g13_kernel_buffer(&job.microsequence)
		|| !mgr.flush_g13_kernel_buffer(&job.timestamps) {
		return none
	}
	complete = true
	return job
}

pub fn (mut mgr GpuManager) release_g13_compute_job(job &G13ComputeJobResources) {
	if job == unsafe { nil } {
		return
	}
	mgr.lock.acquire()
	mut owned := unsafe { job }
	if !owned.submitted {
		complete_g13_compute_job(mut owned, false)
		if !mgr.free_g13_compute_job_locked(mut owned, owned.mappings_published)
			&& !owned.quarantined {
			owned.quarantined = true
			mgr.g13_compute_jobs << owned
		}
	}
	mgr.lock.release()
}

// Install the one-shot completion callback before publishing a prepared job.
// The callback runs with the manager lock held, while timestamps remain valid.
pub fn (mut mgr GpuManager) set_g13_compute_completion(job &G13ComputeJobResources,
	callback fn (&G13ComputeJobResources, bool, voidptr), data voidptr) bool {
	if job == unsafe { nil } || callback == unsafe { nil } {
		return false
	}
	mgr.lock.acquire()
	defer {
		mgr.lock.release()
	}
	mut owned := unsafe { job }
	if owned.released || owned.submitted || owned.quarantined
		|| owned.completion != unsafe { nil } {
		return false
	}
	owned.completion = callback
	owned.completion_data = data
	return true
}

// Transfer a prepared compute job to firmware. Once this succeeds, the
// manager owns the job until its event stamp retires; callers must not release
// or reuse any backing referenced by the command.
pub fn (mut mgr GpuManager) submit_g13_compute_job(job &G13ComputeJobResources) bool {
	if job == unsafe { nil } {
		return false
	}
	mgr.lock.acquire()
	defer {
		mgr.lock.release()
	}
	mut owned := unsafe { job }
	if owned.released || owned.submitted || owned.quarantined || !owned.event_reserved
		|| owned.queue == unsafe { nil } || owned.queue.released
		|| owned.context == unsafe { nil } || !owned.context.active {
		return false
	}
	queue := owned.queue
	if queue.threshold.phys == 0 {
		return false
	}
	mut threshold := unsafe { &u64(queue.threshold.cpu_address()) }
	old_threshold := katomic.load(threshold)
	katomic.store(mut threshold, old_threshold + u64(1))
	if !mgr.begin_g13_operation_locked() {
		katomic.store(mut threshold, old_threshold)
		return false
	}
	owned.pending_counted = true
	if !mgr.submit_g13_queue_command(queue, 2, owned.command.va, owned.event_slot) {
		mgr.end_g13_operation_locked()
		owned.pending_counted = false
		katomic.store(mut threshold, old_threshold)
		return false
	}
	owned.submitted = true
	mgr.g13_compute_jobs << owned
	return true
}

fn (mut mgr GpuManager) reap_g13_compute_jobs() {
	mgr.lock.acquire()
	for index := mgr.g13_compute_jobs.len - 1; index >= 0; index-- {
		job := mgr.g13_compute_jobs[index]
		if !job.quarantined && !event.stamp_completed(job.event_slot) {
			continue
		}
		mut owned := unsafe { job }
		owned.completion_result = owned.timestamp_values()
		owned.completion_ready = true
		if owned.pending_counted {
			mgr.end_g13_operation_locked()
			owned.pending_counted = false
		}
		if mgr.free_g13_compute_job_locked(mut owned, true) {
			mgr.g13_compute_jobs.delete(index)
			complete_g13_compute_job(mut owned, true)
		} else {
			owned.quarantined = true
			complete_g13_compute_job(mut owned, false)
		}
	}
	mgr.lock.release()
}

// Firmware is stopped before this is called, so no completion flush is
// required and all remaining command backing can be reclaimed directly.
fn (mut mgr GpuManager) release_all_g13_compute_jobs() {
	for index := mgr.g13_compute_jobs.len - 1; index >= 0; index-- {
		mut job := unsafe { mgr.g13_compute_jobs[index] }
		if job.pending_counted {
			mgr.end_g13_operation_locked()
			job.pending_counted = false
		}
		complete_g13_compute_job(mut job, false)
		mgr.free_g13_compute_job_locked(mut job, false)
	}
	mgr.g13_compute_jobs.clear()
}

pub fn (job &G13ComputeJobResources) command_address() u64 {
	if job == unsafe { nil } || job.released {
		return 0
	}
	return job.command.va
}

pub fn (job &G13ComputeJobResources) timestamp_values() fw.G13JobTimestamps {
	if job == unsafe { nil } {
		return fw.G13JobTimestamps{}
	}
	if job.completion_ready {
		return job.completion_result
	}
	if job.released || job.timestamps.phys == 0 {
		return fw.G13JobTimestamps{}
	}
	return unsafe { *&fw.G13JobTimestamps(job.timestamps.cpu_address()) }
}

pub fn (mut mgr GpuManager) create_g13_queue_resources(queue_id u32,
	channel_mask u32, priority u32, vm &mmu.UatContext) ?&G13QueueResources {
	if queue_id == 0 || channel_mask == 0 || channel_mask & ~g13_queue_channel_mask != 0
		|| priority >= 4 || !fw.validate_g13_workqueue_layouts()
		|| !fw.validate_g13_event_layouts() || vm == unsafe { nil } || !vm.active
		|| vm.id == 0 {
		return none
	}
	mgr.lock.acquire()
	defer {
		mgr.lock.release()
	}
	if mgr.state != .running || mgr.hw_config.gpu_gen != .g13
		|| mgr.g13_channels == unsafe { nil } || !event.event_manager_ready() {
		return none
	}

	mut resources := &G13QueueResources{
		queue_id: queue_id
		channel_mask: channel_mask
		priority: priority
		vm: unsafe { vm }
	}
	mut complete := false
	defer {
		if !complete {
			if !mgr.free_g13_queue_resources_locked(mut resources, resources.mappings_published) {
				resources.quarantined = true
				mgr.g13_queues << resources
			}
		}
	}

	resources.context = mgr.alloc_g13_shared_buffer(sizeof(fw.G13GpuContextData)) or {
		return none
	}
	if !fw.initialize_g13_gpu_context(resources.context.cpu_address(), resources.context.size) {
		return none
	}
	resources.notifier_list = mgr.alloc_g13_shared_buffer(sizeof(fw.G13NotifierList)) or {
		return none
	}
	unsafe {
		mut list := &fw.G13NotifierList(resources.notifier_list.cpu_address())
		list.list_head.next = resources.notifier_list.va + 8
	}
	resources.threshold = mgr.alloc_g13_shared_buffer(sizeof(u64)) or { return none }
	resources.notifier = mgr.alloc_g13_buffer_with_protection(sizeof(fw.G13Notifier), pgtable.gpu_prot_fw_private_rw) or { return none }
	unsafe {
		mut notifier := &fw.G13Notifier(resources.notifier.cpu_address())
		notifier.threshold = resources.threshold.va
		notifier.generation = queue_id
		notifier.unk_10 = 0x50
	}

	for pipe_type := u32(0); pipe_type < 3; pipe_type++ {
		if channel_mask & (u32(1) << pipe_type) != 0
			&& !mgr.initialize_g13_subqueue(mut resources, pipe_type) {
			return none
		}
	}
	if channel_mask & g13_queue_channel_vertex != 0
		&& !mgr.initialize_g13_render_buffer(mut resources, vm) {
		return none
	}
	resources.mappings_published = true
	if !mgr.flush_g13_queue_mappings(resources) {
		return none
	}
	mgr.g13_queues << resources
	complete = true
	return resources
}

pub fn (mut mgr GpuManager) release_g13_queue_resources(resources &G13QueueResources) bool {
	if resources == unsafe { nil } {
		return false
	}
	mgr.lock.acquire()
	defer {
		mgr.lock.release()
	}
	mut owned := unsafe { resources }
	if owned.released {
		return true
	}
	if owned.quarantined {
		return false
	}
	for job in mgr.g13_render_jobs {
		if !job.released && voidptr(job.queue) == voidptr(resources) {
			return false
		}
	}
	for job in mgr.g13_compute_jobs {
		if !job.released && voidptr(job.queue) == voidptr(resources) {
			return false
		}
	}
	if !mgr.free_g13_queue_resources_locked(mut owned, owned.mappings_published) {
		owned.quarantined = true
		return false
	}
	for index, candidate in mgr.g13_queues {
		if voidptr(candidate) == voidptr(resources) {
			mgr.g13_queues.delete(index)
			break
		}
	}
	return true
}

// Vinix currently serializes native G13 submissions per userspace queue. This
// preserves the DRM scheduler's implicit ordering until multi-command barrier
// objects and independent TVB scene slots are implemented.
pub fn (mut mgr GpuManager) g13_queue_busy(resources &G13QueueResources) bool {
	if resources == unsafe { nil } {
		return true
	}
	mgr.lock.acquire()
	defer {
		mgr.lock.release()
	}
	if resources.released || resources.quarantined {
		return true
	}
	for job in mgr.g13_render_jobs {
		if !job.released && voidptr(job.queue) == voidptr(resources) {
			return true
		}
	}
	for job in mgr.g13_compute_jobs {
		if !job.released && voidptr(job.queue) == voidptr(resources) {
			return true
		}
	}
	return false
}

// Caller holds the manager lock during shutdown.
fn (mut mgr GpuManager) release_all_g13_queue_resources() {
	for index := mgr.g13_queues.len - 1; index >= 0; index-- {
		mut resources := unsafe { mgr.g13_queues[index] }
		mgr.free_g13_queue_resources_locked(mut resources, false)
	}
	mgr.g13_queues.clear()
}
