// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_fence_completion_contract(local string, reference string) ! {
	success := section(local, 'pub fn signal(fence &DmaFence)',
		'// Signal a fence with an error code.', 'Vinix successful fence completion')!
	failure := section(local, 'pub fn signal_error(fence &DmaFence, err int)',
		'fn complete_fence(', 'Vinix failed fence completion')!
	require_order(success, ['if fence.chain', 'complete_fence(fence, 0, false)', 'drain_chain_notifications()'], 'Successful leaf completion and unlocked propagation')!
	require_order(failure, ['if fence.chain', 'complete_fence(fence, err, true)', 'drain_chain_notifications()'], 'Failed leaf completion and unlocked propagation')!
	completion_native := section(local, 'fn complete_fence(', '// Leaves use a lock-free read.', 'Vinix common first completion')!
	for source in [completion_native] {
		require_order(source, ['f.lock.acquire()', 'if f.signaled {', 'f.lock.release()',
			'return', 'f.timestamp_ns = time.monotonic_ns()', 'katomic.store(mut &f.signaled, true)',
			'for mut w in f.waiters', 'if !w.triggered', 'w.callback(fence)', 'f.lock.release()'],
			'Vinix first-completion guard and release publication')!
	}
	require_order(completion_native, ['if f.signaled {', 'return', 'if set_error { f.error = err }',
		'katomic.store(mut &f.signaled, true)'], 'Vinix completed fence status preservation')!
	require(!completion_native.all_before('if f.signaled {').contains('f.error'), 'No status rewrite before completion guard')!
	require(!success.contains('f.error ='), 'Plain signaling must preserve an owner-prepared error')!
	completion := section(reference, 'void dma_fence_signal_timestamp_locked(',
		'EXPORT_SYMBOL(dma_fence_signal_timestamp_locked)', 'Linux first fence completion')!
	require_order(completion, ['dma_fence_assert_held(fence)',
		'if (unlikely(test_and_set_bit(DMA_FENCE_FLAG_SIGNALED_BIT,',
		'&fence->flags)))', 'return;', 'trace_dma_fence_signaled',
		'list_for_each_entry_safe', 'cur->func(fence, cur)'], 'Linux first fence completion and under-lock callback contract')!
}
