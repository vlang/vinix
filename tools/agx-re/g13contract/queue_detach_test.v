module g13contract

import g13layout

fn test_queue_detach_guards_require_namespace_visibility_and_owner_ordering() {
	root := g13layout.repo_root()
	file := read(root + '/kernel/gpu/agx/file/file.v')!
	pending := read(root + '/kernel/gpu/agx/file/pending.v')!
	workqueue := read(root + '/kernel/gpu/agx/workqueue/workqueue.v')!
	manager := read(root + '/kernel/gpu/agx/gpu/gpu.v')!
	check_queue_detach_local(file, pending, workqueue, manager)!
	for token in ['q.detached = true', 'if !q.detached { continue }',
		'if ownership.resources.has_file_references() { continue }', 'file_map_lock.acquire()',
		'if queue.id != queue_id || queue.detached { continue }'] {
		if _ := check_queue_detach_local(file.replace(token, ''), pending, workqueue, manager) { assert false, token }
	}
	if _ := check_queue_detach_local(file, pending.replace('reap_open_detached_g13_queues()', ''), workqueue, manager) { assert false }
	if _ := check_queue_detach_local(file, pending, workqueue, manager.replace('mgr.lock.release()\n\tif callback', 'if callback')) { assert false }
}

fn test_queue_detach_reference_guard_requires_remove_and_retained_jobs() {
	file := 'pub(crate) fn queue_destroy( queues().remove(data.queue_id as usize); if queue.is_none() { Err(ENOENT) } else { Ok(0) }\n/// IOCTL: submit:'
	queue := 'fn new_job(&mut self, fence: wq: self.wq.clone() struct SubQueueJob wq: Arc<workqueue::WorkQueue::ver>'
	check_queue_detach_reference(file, queue)!
	if _ := check_queue_detach_reference(file.replace('Ok(0)', 'Err(EBUSY)'), queue) { assert false }
	if _ := check_queue_detach_reference(file, queue.replace('self.wq.clone()', 'self.wq')) { assert false }
}
