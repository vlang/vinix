// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_wait_capture_contract(drm string, objects string, captures string, reference string) ! {
	prepare := section(captures, 'pub fn prepare_capture(', 'pub fn captured_fence(', 'Vinix wait capture registration')!
	require_order(prepare, ['o.lock.acquire()', 'c.object =', 'c.fence = unsafe { o.fence }',
		'if c.fence == unsafe { nil } && wait_for_submit {', 'c.next =', 'c.pending = true',
		'o.pending_captures =', 'o.lock.release()'], 'Vinix atomic snapshot/registration')!
	read := section(captures, 'pub fn captured_fence(', '// Called with the object lock held.', 'Vinix capture read')!
	require_order(read, ['o.lock.acquire()', 'defer { o.lock.release() }', 'if capture.fence ==', 'return unsafe { capture.fence }'], 'Vinix locked capture reads')!
	publish := section(captures, 'fn (mut obj SyncObj) publish_captures_locked(', '// Unlink before', 'Vinix capture publication')!
	require_order(publish, ['if fence == unsafe { nil } { return }', 'obj.pending_captures = unsafe { nil }',
		'for cursor !=', 'next :=', 'cursor.fence =', 'cursor.next = unsafe { nil }',
		'cursor.pending = false', 'cursor = unsafe { next }'], 'Vinix first publication detaches borrowed nodes')!
	require(!publish.contains('.object ='), 'Publication must not change the caller-owned object identity')!
	replace := section(objects, 'pub fn replace_fence(', '// Snapshot a binary syncobj fence', 'Vinix syncobj replacement')!
	require_order(replace, ['o.lock.acquire()', 'o.fence =', 'o.publish_captures_locked(fence)', 'o.lock.release()'], 'Vinix publication stays under object lock')!
	release := captures.all_after('pub fn release_capture(')
	require_order(release, ['o.lock.acquire()', 'if c.pending {', 'voidptr(cursor) == voidptr(capture)',
		'o.pending_captures =', 'previous.next =', 'c.object = unsafe { nil }',
		'c.next = unsafe { nil }', 'c.fence = unsafe { nil }', 'c.pending = false', 'o.lock.release()'], 'Vinix unlink before stack retirement')!
	wait := section(drm, 'fn ioctl_syncobj_wait(', 'fn ioctl_syncobj_reset(', 'Vinix signal-interruptible wait')!
	require_order(wait, ['defer {', 'syncobj.release_capture(', 'syncobj.prepare_capture(',
		'if ready {', 'request.timeout_nsec <= 0', 'proc.current_thread()',
		'katomic.load(&waiting_thread.must_exit)', 'proc.pending_signals(waiting_thread) & ~waiting_thread.masked_signals',
		'return -proc.interrupted_errno', 'sched.reschedule()'], 'Vinix wait outcome precedence and signal interruption')!
	add := section(reference, 'static void drm_syncobj_fence_add_wait(', 'static void drm_syncobj_remove_wait(', 'Linux wait registration')!
	require_order(add, ['spin_lock(&syncobj->lock)', 'fence = dma_fence_get(',
		'list_add_tail(&wait->node, &syncobj->cb_list)', 'wait->fence = fence', 'spin_unlock(&syncobj->lock)'], 'Linux atomic snapshot/registration')!
	ref_replace := section(reference, 'void drm_syncobj_replace_fence(', 'EXPORT_SYMBOL(drm_syncobj_replace_fence)', 'Linux syncobj replacement')!
	require_order(ref_replace, ['spin_lock(&syncobj->lock)', 'rcu_assign_pointer(syncobj->fence, fence)',
		'syncobj_wait_syncobj_func(syncobj, wait_cur)', 'spin_unlock(&syncobj->lock)'], 'Linux replacement captures waiting submissions')!
	ref_wait := section(reference, 'static signed long drm_syncobj_array_wait_timeout(', '* drm_timeout_abs_to_jiffies', 'Linux wait cleanup/interruption')!
	require_order(ref_wait, ['if (timeout == 0)', 'if (signal_pending(current))', 'timeout = -ERESTARTSYS',
		'schedule_timeout(timeout)', 'cleanup_entries:', 'drm_syncobj_remove_wait(syncobjs[i], &entries[i])'], 'Linux wait interruption and final detachment')!
}
