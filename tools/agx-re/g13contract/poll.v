// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_sync_file_poll_contract(drm string, objects string, events string, reference string) ! {
	poll := section(drm, 'fn (mut this SyncFileResource) poll_status(', 'fn (mut this SyncFileResource) mmap(', 'Vinix sync-file poll')!
	require(poll.contains('syncobj.poll_fence(this.fence, unsafe { &this.poll_event }, unsafe { &this.event })')
		&& poll.contains('{ file.pollin } else { 0 }') && !poll.contains('this.status'), 'Poll must register and read immutable fence readiness')!
	close := section(drm, 'fn (mut this SyncFileResource) unref(', 'fn (mut this SyncFileResource) link(', 'Vinix sync-file close')!
	require_order(close, ['katomic.dec(mut &this.refcount)',
		'syncobj.cancel_fence_event(this.fence, unsafe { &this.poll_event })',
		'memory.free(voidptr(this.box))', 'memory.free(voidptr(this))'], 'Final close must cancel before retiring borrowed event storage')!
	registration := section(events, 'pub fn poll_fence(', '// Final descriptor release', 'Vinix poll subscription')!
	require_order(registration, ['enable_array(fence)', 'drain_chain_notifications()',
		'return poll_leaf_event(fence, node, target, unsafe { nil })', 'pub fn poll_leaf_event(',
		'f.lock.acquire()', 'defer { f.lock.release() }', 'if f.signaled { return true }',
		'if n.fence == unsafe { nil }', 'n.fence = unsafe { fence }', 'n.event = unsafe { target }',
		'n.generation = unsafe { generation }',
		'n.next = unsafe { f.poll_events }', 'f.poll_events = unsafe { node }'], 'Readiness and one borrowed registration share completion lock')!
	cancel := section(events, 'pub fn cancel_fence_event(', '// Caller holds the fence lock', 'Vinix poll cancellation')!
	require_order(cancel, ['f.lock.acquire()', 'defer { f.lock.release() }', 'if voidptr(n.fence) != voidptr(fence) { return }',
		'voidptr(cursor) == voidptr(node)', 'f.poll_events = unsafe { cursor.next }', 'previous.next = cursor.next',
		'n.fence = unsafe { nil }; n.next = unsafe { nil }; n.event = unsafe { nil }; n.generation = unsafe { nil }'], 'Cancellation must take immutable fence lock even after signal detaches')!
	notify := events.all_after('fn (mut f DmaFence) notify_events_locked()')
	require_order(notify, ['f.poll_events = unsafe { node.next }', 'mut target := unsafe { node.event }',
		'mut generation := unsafe { node.generation }',
		'node.fence = unsafe { nil }; node.next = unsafe { nil }; node.event = unsafe { nil }',
		'node.generation = unsafe { nil }', 'directional := generation != unsafe { nil }',
		'if directional { katomic.inc(mut generation) }',
		'event.trigger(mut target, directional)'], 'Detach borrowed links before notifying under the completion lock')!
	for pair in [['fn complete_fence(', '// Leaves use a lock-free read.']] {
		completion := section(objects, pair[0], pair[1], 'Vinix first-completion poll wake')!
		require_order(completion, ['f.lock.acquire()', 'if f.signaled', 'return',
			'katomic.store(mut &f.signaled, true)', 'f.notify_events_locked()', 'f.lock.release()'],
			'Only first completion may notify, while holding its lock')!
	}
	linux_poll := section(reference, 'static __poll_t sync_file_poll(', 'static long sync_file_ioctl_merge(', 'Linux sync-file poll')!
	require_order(linux_poll, ['poll_wait(file, &sync_file->wq, wait)', 'POLL_ENABLED',
		'dma_fence_add_callback', 'fence_check_cb_func', 'dma_fence_is_signaled(sync_file->fence) ? EPOLLIN : 0'], 'Linux callback-backed readiness')!
	linux_close := section(reference, 'static int sync_file_release(', 'static __poll_t sync_file_poll(', 'Linux callback retirement')!
	require_order(linux_close, ['dma_fence_remove_callback', 'dma_fence_put', 'kfree(sync_file)'], 'Linux close removes callback before freeing owner')!
	require(reference.contains('wake_up_all(&sync_file->wq)'), 'Linux fence callback must wake pollers')!
}
