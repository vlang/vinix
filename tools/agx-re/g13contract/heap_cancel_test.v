module g13contract

import g13layout

fn test_unpublished_cancellation_preserves_pending_owners() {
	root := g13layout.repo_root()
	allocator := read(root + '/kernel/gpu/agx/alloc/alloc.v')!
	manager := read(root + '/kernel/gpu/agx/gpu/gpu.v')!
	table := read(root + '/kernel/gpu/agx/pgtable/pgtable.v')!
	check_heap_cancel_local(allocator, manager, table)!
	for token in ['if record.va != va || !record.in_use { continue }', 'h.allocations.delete(index)', 'free(record)'] {
		if _ := check_heap_cancel_local(allocator.replace(token, ''), manager, table) { assert false, token }
	}
	if _ := check_heap_cancel_local(allocator, manager.replace('heap.cancel_unpublished(va)', 'heap.release(va)\n\t\theap.gc()'), table) { assert false }
	if _ := check_heap_cancel_local(allocator, manager, table.replace('pt.invalidate_range_locked(iova, size)', '')) { assert false }
}
