module gpu

// Queue-owned object graph for the G13/macOS 12.3 firmware ABI. All buffers
// are driver-owned and stay mapped until the DRM queue is explicitly destroyed
// or its file is closed.

import gpu.agx.fw
import gpu.agx.pgtable

pub const g13_queue_channel_vertex = u32(1) << 0
pub const g13_queue_channel_fragment = u32(1) << 1
pub const g13_queue_channel_compute = u32(1) << 2
const g13_queue_channel_mask = g13_queue_channel_vertex | g13_queue_channel_fragment |
	g13_queue_channel_compute

struct G13SubQueueResources {
mut:
	state      SharedBuffer
	ring       SharedBuffer
	gpu_buffer SharedBuffer
	info       SharedBuffer
	pipe_type  u32
	is_new     bool
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
		mgr.free_shared_buffer(mut queue.info)
		mgr.free_shared_buffer(mut queue.ring)
		mgr.free_shared_buffer(mut queue.state)
		mgr.free_shared_buffer(mut queue.gpu_buffer)
	}
	mgr.free_shared_buffer(mut resources.notifier)
	mgr.free_shared_buffer(mut resources.threshold)
	mgr.free_shared_buffer(mut resources.notifier_list)
	mgr.free_shared_buffer(mut resources.context)
	mgr.g13_private.gc()
	mgr.g13_shared.gc()
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
	if mgr.state != .running || mgr.hw_config.gpu_gen != .g13 || mgr.g13_channels == unsafe { nil } {
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
