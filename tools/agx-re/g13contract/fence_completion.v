// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_fence_completion_contract(local string, reference string) ! {
	success := section(local, 'pub fn signal(fence &DmaFence)',
		'// Signal a fence with an error code.', 'Vinix successful fence completion')!
	failure := section(local, 'pub fn signal_error(fence &DmaFence, err int)',
		'// Check whether a fence has been signaled', 'Vinix failed fence completion')!
	for source in [success, failure] {
		require_order(source, ['f.lock.acquire()', 'if f.signaled {', 'f.lock.release()',
			'return', 'katomic.store(mut &f.signaled, true)',
			'for mut w in f.waiters', 'if !w.triggered', 'w.callback(fence)', 'f.lock.release()'],
			'Vinix first-completion guard and release publication')!
	}
	require_order(failure, ['if f.signaled {', 'return', 'f.error = err',
		'katomic.store(mut &f.signaled, true)'], 'Vinix completed fence status preservation')!
	require(!success.contains('f.error ='), 'Plain signaling must preserve an owner-prepared error')!
	completion := section(reference, 'void dma_fence_signal_timestamp_locked(',
		'EXPORT_SYMBOL(dma_fence_signal_timestamp_locked)', 'Linux first fence completion')!
	require_order(completion, ['dma_fence_assert_held(fence)',
		'if (unlikely(test_and_set_bit(DMA_FENCE_FLAG_SIGNALED_BIT,',
		'&fence->flags)))', 'return;', 'trace_dma_fence_signaled',
		'list_for_each_entry_safe', 'cur->func(fence, cur)'], 'Linux first fence completion and under-lock callback contract')!
}
