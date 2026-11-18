// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_queue_unwind_local(source string) ! {
	constructor := section(source, 'pub fn (mut mgr GpuManager) create_g13_queue_resources(', 'pub fn (mut mgr GpuManager) release_g13_queue_resources(', 'Queue constructor ownership')!
	require_order(constructor, ['retained &&G13QueueResources', 'unsafe { *retained = nil }',
		'mgr.lock.acquire()', 'defer {', 'mgr.lock.release()', 'mut resources := &G13QueueResources{',
		'mut complete := false', 'defer {', 'if !complete {',
		'if !mgr.free_g13_queue_resources_locked(mut resources, resources.mappings_published) {',
		'resources.quarantined = true', 'mgr.g13_queues << resources', 'unsafe { *retained = resources }', '} else {',
		'unsafe { free(resources) }', 'resources.context =', 'resources.mappings_published = true',
		'if !mgr.flush_g13_queue_mappings(resources)', 'mgr.g13_queues << resources', 'complete = true', 'return resources'],
		'Transfer quarantined metadata and free fully unwound metadata before unlocking')!
	require(constructor.count('free(resources)') == 1, 'Exactly one source failure-only metadata free')!
}

fn check_queue_unwind_reference(queue string, buffer string, types string, allocator string) ! {
	constructor := section(queue, '        let mut ret = Queue::ver {', '\nconst SQ_RENDER:', 'Asahi owned queue construction')!
	require_order(constructor, ['gpu_context: Arc::new(', 'workqueue::GpuContext::new(', 'ret.q_vtx =',
		'workqueue::WorkQueue::ver::new(', 'ret.q_frag =', 'ret.q_comp =', 'Ok(ret)'], 'Fallible construction owns partial queue fields until successful return')!
	require(queue.contains('workqueue::GpuContext::new(dev.clone(), alloc, buffer.any_ref())?')
		&& types.contains('pub(crate) _buffer: Arc<dyn core::any::Any + Send + Sync>'), 'Deferred context owns the erased buffer reference')!
	inner := section(buffer, 'struct BufferInner {', '/// Locked and reference counted TVB buffer.', 'Asahi retained TVB owners')!
	require(inner.contains('ualloc: Arc<Mutex<alloc::DefaultAllocator>>') && inner.contains('ualloc_priv: Arc<Mutex<alloc::DefaultAllocator>>'), 'TVB retains both per-VM allocators')!
	require(buffer.contains('pub(crate) fn any_ref(&self) -> Arc<dyn core::any::Any + Send + Sync> {\n        self.inner.clone()'), 'Erased reference clones the retained TVB owner')!
	for name in ['SimpleAllocator', 'HeapAllocator'] {
		owned := section(allocator, 'pub(crate) struct ' + name + ' {', '\n}', 'Asahi allocator VM owner')!
		require(owned.contains('vm: mmu::Vm'), 'Both allocator policies retain their VM')!
	}
}
