module g13contract

import g13layout

fn test_heap_gc_barrier_snapshots_and_allocation_entry() {
	root := g13layout.repo_root()
	source := read(root + '/kernel/gpu/agx/gpu/g13_garbage.v')!
	manager := read(root + '/kernel/gpu/agx/gpu/gpu.v')!
	wire := read(root + '/kernel/gpu/agx/fw/channels.v')!
	check_heap_gc_local(source, manager, wire)!
	for token in ['16 * 1024 * 1024', '2048', 'if !mgr.flush_g13_fw_cache_locked()',
		'mgr.g13_private.collect_garbage(private_count)', 'mgr.g13_gpu_readonly.collect_garbage(readonly_count)',
		'enqueue_with_token(voidptr(&message)) or { return false }', 'read_pointer() != token'] {
		if _ := check_heap_gc_local(source.replace(token, 'false'), manager, wire) { assert false, token }
	}
	if _ := check_heap_gc_local(source, manager.replace('mgr.collect_g13_heap_garbage_locked()', ''), wire) { assert false }
	if _ := check_heap_gc_local(source, manager, wire.replace('0x11', '0x14')) { assert false }
}
