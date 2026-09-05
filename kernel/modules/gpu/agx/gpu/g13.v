module gpu

// Queue-owned object graph for the G13/macOS 12.3 firmware ABI. All buffers
// are driver-owned and stay mapped until the DRM queue is explicitly destroyed
// or its file is closed.

import gpu.agx.fw
import gpu.agx.alloc
import gpu.agx.pgtable
import gpu.agx.event
import gpu.agx.mmu
import katomic
import klock

pub const g13_queue_channel_vertex = u32(1) << 0
pub const g13_queue_channel_fragment = u32(1) << 1
pub const g13_queue_channel_compute = u32(1) << 2
const g13_queue_channel_mask = g13_queue_channel_vertex | g13_queue_channel_fragment | g13_queue_channel_compute
const g13_compute_no_preemption = u64(1) << 0
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

pub struct G13ComputeAttachment {
pub:
	address u64
	size    u32
	order   u16
}

pub struct G13ComputeCommand {
pub:
	flags            u64
	encoder_ptr      u64
	encoder_end      u64
	usc_base         u64
	helper_program   u32
	helper_cfg       u32
	helper_arg       u64
	encoder_id       u32
	cmd_id           u32
	sampler_array    u64
	sampler_count    u32
	sampler_max      u32
	iogpu_unk_40     u32
	unk_mask         u32
	attachment_count u32
	attachments      [fw.g13_max_attachments]G13ComputeAttachment
	has_result       bool
	flush_stamps     bool
}

pub struct G13ComputeJobResources {
pub mut:
	event_slot     u32
	stamp_value    u32
	event_sequence u64
	command        SharedBuffer
	microsequence  SharedBuffer
	timestamps     SharedBuffer
	preempt        &mmu.UatBuffer = unsafe { nil }
	context        &mmu.UatContext = unsafe { nil }
	queue          &G13QueueResources = unsafe { nil }
	event_reserved bool
	submitted      bool
	released       bool
}

