// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_identity_lookup_contract(local string, reference string) ! {
	vm := section(local, 'pub fn (mut f GpuFile) ioctl_vm_destroy(',
		'pub fn (mut f GpuFile) ioctl_gem_create(', 'Native VM destroy lookup')!
	require_order(vm, ['request.extensions != 0 || request.pad != 0', 'return -22',
		'f.lock.acquire()', 'defer { f.lock.release() }', 'vm := f.find_vm(request.vm_id) or { return -2 }',
		'f.detached_vms[vm.id] = true', 'f.reap_detached_vms_locked()', 'return 0'], 'Absent VM is ENOENT after validation and locked lookup')!
	create := section(local, 'pub fn (mut f GpuFile) ioctl_queue_create(',
		'pub fn (mut f GpuFile) ioctl_queue_destroy(', 'Native queue VM lookup')!
	require_order(create, ['return -22', 'f.lock.acquire()', 'defer { f.lock.release() }',
		'vm := f.find_vm(request.vm_id) or { return -2 }', 'id := f.allocate_queue_id_locked()',
		'workqueue.new_workqueue('], 'Missing queue VM is ENOENT before construction')!
	destroy := section(local, 'pub fn (mut f GpuFile) ioctl_queue_destroy(',
		'fn discard_g13_completion(', 'Native queue destroy lookup')!
	require_order(destroy, ['request.extensions != 0 || request.pad != 0', 'return -22',
		'f.lock.acquire()', 'for i, mut q in f.queues', 'q.destroy()', 'return 0',
		'f.lock.release()', 'return -2'], 'Missing queue destroy releases the lock and returns ENOENT')!
	submit := section(local, 'pub fn (mut f GpuFile) ioctl_submit(', 'fn dispatch(', 'Native submit queue lookup')!
	require_order(submit, ['captured := f.capture_submission_queue(request.queue_id) or { return -2 }',
		'f.lock.acquire()', 'vm_id := captured.vm_id',
		'if vm_id == 0 || vm_id >= mmu.uat_num_contexts { return -22 }', 'vm := f.find_owned_vm(vm_id)',
		'f.cleanup_closed_mappings_locked(vm_id)'], 'Missing submit queue differs from invalid internal VM state')!
	for spec in [
		['vm_destroy', '/// IOCTL: gem_create:', 'vms().remove(data.vm_id as usize)', 'if vm.is_none()', 'Err(ENOENT)'],
		['queue_create', '/// IOCTL: queue_destroy:', 'let guard = vms_xa.lock()', 'guard.get(data.vm_id.try_into()?).ok_or(ENOENT)?', 'let vm = file_vm.vm.clone()'],
		['queue_destroy', '/// IOCTL: submit:', 'queues().remove(data.queue_id as usize)', 'if queue.is_none()', 'Err(ENOENT)'],
		['submit', '/// IOCTL: get_time:', '.queues()', '.get(data.queue_id.try_into()?)', '.ok_or(ENOENT)?'],
	] {
		body := section(reference, 'pub(crate) fn ' + spec[0] + '(', spec[1], 'Packaged ' + spec[0] + ' identity lookup')!
		require_order(body, spec[2..], 'Packaged ' + spec[0] + ' returns ENOENT for an absent identity')!
	}
}
