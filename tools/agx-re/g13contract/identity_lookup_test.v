// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

import g13layout

fn test_identity_lookup_guard_rejects_errno_collapse_and_lost_presence_check() {
	local := read(g13layout.repo_root() + '/kernel/gpu/agx/file/file.v')!
	reference := 'pub(crate) fn vm_destroy( vms().remove(data.vm_id as usize); if vm.is_none() { Err(ENOENT) }\n/// IOCTL: gem_create:\n' +
		'pub(crate) fn queue_create( let guard = vms_xa.lock(); guard.get(data.vm_id.try_into()?).ok_or(ENOENT)?; let vm = file_vm.vm.clone();\n/// IOCTL: queue_destroy:\n' +
		'pub(crate) fn queue_destroy( queues().remove(data.queue_id as usize); if queue.is_none() { Err(ENOENT) }\n/// IOCTL: submit:\n' +
		'pub(crate) fn submit( .queues().get(data.queue_id.try_into()?).ok_or(ENOENT)?;\n/// IOCTL: get_time:'
	check_identity_lookup_contract(local, reference)!
	for token in ['f.detached_vms[vm.id] = true', 'return -2 // ENOENT: no queue',
		'vm := f.find_vm(request.vm_id) or { return -2 }', 'captured := f.capture_submission_queue(request.queue_id) or { return -2 }',
		'vm_id := captured.vm_id', 'if vm_id == 0 || vm_id >= mmu.uat_num_contexts { return -22 }'] {
		if _ := check_identity_lookup_contract(local.replace(token, ''), reference) { assert false, token }
	}
	if _ := check_identity_lookup_contract(local, reference.replace('ENOENT', 'EINVAL')) { assert false }
}