pub struct G13QueueResources {
pub:
	queue_id     u32
	channel_mask u32
	priority     u32
mut:
	context         SharedBuffer
	notifier_list   SharedBuffer
	threshold       SharedBuffer
	notifier        SharedBuffer
	subqueues       [3]G13SubQueueResources
	event_sequences [3]u64
	render_buffer   G13RenderBufferResources
	vm              &mmu.UatContext = unsafe { nil }
	released        bool
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
	buffer.page_list = context.alloc_driver_buffer(u64(g13_tvb_max_pages) * sizeof(u32), true) or {
		return false
	}
	buffer.block_list = context.alloc_driver_buffer(u64(g13_tvb_max_blocks) * u64(2) * sizeof(u32), true) or {
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
	if !mgr.flush_g13_kernel_buffer(&buffer.info)
		|| !mgr.flush_g13_kernel_buffer(&buffer.block_control)
		|| !mgr.flush_g13_kernel_buffer(&buffer.counter)
		|| !mgr.flush_g13_kernel_buffer(&buffer.stats)
		|| !mgr.flush_g13_kernel_buffer(&buffer.kernel_buffer)
		|| !mgr.flush_g13_uat_range(ctx.id, buffer.page_list.va, buffer.page_list.size)
		|| !mgr.flush_g13_uat_range(ctx.id, buffer.block_list.va, buffer.block_list.size) {
		return false
	}
	buffer.initialized = true
	complete = true
	return true
}

// Grow the queue's TVB to the minimum needed by a scene. The page and block
// tables are updated only after every new block has a valid, acknowledged UAT
// mapping, so firmware never observes a half-committed heap extension.
fn (mut mgr GpuManager) ensure_g13_tvb_blocks(mut buffer G13RenderBufferResources,
	minimum u32) bool {
	if !buffer.initialized || buffer.context == unsafe { nil } || minimum == 0
		|| minimum > g13_tvb_max_blocks || u32(buffer.blocks.len) >= minimum {
		return buffer.initialized && u32(buffer.blocks.len) >= minimum
	}
	mut context := unsafe { buffer.context }
	old_count := u32(buffer.blocks.len)
	for _ in old_count .. minimum {
		block := context.alloc_driver_buffer(fw.g13_tvb_block_size, false) or {
			return false
		}
		if !mgr.flush_g13_uat_range(context.id, block.va, block.size) {
			context.release_driver_buffer(block)
			return false
		}
		buffer.blocks << block
	}
	unsafe {
		mut pages := &u32(buffer.page_list.cpu_address())
		mut blocks := &u32(buffer.block_list.cpu_address())
		for index := old_count; index < minimum; index++ {
			page_number := u32(buffer.blocks[index].va >> fw.g13_tvb_page_shift)
			blocks[index * 2] = page_number
			for page := u32(0); page < fw.g13_tvb_pages_per_block; page++ {
				pages[index * fw.g13_tvb_pages_per_block + page] = page_number + page
			}
		}
		mut control := &fw.G13BufferBlockControl(buffer.block_control.cpu_address())
		control.total = minimum
		control.wptr = minimum
		mut info := &fw.G13BufferInfo(buffer.info.cpu_address())
		page_count := minimum * fw.g13_tvb_pages_per_block
		info.page_count = page_count
		info.block_count = minimum
		info.last_page = page_count - 1
	}
	return true
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

fn (mut mgr GpuManager) free_g13_queue_resources_locked(mut resources G13QueueResources) {
	if resources.released {
		return
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
}

// Publish a private work-command pointer into a queue-owned ring and then
// publish the corresponding RunWorkQueue message into the global priority
// pipe. Holding the outer ring lock across both writes prevents a full outer
// ring from stranding an otherwise-visible inner command.
pub fn (mut mgr GpuManager) submit_g13_queue_command(resources &G13QueueResources,
	pipe_type u32, command_va u64, event_slot u32) bool {
	if resources == unsafe { nil } || resources.released || mgr.state != .running
		|| mgr.hw_config.gpu_gen != .g13 || pipe_type >= 3
		|| command_va < alloc.g13_gpu_readonly_start || command_va >= alloc.g13_gpu_readonly_end
		|| event_slot >= event.max_stamps
		|| resources.channel_mask & (u32(1) << pipe_type) == 0
		|| resources.priority >= 4 {
		return false
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
	inner_next := (inner_wp + 1) % fw.g13_workqueue_entries
	if inner_next == inner_done {
		queue.lock.release()
		outer.lock.release()
		return false
	}
	unsafe {
		mut entry := &u64(queue.ring.phys + higher_half + u64(inner_wp) * sizeof(u64))
		*entry = command_va
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

fn build_g13_compute_attachments(command &G13ComputeCommand) ?fw.G13MicroseqAttachments {
	if command.attachment_count > fw.g13_max_attachments {
		return none
	}
	mut attachments := fw.G13MicroseqAttachments{}
	for index := u32(0); index < command.attachment_count; index++ {
		attachment := command.attachments[index]
		if attachment.order < 1 || attachment.order > 6 {
			return none
		}
		attachments.list[index] = fw.G13MicroseqAttachment{
			address: attachment.address
			size: attachment.size
			unk_c: 0x17
			unk_e: attachment.order
		}
	}
	attachments.count = command.attachment_count
	return attachments
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

// Construct one byte-exact G13 v12.3 compute command and its microsequence.
// This prepares owned backing only; the caller must retain it through event
// completion and explicitly publish it with submit_g13_compute_job().
pub fn (mut mgr GpuManager) prepare_g13_compute_job(resources &G13QueueResources,
	ctx &mmu.UatContext, input &G13ComputeCommand) ?&G13ComputeJobResources {
	if resources == unsafe { nil } || resources.released || ctx == unsafe { nil }
		|| !ctx.active || ctx.id == 0 || input.flags & ~g13_compute_no_preemption != 0
		|| resources.channel_mask & g13_queue_channel_compute == 0
		|| mgr.hw_config.compute_preempt1_size == 0 || !fw.validate_g13_compute_layouts()
		|| !fw.validate_g13_microsequence_layouts() || !fw.validate_g13_job_layouts() {
		return none
	}
	attachments := build_g13_compute_attachments(input) or { return none }

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
			mgr.free_g13_compute_job_locked(mut job, false)
		}
	}

	job.event_slot = event.reserve_stamp() or { return none }
	job.event_reserved = true
	job.stamp_value = event.advance_stamp(job.event_slot) or { return none }
	preempt_size := mgr.hw_config.compute_preempt1_size + u64(32)
	mut user_context := unsafe { ctx }
	job.preempt = user_context.alloc_driver_buffer(preempt_size, false) or { return none }
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
				no_preemption: if input.flags & g13_compute_no_preemption != 0 {
					u8(1)
				} else {
					u8(0)
				}
				stamp: event.driver_stamp_address(job.event_slot)
				fw_stamp: event.firmware_stamp_address(job.event_slot)
				stamp_value: job.stamp_value
				stamp_slot: job.event_slot
				flush_stamps: if input.flush_stamps { u32(1) } else { u32(0) }
				uuid: input.cmd_id
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
			uuid: input.cmd_id
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
				uuid: input.cmd_id
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
				uuid: input.cmd_id
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
			uuid: input.cmd_id
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
		mgr.free_g13_compute_job_locked(mut owned, false)
	}
	mgr.lock.release()
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
	if owned.released || owned.submitted || !owned.event_reserved
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
	if !mgr.submit_g13_queue_command(queue, 2, owned.command.va, owned.event_slot) {
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
		if !event.stamp_completed(job.event_slot) {
			continue
		}
		mut owned := unsafe { job }
		if mgr.free_g13_compute_job_locked(mut owned, true) {
			mgr.g13_compute_jobs.delete(index)
		}
	}
	mgr.lock.release()
}

// Firmware is stopped before this is called, so no completion flush is
// required and all remaining command backing can be reclaimed directly.
fn (mut mgr GpuManager) release_all_g13_compute_jobs() {
	for index := mgr.g13_compute_jobs.len - 1; index >= 0; index-- {
		mut job := unsafe { mgr.g13_compute_jobs[index] }
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
	if job == unsafe { nil } || job.released || job.timestamps.phys == 0 {
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
			mgr.free_g13_queue_resources_locked(mut resources)
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
	if !mgr.flush_g13_queue_mappings(resources) {
		return none
	}
	mgr.g13_queues << resources
	complete = true
	return resources
}

pub fn (mut mgr GpuManager) release_g13_queue_resources(resources &G13QueueResources) {
	if resources == unsafe { nil } {
		return
	}
	mgr.lock.acquire()
	defer {
		mgr.lock.release()
	}
	mut owned := unsafe { resources }
	if owned.released {
		return
	}
	for index, candidate in mgr.g13_queues {
		if voidptr(candidate) == voidptr(resources) {
			mgr.g13_queues.delete(index)
			break
		}
	}
	mgr.free_g13_queue_resources_locked(mut owned)
}

// Caller holds the manager lock during shutdown.
fn (mut mgr GpuManager) release_all_g13_queue_resources() {
	for index := mgr.g13_queues.len - 1; index >= 0; index-- {
		mut resources := unsafe { mgr.g13_queues[index] }
		mgr.free_g13_queue_resources_locked(mut resources)
	}
	mgr.g13_queues.clear()
}
