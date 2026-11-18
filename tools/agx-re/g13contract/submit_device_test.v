// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

import g13layout

fn test_submit_device_contract_requires_distinct_errno_locked_snapshot_and_cleanup_order() {
	repo := g13layout.repo_root()
	file := read(repo + '/kernel/gpu/agx/file/file.v')!
	gpu := read(repo + '/kernel/gpu/agx/gpu/gpu.v')!
	check_submit_device_local(file, gpu)!
	for token in ['if status != 0 { return status }', 'defer { memory.free(stage_storage) }'] {
		if _ := check_submit_device_local(file.replace(token, ''), gpu) { assert false, token }
	}
	for token in ['mgr.state == .error || ', ' || mgr.state == .stopped', 'mgr.lock.release()'] {
		if _ := check_submit_device_local(file, gpu.replace(token, '')) { assert false, token }
	}
	if _ := check_submit_device_local(file, gpu.replace('{ -19 }', '{ -95 }')) { assert false }
}

fn test_modern_submit_device_contract_rejects_lost_check_and_premature_empty_rejection() {
	submit := read(g13layout.repo_root() + '/kernel/gpu/agx/file/modern_submit.v')!
	check_modern_submit_device_local(submit)!
	for token in ['status := manager.g13_submission_status()', 'memory.free(packet)',
		'if data.cmdbuf_size != 0', 'if status != 0 { return status }'] {
		if _ := check_modern_submit_device_local(submit.replace_once(token, '')) { assert false, token }
	}
	early := submit.replace_once('if data.cmdbuf_size == 0 { return -22 }', '').replace_once(
		'if data.cmdbuf_size != 0 {', 'if data.cmdbuf_size == 0 { return -22 }\n\tif data.cmdbuf_size != 0 {')
	if _ := check_modern_submit_device_local(early) { assert false }
}
