// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_queue_reference_local(file string, pending string, gpu string, vfs string) ! {
	capture := section(file, 'fn (mut f GpuFile) capture_submission_queue(', 'fn release_submission_queue(', 'Owned queue capture')!
	require_order(capture, ['f.lock.acquire()', 'defer { f.lock.release() }',
		'if queue.id != queue_id || queue.detached { continue }', 'ownership.queue_id == queue_id',
		'resources.retain_file_reference()', 'return G13SubmissionQueue{vm_id: queue.vm_id, caps: queue.caps, resources: resources, retained: true}'], 'Capture queue identity and owner under the namespace lock')!
	for token in ['memory.', 'usercopy.', 'inflight_by_vm', 'return queue'] { require(!capture.contains(token), 'Capture must not allocate, copy, borrow a logical queue or pin VM job admission')! }
	release := section(file, 'fn release_submission_queue(', '// Copy userspace input', 'Captured queue cleanup')!
	require_order(release, ['if !captured.retained { return }', 'captured.resources', 'resources.release_file_reference()'], 'Release exactly the owned queue reference')!
	submit := section(file, 'pub fn (mut f GpuFile) ioctl_submit(', 'fn dispatch(', 'Queue reference transfer')!
	require_order(submit, ['captured := f.capture_submission_queue(request.queue_id) or { return -2 }',
		'mut transferred := false', 'defer { if !transferred { release_submission_queue(captured) } }',
		'stage_storage := memory.malloc_packed_fallible', 'agxsubmission.stage_command_array(',
		'g13_submission_status()', 'f.lock.acquire()', 'vm_id := captured.vm_id',
		'f.cleanup_closed_mappings_locked(vm_id)', 'if !captured.retained { return -22 }',
		'queue_resources := captured.resources', 'katomic.inc(mut &f.inflight_by_vm[vm_id])',
		'if !register_g13_pending(', 'katomic.dec(mut &f.inflight_by_vm[vm_id])',
		'return -19', 'transferred = true', 'queued = true'], 'Owned capture survives staging and transfers only with accepted registration')!
	require(!submit.contains('for queue in f.queues') && !submit.contains('for ownership in f.g13_queues'), 'Captured state must not be resolved again by userspace name')!
	require(submit.count('katomic.inc(mut &f.inflight_by_vm[vm_id])') == 1 && submit.count('katomic.dec(mut &f.inflight_by_vm[vm_id])') == 1, 'Aggregate VM pin must keep its original registration balance')!
	retire := section(pending, 'fn process_pending_submissions()', 'pub fn service_file_work()', 'Last queue reference')!
	require_order(retire, ['assert katomic.load(&item.callbacks_remaining) == 0', 'signal_g13_submission_fence(',
		'queue.release_file_reference()', 'katomic.dec(mut &item.file.inflight_by_vm[item.vm_id])', 'memory.free(voidptr(item))'], 'Drop queue owner after final callbacks/fence access, before releasing the file pin')!
	refs := section(gpu, 'pub fn (mut queue G13QueueResources) retain_file_reference()', '// Caller holds mgr.lock. Asahi QueueInner', 'Scalar queue references')!
	require_order(refs, ['katomic.inc(mut &queue.file_references)', 'pub fn (mut queue G13QueueResources) release_file_reference()',
		'assert katomic.load(&queue.file_references) != 0', 'katomic.dec(mut &queue.file_references)',
		'pub fn (queue &G13QueueResources) has_file_references()', 'katomic.load(&queue.file_references) != 0'], 'Atomic owner count acquisition, release and zero test')!
	manager := section(gpu, 'pub fn (mut mgr GpuManager) release_g13_queue_resources(', '// Quarantined backing must retire', 'Normal physical queue release')!
	require_order(manager, ['mgr.lock.acquire()', 'if owned.has_file_references() { return false }', 'for job in mgr.g13_render_jobs',
		'for job in mgr.g13_compute_jobs', 'mgr.free_g13_queue_resources_locked('], 'Normal release respects queue captures and retained manager jobs')!
	ioctl := section(vfs, 'pub fn syscall_ioctl(', '\n}', 'Ioctl Handle owner')!
	require_order(ioctl, ['file.fd_from_fdnum(', 'defer {', 'fd.unref()'], 'Syscall Handle pins file through staging')!
}
