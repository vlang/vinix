module gpu

// Queue-owned object graph for the G13/macOS 12.3 firmware ABI. All buffers
// are driver-owned and stay mapped until the DRM queue is explicitly destroyed
// or its file is closed.

import gpu.agx.fw
import gpu.agx.alloc
import gpu.agx.pgtable
import gpu.agx.event
import katomic
import klock

pub const g13_queue_channel_vertex = u32(1) << 0
pub const g13_queue_channel_fragment = u32(1) << 1
pub const g13_queue_channel_compute = u32(1) << 2
const g13_queue_channel_mask = g13_queue_channel_vertex | g13_queue_channel_fragment |
	g13_queue_channel_compute

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

pub struct G13QueueResources {
pub:
	queue_id     u32
	channel_mask u32
	priority     u32
mut:
	context       SharedBuffer
	notifier_list SharedBuffer
	threshold     SharedBuffer
	notifier      SharedBuffer
	subqueues     [3]G13SubQueueResources
	released      bool
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
	mgr.g13_events.firmware_stamps = mgr.alloc_g13_buffer_with_protection(bytes,
		pgtable.gpu_prot_fw_private_rw) or {
		mgr.free_shared_buffer(mut mgr.g13_events.driver_stamps)
		return false
	}
	if !event.configure_event_manager(mgr.g13_events.driver_stamps.va,
		mgr.g13_events.driver_stamps.phys, mgr.g13_events.firmware_stamps.va,
		mgr.g13_events.firmware_stamps.phys) {
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
	queue.gpu_buffer = mgr.alloc_g13_buffer_with_protection(fw.g13_gpu_buffer_size,
		pgtable.gpu_prot_fw_private_rw) or { return false }
	queue.state = mgr.alloc_g13_shared_buffer(sizeof(fw.G13WorkQueueRingState)) or {
		return false
	}
	queue.ring = mgr.alloc_g13_shared_buffer(u64(fw.g13_workqueue_entries) * sizeof(u64)) or {
		return false
	}
	queue.info = mgr.alloc_g13_buffer_with_protection(sizeof(fw.G13WorkQueueInfo),
		pgtable.gpu_prot_fw_private_rw) or { return false }
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
		|| command_va < alloc.g13_private_start || command_va >= alloc.g13_private_end
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
	_ = mgr.ring_pipe(resources.priority, pipe_type)
	return true
}

pub fn (mut mgr GpuManager) create_g13_queue_resources(queue_id u32,
	channel_mask u32, priority u32) ?&G13QueueResources {
	if queue_id == 0 || channel_mask == 0 || channel_mask & ~g13_queue_channel_mask != 0
		|| priority >= 4 || !fw.validate_g13_workqueue_layouts()
		|| !fw.validate_g13_event_layouts() {
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
	resources.notifier = mgr.alloc_g13_buffer_with_protection(sizeof(fw.G13Notifier),
		pgtable.gpu_prot_fw_private_rw) or { return none }
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
