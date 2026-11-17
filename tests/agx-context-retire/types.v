@[has_globals]
module gpu

import klock

__global higher_half = u64(0)
__global context_test_queue = unsafe { &G13QueueResources(nil) }
__global context_test_unpublished = false

struct ContextRenderBuffer {}
struct ContextSubqueue { mut: lock klock.Lock info SharedBuffer ring SharedBuffer state SharedBuffer gpu_buffer SharedBuffer }
struct G13QueueResources {
mut:
	context SharedBuffer
	context_retirement G13ContextRetirement
	context_next &G13QueueResources = unsafe { nil }
	released bool
	render_buffer ContextRenderBuffer
	subqueues [3]ContextSubqueue
	notifier SharedBuffer
	threshold SharedBuffer
	notifier_list SharedBuffer
}
fn (_ &GpuManager) free_g13_render_buffer_locked(mut buffer ContextRenderBuffer) { buffer = ContextRenderBuffer{} }
fn (mut manager GpuManager) invalidate_g13_queue_mappings_locked(mut resources G13QueueResources) bool {
	assert resources.context_retirement == .complete, 'queue mappings must wait for acknowledged context retirement'
	manager.context_map_calls++
	resources.context.mapped = false
	return !manager.context_refuse_map && manager.state == .running
}
fn (mut manager GpuManager) free_shared_buffer(mut buffer SharedBuffer) {
	if buffer.va == 0 && buffer.phys == 0 { return }
	assert context_test_queue.released
	assert context_test_queue.context_next == unsafe { nil }, 'backing release must leave no deferred node link'
	assert manager.g13_context_head != context_test_queue && manager.g13_context_tail != context_test_queue,
		'backing release must follow removal of deferred roots'
	assert context_test_queue.context_retirement == .complete || context_test_unpublished,
		'context backing must remain owned until acknowledgement or stopped/unpublished teardown'
	manager.context_backing_calls++
	assert manager.context_backing_calls == 1, 'context backing releases once'
	buffer = SharedBuffer{}
}
