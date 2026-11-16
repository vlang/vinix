// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

import g13layout

fn test_params_device_guards_require_pre_copy_rejection_and_released_state_lock() {
	repo := g13layout.repo_root()
	file := read(repo + '/kernel/gpu/agx/file/file.v')!
	gpu := read(repo + '/kernel/gpu/agx/gpu/gpu.v')!
	check_params_device_local(file, gpu)!
	for token in ['if !gpu_manager.can_query_global_params() { return -19 }', 'return -22 // EINVAL'] {
		if _ := check_params_device_local(file.replace(token, ''), gpu) { assert false, token }
	}
	for token in ['defer { mgr.lock.release() }', 'mgr.state != .error && ', ' && mgr.state != .stopped'] {
		if _ := check_params_device_local(file, gpu.replace(token, '')) { assert false, token }
	}
}
