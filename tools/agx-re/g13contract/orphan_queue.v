// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_orphan_queue_local(file string, gpu string, worker string) ! {
	reap := section(file, 'fn (mut f GpuFile) reap_orphaned_g13_queues_locked()', '// The registry lock pins', 'Unpublished G13 queue cleanup')!
	require_order(reap, ['manager := gpu.get_global_manager() or { return }',
		'index := f.g13_queues.len - 1', 'ownership := f.g13_queues[index]',
		'for queue in f.queues', 'if queue.id == ownership.queue_id { named = true; break }',
		'if named || ownership.resources.has_file_references() { continue }',
		'if !gpu_manager.release_g13_queue_resources(ownership.resources) { continue }',
		'f.g13_queues.delete(index)', 'gpu.free_g13_queue_record(ownership.resources)'], 'Exclude every logical/captured owner and delete only after acknowledged release')!
	for token in ['inflight_by_vm', 'detached_vms', 'queue.detached', 'q.destroy()', 'free(', 'memory.'] {
		require(!reap.contains(token), 'Unpublished cleanup preserves ownership gates and uses checked metadata disposal')!
	}
	registry := section(file, 'fn reap_open_detached_g13_queues()', 'pub fn (mut f GpuFile) ioctl_queue_destroy(', 'Open-file retry ownership')!
	require_order(registry, ['file_map_lock.acquire()', 'owned.lock.acquire()',
		'owned.reap_detached_g13_queues_locked()', 'owned.reap_orphaned_g13_queues_locked()',
		'owned.reap_detached_vms_locked()', 'owned.lock.release()', 'file_map_lock.release()'], 'Retry unpublished resources before final VM release under registry/file locks')!
	create := section(file, 'pub fn (mut f GpuFile) ioctl_queue_create(', 'fn (mut f GpuFile) reap_detached_g13_queues_locked()', 'Failed queue adoption')!
	require_order(create, ['f.lock.acquire()', 'defer { f.lock.release() }',
		'gpu_manager.retained_g13_queue_resources(id, vm)',
		'f.g13_queues << G13QueueOwnership{ queue_id: id, vm_id: request.vm_id, resources: retained }',
		'queue.destroy()', 'unsafe { free(queue) }', 'return -12', 'f.queues << wq'], 'Construction adoption and successful publication stay under the same file lock')!
	manager := section(gpu, 'pub fn (mut mgr GpuManager) release_g13_queue_resources(', '// Quarantined backing must retire', 'Existing physical release gates')!
	require_order(manager, ['mgr.lock.acquire()', 'if owned.has_file_references()',
		'for job in mgr.g13_render_jobs', 'for job in mgr.g13_compute_jobs',
		'mgr.free_g13_queue_resources_locked(', 'owned.quarantined = true', 'return false',
		'mgr.g13_queues.delete(index)', 'return true'], 'Manager guards its exact jobs and failed invalidation independently of unrelated VM work')!
	service := section(worker, 'fn event_worker(', '// Shutdown the GPU', 'Worker retry and final stop drain')!
	require_order(service, ['mgr.reap_file_resources()', 'sched.reschedule()', 'mgr.shutdown()',
		'mgr.reap_file_resources()'], 'Both normal and final worker service retry retained file resources')!
}

fn check_orphan_queue_reference(file string, queue string) ! {
	create := section(file, 'pub(crate) fn queue_create(', '/// IOCTL: queue_destroy:', 'Packaged queue publication')!
	require_order(create, ['let mut queue = reg_data.gpu.new_queue(', 'queue.reserve_render_scs(data.render_scs_layout)?',
		'data.queue_id = resv.index().try_into()?', 'resv.fill(Arc::pin_init(new_mutex!(queue), GFP_KERNEL)?)?'], 'Only fully constructed owned queues enter the namespace')!
	constructor := section(queue, '    pub(crate) fn new(', '\nconst SQ_RENDER:', 'Packaged owned queue construction')!
	require_order(constructor, ['let mut notifier_list = alloc.shared.new_default', 'let threshold =',
		'let notifier:', 'let buffer =', 'let mut ret = Queue::ver {', 'ret.inner.buffer.ensure_blocks(tvb_blocks)?',
		'ret.q_vtx = Some(', 'ret.q_frag = Some(', 'ret.q_comp = Some(', 'Ok(ret)'], 'Fallible construction uses owned locals and partial fields before returning a queue')!
}
