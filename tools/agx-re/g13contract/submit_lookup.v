// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_submit_lookup_order_contract(local string, reference string) ! {
	probe := section(local, 'fn (mut f GpuFile) capture_submission_queue(',
		'pub fn (mut f GpuFile) ioctl_submit(', 'Native queue presence probe')!
	require_order(probe, ['f.lock.acquire()', 'defer { f.lock.release() }', 'for queue in f.queues',
		'if queue.id != queue_id || queue.detached { continue }', 'resources.retain_file_reference()',
		'return G13SubmissionQueue{', 'return none'], 'Serialized allocation-free owned queue capture')!
	for token in ['memory.', 'usercopy.', 'return queue', 'f.queues <<', 'f.queues.delete'] {
		require(!probe.contains(token), 'Queue probe must not stage, mutate or return a borrowed queue pointer')!
	}
	submit := section(local, 'pub fn (mut f GpuFile) ioctl_submit(', 'fn dispatch(', 'Native early queue lookup')!
	require_order(submit, ['request.extensions != 0 || request.flags != 0', 'return -22',
		'captured := f.capture_submission_queue(request.queue_id) or { return -2 }',
		'defer { if !transferred { release_submission_queue(captured) } }', 'stage_bytes :=',
		'stage_storage := memory.malloc_packed_fallible(stage_bytes)',
		'defer { memory.free(stage_storage) }', 'agxsubmission.stage_command_array(',
		'agxsubmission.stage_sync_array(', 'f.lock.acquire()', 'vm_id := captured.vm_id',
		'queue_caps := captured.caps', 'vm := f.find_owned_vm(vm_id)', 'queue_resources := captured.resources'],
		'Header validation, owned early lookup, unlocked staging and locked captured state')!
	remote := section(reference, 'pub(crate) fn submit(', '/// IOCTL: get_time:', 'Packaged queue lookup order')!
	require_order(remote, ['if data.flags != 0 || data.pad != 0', 'return Err(EINVAL)',
		'.queues()', '.get(data.queue_id.try_into()?)', '.ok_or(ENOENT)?',
		'let copy_commands =', 'UserSlice::new(', 'SyncItem::parse_array('],
		'Packaged Asahi resolves its queue before userspace command and sync staging')!
}
