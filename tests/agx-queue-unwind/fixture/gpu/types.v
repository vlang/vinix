@[has_globals]
module gpu

import klock
import gpu.agx.mmu

const g13_queue_channel_mask = u32(7)
const g13_queue_channel_vertex = u32(1)
enum State { running stopped }
enum Generation { g13 g17 }
struct Config { gpu_gen Generation = .g13 firmware_abi int }
struct SharedBuffer { mut: va u64 phys u64 size u64 }
fn (buffer &SharedBuffer) cpu_address() voidptr { return unsafe { voidptr(buffer.phys) } }

struct G13QueueResources {
mut:
	queue_id u32
	fence_context u64
	firmware_id u64
	channel_mask u32
	priority u32
	vm &mmu.UatContext = unsafe { nil }
	context SharedBuffer
	notifier_list SharedBuffer
	threshold SharedBuffer
	notifier SharedBuffer
	mappings_published bool
	quarantined bool
	released bool
}
struct GpuManager {
mut:
	lock klock.Lock
	state State
	hw_config Config
	g13_channels voidptr = voidptr(1)
	g13_queue_ids G13QueueIds
	g13_queues []&G13QueueResources
	mode int
	allocations int
	cleanups int
	last &G13QueueResources = unsafe { nil }
	workspace [4][128]u8
}
fn (mut manager GpuManager) alloc_g13_shared_buffer(size u64) ?SharedBuffer { return manager.allocate(size) }
fn (mut manager GpuManager) alloc_g13_buffer_with_protection(size u64, _ u64) ?SharedBuffer { return manager.allocate(size) }
fn (mut manager GpuManager) allocate(size u64) ?SharedBuffer {
	manager.allocations++
	if manager.allocations == manager.mode || (manager.mode == 12 && manager.allocations == 1) { return none }
	assert manager.allocations <= 4 && size <= 128
	return SharedBuffer{va: u64(manager.allocations) * 0x4000, phys: unsafe { u64(&manager.workspace[manager.allocations - 1][0]) }, size: size}
}
fn (manager &GpuManager) initialize_g13_subqueue(mut _ G13QueueResources, pipe u32) bool { return manager.mode != 7 + int(pipe) }
fn (manager &GpuManager) initialize_g13_render_buffer(mut _ G13QueueResources, _ &mmu.UatContext) bool { return manager.mode != 10 }
fn (manager &GpuManager) flush_g13_queue_mappings(_ &G13QueueResources) bool { return manager.mode != 11 }
fn (mut manager GpuManager) free_g13_queue_resources_locked(mut resources G13QueueResources, published bool) bool {
	manager.cleanups++; manager.last = &resources
	if published || manager.mode == 12 { return false }
	resources.context = SharedBuffer{}; resources.notifier_list = SharedBuffer{}
	resources.threshold = SharedBuffer{}; resources.notifier = SharedBuffer{}
	resources.released = true
	return true
}
