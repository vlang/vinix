module g13contract

import g13layout
import os

fn test_fence_completion_guards_reject_status_rewrite_and_reference_drift() {
	local := os.read_file(g13layout.repo_root() + '/kernel/drm/syncobj/syncobj.v')!
	reference := 'void dma_fence_signal_timestamp_locked(\n' +
		'dma_fence_assert_held(fence);\n' +
		'if (unlikely(test_and_set_bit(DMA_FENCE_FLAG_SIGNALED_BIT, &fence->flags))) return;\n' +
		'trace_dma_fence_signaled(fence);\nlist_for_each_entry_safe(cur, tmp, &cb_list, node) cur->func(fence, cur);\n' +
		'EXPORT_SYMBOL(dma_fence_signal_timestamp_locked)'
	check_fence_completion_contract(local, reference)!
	for token in ['if f.signaled {', 'katomic.store(mut &f.signaled, true)'] {
		if _ := check_fence_completion_contract(local.replace(token, ''), reference) { assert false }
	}
	if _ := check_fence_completion_contract(local.replace('if f.signaled {', 'f.error = err\nif f.signaled {'), reference) { assert false }
	if _ := check_fence_completion_contract(local,
		reference.replace('if (unlikely(test_and_set_bit(DMA_FENCE_FLAG_SIGNALED_BIT, &fence->flags))) return;', '')) { assert false }
}
