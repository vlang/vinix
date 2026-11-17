// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_heap_cancel_local(allocator string, manager string, table string) ! {
	cancel := section(allocator, 'pub fn (mut h HeapAllocator) cancel_unpublished(', '// Collect every released record', 'Unpublished cancellation')!
	require_order(cancel, ['h.lock.acquire()', 'defer { h.lock.release() }',
		'if record.va != va || !record.in_use { continue }', 'assert record.release_order == 0',
		'h.retire_hole_order_locked(record.hole_order)', 'if record.va + record.size == h.top',
		'h.allocations.delete(index)', 'free(record)', 'return'], 'Only the selected live unpublished record is unlinked before destruction')!
	for token in ['garbage_count', 'garbage_bytes', 'h.release(', 'h.gc(', 'h.collect_garbage('] {
		require(!cancel.contains(token), 'Cancellation must preserve deferred FIFO accounting: ' + token)!
	}
	caller := section(manager, 'fn alloc_buffer_from_heap(', 'fn (mut mgr GpuManager) alloc_shared_buffer_with_protection(', 'Failed map rollback')!
	require_order(caller, ['if !uat_mgr.map_kernel(va, phys, aligned_size, protection)',
		'heap.cancel_unpublished(va)', 'memory.pmm_free(voidptr(phys), pages)', 'return none'], 'Only the unpublished failed reservation retires before physical backing')!
	require(!caller.contains('heap.release(') && !caller.contains('heap.gc('), 'Map failure cannot drain unrelated pending ranges')!
	mapping := section(table, 'pub fn (mut pt UatPgtable) map(', '// Repeat one physical', 'Page-table rollback')!
	require_order(mapping, ['defer {', 'pt.invalidate_range_locked(iova, size)', 'pt.lock.release()',
		'if !pt.map_page_locked(', 'pt.unmap_page_locked(', 'return false'], 'Failed map rolls back partial leaves and completes invalidation before returning')!
}

fn check_heap_cancel_reference(allocator string) ! {
	inner := section(allocator, 'fn alloc_inner(&mut self, size: usize, align: usize)', 'impl Allocator for HeapAllocator', 'Asahi unpublished allocation')!
	require_order(inner, ['let mut node = match self.mm.insert_node_generic(', 'self.add_block(block_size)?',
		'obj.0.vmap()?.addr', 'Ok(HeapAllocation(Some(node)))'], 'Asahi retains a local range node until all fallible allocation work completes')!
	require(!inner.contains('collect_garbage('), 'Asahi failed allocation does not drain unrelated garbage')!
}
