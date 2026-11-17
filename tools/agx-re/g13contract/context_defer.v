// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_context_defer_local(context string, queues string, manager string) ! {
	append := section(context, 'fn (mut mgr GpuManager) append_g13_context_locked(', '\n}\n', 'Context FIFO append')!
	require_order(append, ['resources.context_next = unsafe { nil }', 'if mgr.g13_context_tail == unsafe { nil }',
		'mgr.g13_context_head = &resources', 'mgr.g13_context_tail.context_next = &resources', 'mgr.g13_context_tail = &resources'], 'Existing retained objects form a release-order FIFO')!
	defer_ctx := section(context, 'fn (mut mgr GpuManager) defer_g13_context_locked(', '\n}\n', 'Deferred context gate')!
	require_order(defer_ctx, ['if resources.context_retirement == .complete { return true }',
		'if resources.context_retirement == .fresh', 'resources.context_retirement = .queued',
		'mgr.append_g13_context_locked(mut resources)', 'return false'], 'Only fresh requests append, and completion gates cleanup')!
	require(!defer_ctx.contains('invalidate_g13_context_locked('), 'Retirement requests cannot publish inline')!
	drain := section(context, 'fn (mut mgr GpuManager) collect_g13_context_garbage_locked()', '\n}\n', 'Context snapshot drain')!
	require_order(drain, ['mgr.state != .running || mgr.hw_config.gpu_gen != .g13',
		'mut current := mgr.g13_context_head', 'mgr.g13_context_head = unsafe { nil }', 'mgr.g13_context_tail = unsafe { nil }',
		'for current != unsafe { nil }', 'mut resources := current', 'current = resources.context_next',
		'resources.context_next = unsafe { nil }', '!mgr.invalidate_g13_context_locked(mut resources)',
		'&& resources.context_retirement == .queued', 'mgr.append_g13_context_locked(mut resources)'], 'Detach the snapshot before processing; only unpublished failures may retry later')!
	allocation := section(manager, 'fn (mut mgr GpuManager) alloc_g13_buffer_with_protection(', '\n}\n', 'Allocator borrow')!
	require_order(allocation, ['pgtable.gpu_prot_gpu_ro_fw_private_rw { return none }', 'mgr.collect_g13_context_garbage_locked()',
		'mgr.collect_g13_heap_garbage_locked()', 'return match protection'], 'Context drain precedes threshold GC and allocator access')!
	stopped := section(queues, 'fn (mut mgr GpuManager) release_all_g13_queue_resources()', '\n}\n', 'Stopped context drain')!
	require_order(stopped, ['mgr.g13_context_head = unsafe { nil }', 'mgr.g13_context_tail = unsafe { nil }',
		'for index :=', 'resources.context_next = unsafe { nil }', 'mgr.free_g13_queue_resources_locked(mut resources, false)'], 'Stopped teardown clears intrusive roots and node links before bypass')!
}

fn check_context_defer_reference(manager string) ! {
	allocation := section(manager, "fn alloc(&self) -> Guard<'_, KernelAllocators, MutexBackend> {", '\n    fn bind_vm(', 'Asahi deferred contexts')!
	require_order(allocation, ['core::mem::swap(&mut *self.garbage_contexts.lock(), &mut garbage_ctx)',
		'for ctx in garbage_ctx', 'self.invalidate_context(&ctx)', 'let mut guard = self.alloc.lock()',
		'guard.private.garbage()'], 'Asahi drains a detached context snapshot before borrowing heaps')!
	free_ctx := section(manager, 'fn free_context(&self, ctx:', '\n}\n', 'Asahi context retirement request')!
	require_order(free_ctx, ['self.garbage_contexts.lock()', 'garbage.push(ctx, GFP_KERNEL)'], 'Asahi appends dropped contexts in release order')!
}
