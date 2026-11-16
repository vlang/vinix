// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_timeline_boundary_contract(objects string, staging string, reference string, asahi string) ! {
	lookup := objects.all_after('pub fn get_timeline_fence(')
	require_order(lookup, ['if obj == unsafe { nil } || value == 0', 'o.lock.acquire()', 'defer {', 'o.lock.release()',
		'mut later_value := u64(0)', 'mut later_fence := &DmaFence(unsafe { nil })', 'for point in o.timeline_points',
		'point.value == value && point.fence != unsafe { nil }', 'return unsafe { point.fence }',
		'point.value > value && (later_fence == unsafe { nil } || point.value < later_value)',
		'&& point.fence != unsafe { nil }', 'later_value = point.value', 'later_fence = unsafe { point.fence }',
		'if later_fence != unsafe { nil }', 'return later_fence'], 'Unsigned nearest-later selection without a numeric sentinel')!
	require(!lookup.contains('~u64(0)') && !lookup.contains('i64(') && !lookup.contains('memory.'),
		'Timeline lookup must not reserve a valid u64 point, narrow values or allocate')!
	require_order(staging, ['timeline_values [64]u64', 'pub fn stage_sync_array(',
		'item.timeline_value == 0', 'if input', 'syncobj.get_timeline_fence(object, item.timeline_value)',
		'fences[index] = fence'], 'Native Asahi input preserves unsigned point and stable fence')!
	require_order(staging.all_after('pub fn install_output_syncs('), ['if staged.timeline[index]',
		'syncobj.add_timeline_point(object, staged.timeline_values[index], fence)'], 'Native Asahi timeline output publication')!
	find := section(reference, 'int dma_fence_chain_find_seqno(', 'EXPORT_SYMBOL(dma_fence_chain_find_seqno)', 'Linux timeline lookup boundary')!
	require_order(find, ['uint64_t seqno', 'if (!seqno)', 'chain->base.seqno < seqno',
		'return -EINVAL', 'prev_seqno < seqno', 'return 0'], 'Linux unsigned upper-bound lookup')!
	require_order(asahi, ['pub(crate) timeline_value: u64', '.chain_find_seqno(data.timeline_value)?'], 'Packaged Asahi full-width timeline lookup')!
}
