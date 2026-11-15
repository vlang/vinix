module g13contract

import g13layout
import os

fn test_capture_guard_rejects_unlocked_or_unretired_borrows() {
	repo := g13layout.repo_root()
	drm := os.read_file(repo + '/kernel/drm/drm.v')!
	objects := os.read_file(repo + '/kernel/drm/syncobj/syncobj.v')!
	captures := os.read_file(repo + '/kernel/drm/syncobj/capture.v')!
	reference := 'static void drm_syncobj_fence_add_wait(\nspin_lock(&syncobj->lock);\nfence = dma_fence_get();\n' +
		'list_add_tail(&wait->node, &syncobj->cb_list);\nwait->fence = fence;\nspin_unlock(&syncobj->lock);\n' +
		'static void drm_syncobj_remove_wait(\nvoid drm_syncobj_replace_fence(\nspin_lock(&syncobj->lock);\n' +
		'rcu_assign_pointer(syncobj->fence, fence);\nsyncobj_wait_syncobj_func(syncobj, wait_cur);\n' +
		'spin_unlock(&syncobj->lock);\nEXPORT_SYMBOL(drm_syncobj_replace_fence)\n' +
		'static signed long drm_syncobj_array_wait_timeout(\nif (timeout == 0)\nif (signal_pending(current))\n' +
		'timeout = -ERESTARTSYS;\nschedule_timeout(timeout);\ncleanup_entries:\ndrm_syncobj_remove_wait(syncobjs[i], &entries[i]);\n* drm_timeout_abs_to_jiffies'
	check_wait_capture_contract(drm, objects, captures, reference)!
	for token in ['o.lock.acquire()', 'c.pending = true', 'cursor.pending = false',
		'obj.pending_captures = unsafe { nil }', 'previous.next =', 'c.object = unsafe { nil }'] {
		if _ := check_wait_capture_contract(drm, objects, captures.replace(token, ''), reference) { assert false, token }
	}
	if _ := check_wait_capture_contract(drm.replace('syncobj.release_capture(', ''), objects, captures, reference) { assert false }
	if _ := check_wait_capture_contract(drm, objects.replace('o.publish_captures_locked(fence)', ''), captures, reference) { assert false }
	if _ := check_wait_capture_contract(drm, objects, captures, reference.replace('timeout = -ERESTARTSYS;', '')) { assert false }
}
