module g13contract

import g13layout
import os

fn test_poll_guards_reject_stale_readiness_unlocked_cancellation_and_missing_wakes() {
	repo := g13layout.repo_root()
	drm := os.read_file(repo + '/kernel/drm/drm.v')!
	objects := os.read_file(repo + '/kernel/drm/syncobj/syncobj.v')!
	events := os.read_file(repo + '/kernel/drm/syncobj/events.v')!
	reference := 'wake_up_all(&sync_file->wq);\nstatic int sync_file_release(\n' +
		'dma_fence_remove_callback();\ndma_fence_put();\nkfree(sync_file);\n' +
		'static __poll_t sync_file_poll(\npoll_wait(file, &sync_file->wq, wait);\nPOLL_ENABLED;\n' +
		'dma_fence_add_callback(fence, cb, fence_check_cb_func);\n' +
		'dma_fence_is_signaled(sync_file->fence) ? EPOLLIN : 0;\nstatic long sync_file_ioctl_merge('
	check_sync_file_poll_contract(drm, objects, events, reference)!
	for token in ['syncobj.poll_fence(this.fence, unsafe { &this.poll_event }, unsafe { &this.event })',
		'syncobj.cancel_fence_event(this.fence, unsafe { &this.poll_event })'] {
		if _ := check_sync_file_poll_contract(drm.replace(token, ''), objects, events, reference) { assert false, token }
	}
	for token in ['f.lock.acquire()', 'if n.fence == unsafe { nil }',
		'f.poll_events = unsafe { node.next }', 'previous.next = cursor.next', 'event.trigger(mut target, false)'] {
		if _ := check_sync_file_poll_contract(drm, objects, events.replace(token, ''), reference) { assert false, token }
	}
	if _ := check_sync_file_poll_contract(drm, objects.replace('f.notify_events_locked()', ''), events, reference) { assert false }
	if _ := check_sync_file_poll_contract(drm, objects, events, reference.replace('dma_fence_remove_callback();', '')) { assert false }
}
