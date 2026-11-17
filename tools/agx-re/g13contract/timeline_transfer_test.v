// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

import g13layout

fn check_timeline_transfer(transfer string, merge string, array string, chain string, fences string, queue string, info string) ! {
	require_order(transfer, ['destination := syncobj.lookup_referenced(', 'defer { syncobj.release_syncobj(destination) }',
		'source := find_syncobj_fence(', 'if source.code != 0',
		'if request.dst_point != 0', 'syncobj.unwrap_merge(source.fence)', 'defer { syncobj.release_merge_reservation(merged) }',
		'syncobj.reserve_chain()', 'defer { syncobj.release_chain_reservation(chain) }', 'syncobj.add_chain_point(destination, chain, merged, request.dst_point)'], 'Private merge and chain reservations before destination effects')!
	require_order(merge, ['C.__builtin_alloca(sizeof(FenceUnwrap))', 'unwrap_first(head, cursor)', 'if count == 0 { return merge_stub(timestamp) }',
		'if count == 1 { return single }', 'memory.malloc_packed_fallible(', 'defer { if owned { memory.free(storage) } }',
		'count = 0', 'unwrap_first(head, cursor)', 'count = merge_dedup(items, count)', 'new_merge_array(items, count)', 'owned = false'], 'Count/fill fast paths, exact private cleanup and pointer-table handoff')!
	require(merge.contains('a.seqno > b.seqno') && merge.contains('a.context < b.context') && merge.contains('fence.merge_reserved = true'), 'Full-width latest-context merge with private timestamped stubs')!
	require_order(array, ['bytes := sizeof(DmaFence) +', 'memory.malloc_packed_fallible(bytes)', 'C.memset(allocation, 0, bytes)',
		'fence_array: true, merge_reserved: true', 'array_count: count, array_pending: count, array_fences: children', 'array_waiters: &ChainWaiter('], 'All immutable members and callback slots initialized before activation')!
	require(fences.contains('array_error i64 = 1') && array.contains('katomic.load(&f.array_error)'), 'Array error must retain its sign through ARM atomics')!
	require(array.contains('katomic.cas(mut &f.array_error, i64(1), i64(error_code))') && array.contains('katomic.dec(mut &f.array_pending)'), 'First error and final child counted atomically')!
	require_order(chain, ['if payload.merge_reserved { unsafe { payload.merge_reserved = false } }', 'register_chain_waiter(previous',
		'register_chain_waiter(payload'], 'Only private payload reservation changes before callback handoff')!
	require_order(chain.all_after('pub fn add_chain_point('), ['o.lock.release()', 'drain_chain_notifications()'], 'Drain completion after publication unlock')!
	require(queue.contains('context: if queue_context != 0 { queue_context } else { context }'), 'Different queues of one file must have distinct public contexts')!
	require(info.contains('syncobj.unwrap_first(fence, iterator)') && info.contains('syncobj.unwrap_next(iterator)') && info.contains(".fence_array { 'dma_fence_array' }"), 'Sync-file records flatten arrays')!
}

fn test_timeline_transfer_private_ownership_flat_arrays_and_queue_identity() {
	r := g13layout.repo_root()
	t := read(r + '/kernel/drm/syncobj_transfer.v')!; m := read(r + '/kernel/drm/syncobj/merge.v')!
	a := read(r + '/kernel/drm/syncobj/array.v')!; c := read(r + '/kernel/drm/syncobj/chain.v')!
	f := read(r + '/kernel/drm/syncobj/syncobj.v')!; q := read(r + '/kernel/drm/syncobj/queue.v')!; i := read(r + '/kernel/drm/sync_file_info.v')!
	check_timeline_transfer(t, m, a, c, f, q, i)!
	for token in ['defer { syncobj.release_merge_reservation(merged) }', 'defer { syncobj.release_chain_reservation(chain) }'] {
		if _ := check_timeline_transfer(t.replace(token, ''), m, a, c, f, q, i) { assert false, token }
	}
	for token in ['defer { if owned { memory.free(storage) } }', 'a.seqno > b.seqno', 'owned = false'] {
		if _ := check_timeline_transfer(t, m.replace(token, ''), a, c, f, q, i) { assert false, token }
	}
	if _ := check_timeline_transfer(t, m, a, c, f.replace('array_error i64', 'array_error int'), q, i) { assert false }
	if _ := check_timeline_transfer(t, m, a, c.replace('if payload.merge_reserved { unsafe { payload.merge_reserved = false } }', 'unsafe { payload.merge_reserved = false }'), f, q, i) { assert false }
	if _ := check_timeline_transfer(t, m, a, c, f, q.replace('context: if queue_context != 0 { queue_context } else { context }', 'context: context'), i) { assert false }
}
