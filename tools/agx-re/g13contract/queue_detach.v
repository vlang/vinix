// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_queue_detach_local(file string, pending string, workqueue string, manager string) ! {
	require(workqueue.contains('detached       bool'), 'Host queue must distinguish namespace removal from backing retirement')!
	destroy := section(file, 'pub fn (mut f GpuFile) ioctl_queue_destroy(', 'fn discard_g13_completion(', 'G13 queue detach')!
	require_order(destroy, ['f.lock.acquire()', 'q.id == request.queue_id && !q.detached',
		'if g13_resources != unsafe { nil } {', 'q.detached = true',
		'f.reap_detached_g13_queues_locked()', 'f.lock.release()', 'return 0',
		'manager := gpu.get_global_manager()', 'q.destroy()', 'return -2'], 'G13 namespace removal precedes fallible physical retirement; legacy backend retains its path')!
	reap := section(file, 'fn (mut f GpuFile) reap_detached_g13_queues_locked()', '// The registry lock pins', 'G13 detached owner retirement')!
	require_order(reap, ['manager := gpu.get_global_manager() or { return }',
		'if !q.detached { continue }', 'ownership.queue_id == q.id',
		'katomic.load(&f.inflight_by_vm[ownership.vm_id]) != 0',
		'if !gpu_manager.release_g13_queue_resources(ownership.resources) { continue }',
		'q.destroy()', 'f.queues.delete(i)', 'f.g13_queues.delete(owner_index)'], 'Retain owner through aggregate VM pins and failed invalidation')!
	registry := section(file, 'fn reap_open_detached_g13_queues()', 'pub fn (mut f GpuFile) ioctl_queue_destroy(', 'Open file reaper pin')!
	require_order(registry, ['file_map_lock.acquire()', 'for _, file in file_map',
		'owned.lock.acquire()', 'owned.reap_detached_g13_queues_locked()',
		'owned.lock.release()', 'file_map_lock.release()'], 'Registry lock pins the file through nested file/manager retirement')!
	for token in ['if queue.id == queue_id && !queue.detached { return true }',
		'if queue.id == request.queue_id && !queue.detached {'] { require(file.contains(token), 'Both submission lookups must hide detached queues')! }
	service := pending.all_after('pub fn service_file_work()')
	require_order(service, ['process_pending_submissions()', 'reap_open_detached_g13_queues()', 'reap_closed_files()'], 'Retire aggregate owners before retrying open and closed files')!
	retire := section(pending, 'fn process_pending_submissions()', 'pub fn service_file_work()', 'Aggregate queue ownership')!
	require_order(retire, ['assert katomic.load(&item.callbacks_remaining) == 0',
		'signal_g13_submission_fence(', 'katomic.dec(mut &item.file.inflight_by_vm[item.vm_id])',
		'memory.free(voidptr(item))'], 'Last aggregate queue use precedes releasing its VM owner')!
	callback := section(manager, 'fn (mut mgr GpuManager) reap_file_resources()', '// Serialize accepted submissions', 'Worker lock ordering')!
	require_order(callback, ['mgr.lock.acquire()', 'callback := mgr.file_reaper', 'mgr.lock.release()', 'callback()'], 'Service callback runs outside manager lock')!
}

fn check_queue_detach_reference(file string, queue string) ! {
	destroy := section(file, 'pub(crate) fn queue_destroy(', '/// IOCTL: submit:', 'Packaged queue destroy')!
	require_order(destroy, ['queues().remove(data.queue_id as usize)', 'if queue.is_none()', 'Err(ENOENT)', 'Ok(0)'], 'Packaged queue namespace removal succeeds independently of live jobs')!
	require(!destroy.contains('EBUSY'), 'Packaged queue destroy busy policy changed')!
	require_order(queue, ['fn new_job(&mut self, fence:', 'wq: self.wq.clone()', 'struct SubQueueJob',
		'wq: Arc<workqueue::WorkQueue::ver>'], 'Packaged accepted jobs retain workqueue ownership')!
}
