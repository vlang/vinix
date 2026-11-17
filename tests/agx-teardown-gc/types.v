@[has_globals]
module gpu

import gpu.agx.alloc
import gpu.agx.mmu
import klock

__global teardown_host_page_size = u64(16384)
__global uat_mgr = unsafe { &TeardownUat(nil) }
struct TeardownUat {}
fn (_ &TeardownUat) unmap_kernel(_ u64, _ u64) {}

struct TailCache { mut: references u64 = 1 }
struct G13RenderBufferResources {
mut:
	initialized bool
	slot_reserved bool
	slot u32
	active_scenes u32
	context &mmu.UatContext = unsafe { nil }
	tail_pointer_cache &TailCache = unsafe { nil }
	page_list &mmu.UatBuffer = unsafe { nil }
	block_list &mmu.UatBuffer = unsafe { nil }
	blocks []&mmu.UatBuffer
	kernel_buffer SharedBuffer
	stats SharedBuffer
	counter SharedBuffer
	block_control SharedBuffer
	info SharedBuffer
}
struct Events { mut: releases int }
fn (mut events Events) release(_ u32, _ u32, _ bool) { events.releases++; assert events.releases == 1 }
struct Subqueue { mut: lock klock.Lock events Events info SharedBuffer ring SharedBuffer state SharedBuffer gpu_buffer SharedBuffer }
struct G13QueueResources {
mut:
	released bool
	render_buffer G13RenderBufferResources
	subqueues [3]Subqueue
	notifier SharedBuffer
	threshold SharedBuffer
	notifier_list SharedBuffer
	context SharedBuffer
}
struct G13RenderSceneResources {
mut:
	aux_framebuffer &mmu.UatBuffer = unsafe { nil }
	preempt &mmu.UatBuffer = unsafe { nil }
	tilemap &mmu.UatBuffer = unsafe { nil }
	heapmeta &mmu.UatBuffer = unsafe { nil }
	user_buffer &mmu.UatBuffer = unsafe { nil }
	tail_pointer_cache &TailCache = unsafe { nil }
	timestamps SharedBuffer
	scene SharedBuffer
}
struct G13RenderJobResources {
mut:
	released bool
	context &mmu.UatContext = unsafe { nil }
	queue &G13QueueResources = unsafe { nil }
	explicit_barriers []u64
	vertex_event_reserved bool
	fragment_event_reserved bool
	vertex_event_slot u32
	fragment_event_slot u32
	vertex_stamp_value u32
	fragment_stamp_value u32
	submitted bool
	fragment SharedBuffer
	vertex SharedBuffer
	barrier SharedBuffer
	init_buffer SharedBuffer
	fragment_microsequence SharedBuffer
	vertex_microsequence SharedBuffer
	scene G13RenderSceneResources
	scene_reserved bool
}
struct G13ComputeJobResources {
mut:
	released bool
	context &mmu.UatContext = unsafe { nil }
	queue &G13QueueResources = unsafe { nil }
	preempt &mmu.UatBuffer = unsafe { nil }
	explicit_barriers []u64
	event_reserved bool
	event_slot u32
	stamp_value u32
	submitted bool
	command SharedBuffer
	microsequence SharedBuffer
	timestamps SharedBuffer
}
fn release_g13_barrier_pins(mut pins []u64) { pins.clear() }
fn (_ &GpuManager) release_g13_tpc_locked(mut context mmu.UatContext, cache &TailCache) { assert context.active && cache == unsafe { nil } }
fn (manager &GpuManager) invalidate_g13_driver_buffer(mut context mmu.UatContext, buffer &mmu.UatBuffer) bool { return !manager.teardown_refuse && context.active && buffer != unsafe { nil } }
fn (manager &GpuManager) invalidate_g13_tpc_locked(mut context mmu.UatContext, _ &TailCache) bool { return context.active && !manager.teardown_refuse }
fn (manager &GpuManager) invalidate_g13_shared_buffer(mut buffer SharedBuffer) bool { if manager.teardown_refuse { return false }; buffer.mapped = false; return true }
fn (manager &GpuManager) invalidate_g13_queue_mappings_locked(mut resources G13QueueResources) bool { return !resources.released && !manager.teardown_refuse }
fn (manager &GpuManager) defer_g13_context_locked(mut resources G13QueueResources) bool { return !resources.released && !manager.teardown_refuse }
struct OwnedBuffer { class int record &alloc.Allocation }
