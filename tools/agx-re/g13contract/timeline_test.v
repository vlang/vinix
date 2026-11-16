module g13contract

import g13layout

fn test_timeline_guard_rejects_max_sentinel_signed_values_and_lost_lock_or_staging() {
	repo := g13layout.repo_root()
	objects := read(repo + '/kernel/drm/syncobj/syncobj.v')!
	staging := read(repo + '/kernel/gpu/agx/submission/submission.v')!
	reference := 'int dma_fence_chain_find_seqno(struct dma_fence **pfence, uint64_t seqno) {\n' +
		'if (!seqno) return 0;\nif (chain->base.seqno < seqno) return -EINVAL;\n' +
		'if (prev_seqno < seqno) break;\nreturn 0;\n}\nEXPORT_SYMBOL(dma_fence_chain_find_seqno)'
	asahi := 'pub(crate) timeline_value: u64;\nfence.chain_find_seqno(data.timeline_value)?;'
	check_timeline_boundary_contract(objects, staging, reference, asahi)!
	for token in ['mut later_value := u64(0)', 'later_fence == unsafe { nil } || ', 'o.lock.acquire()',
		'o.lock.release()', 'point.value < later_value', 'point.fence != unsafe { nil }'] {
		if _ := check_timeline_boundary_contract(objects.replace(token, ''), staging, reference, asahi) { assert false, token }
	}
	for extra in ['~u64(0)', 'i64(value)', 'memory.malloc('] {
		if _ := check_timeline_boundary_contract(objects + extra, staging, reference, asahi) { assert false, extra }
	}
	if _ := check_timeline_boundary_contract(objects, staging.replace('item.timeline_value', '0'), reference, asahi) { assert false }
	if _ := check_timeline_boundary_contract(objects, staging, reference.replace('uint64_t', 'int64_t'), asahi) { assert false }
	if _ := check_timeline_boundary_contract(objects, staging, reference, asahi.replace('chain_find_seqno', 'other')) { assert false }
}
