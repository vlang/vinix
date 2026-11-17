module g13contract

import g13layout

fn test_deferred_context_snapshot_and_allocator_order() {
	root := g13layout.repo_root()
	context := read(root + '/kernel/gpu/agx/gpu/g13_context.v')!
	queues := read(root + '/kernel/gpu/agx/gpu/g13.v')!
	manager := read(root + '/kernel/gpu/agx/gpu/gpu.v')!
	check_context_defer_local(context, queues, manager)!
	for token in ['resources.context_retirement = .queued', 'current = resources.context_next',
		'&& resources.context_retirement == .queued', 'mgr.g13_context_tail.context_next = &resources'] {
		if _ := check_context_defer_local(context.replace(token, ''), queues, manager) { assert false, token }
	}
	if _ := check_context_defer_local(context, queues, manager.replace('mgr.collect_g13_context_garbage_locked()', '')) { assert false }
	if _ := check_context_defer_local(context, queues.replace('resources.context_next = unsafe { nil }', ''), manager) { assert false }
}
