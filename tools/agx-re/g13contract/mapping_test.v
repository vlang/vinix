module g13contract

import g13layout
import os

fn test_user_mapping_lifetime_gates() {
	local := os.read_file(g13layout.repo_root() + '/kernel/gpu/agx/file/file.v')!
	manager := os.read_file(g13layout.repo_root() + '/kernel/gpu/agx/gpu/gpu.v')!
	check_user_mapping_contract(local, manager)!
	for token in ['if !mapping.retiring', 'f.mappings[index].retiring = true',
		'if !f.finish_file_mapping(true)',
		'f.mappings[f.mappings.len - 1].retiring = true', 'f.retire_mapping_locked(index)',
		'if !f.cleanup_closed_mappings_locked(vm)'] {
		assert local.contains(token)
		if _ := check_user_mapping_contract(local.replace(token, ''), manager) { assert false, token }
	}
	if _ := check_user_mapping_contract(local.replace('ctx := f.find_vm(request.vm_id)',
		'f.lock.release()\nctx := f.find_vm(request.vm_id)'), manager) { assert false }
	if _ := check_user_mapping_contract(local.replace('gem.unref(mapping.obj)',
		'gem.unref(mapping.obj)\ngem.unref(mapping.obj)'), manager) { assert false }
	if _ := check_user_mapping_contract(local.replace('return -5 // EIO',
		'gem.unref(obj)\nreturn -5 // EIO'), manager) { assert false }
	for token in ['mgr.lock.acquire()', 'defer { mgr.lock.release() }', 'unmapped &&'] {
		if _ := check_user_mapping_contract(local, manager.replace(token, '')) { assert false, token }
	}
	if _ := check_user_mapping_contract(local, manager.replace('return mgr.g13_submission_status_locked() == 0',
		'return mgr.flush_g13_uat_range(1, 0x4000, 0x4000)')) { assert false }
}
