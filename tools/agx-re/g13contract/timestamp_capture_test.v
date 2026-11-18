// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

import g13layout

fn test_timestamp_capture_guards_require_retained_owners_and_rollback() {
	root := g13layout.repo_root()
	file := read(root + '/kernel/gpu/agx/file/file.v')!
	captures := read(root + '/kernel/gpu/agx/file/timestamps.v')!
	gpu := read(root + '/kernel/gpu/agx/gpu/gpu.v')!
	check_timestamp_capture_local(file, captures, gpu)!
	for token in ['|| object.detached', 'timestamp.offset > ~u32(0) - u32(8)',
		'voidptr(f.timestamp_manager) != voidptr(manager)',
		'object.references++', 'f.release_g13_timestamps(mut references);',
		'if !object.detached || object.references != 0 { continue }', 'f.timestamp_objects[index].references--',
		'f.timestamp_objects[index].va != capture.va'] {
		if _ := check_timestamp_capture_local(file, captures.replace(token, ''), gpu) { assert false, token }
	}
	for token in ['object.references != 0', 'release_timestamp_object(f.timestamp_manager, object)'] {
		if _ := check_timestamp_capture_local(file.replace(token, ''), captures, gpu) { assert false, token }
	}
	for token in ['if mgr.state == .stopped { return -19, 0 }', 'return -28, 0',
		'mgr.g13_timestamp.cancel_unpublished(va)', 'return code, 0', 'if mgr.state == .stopped || va',
		'mgr.uat.unmap_kernel(reservation.va, reservation.size)',
		'mgr.retire_g13_timestamp_aperture_locked()', 'mgr.stop_firmware_cpus(mgr.firmware_roles)'] {
		if _ := check_timestamp_capture_local(file, captures, gpu.replace(token, '')) { assert false, token }
	}
}
