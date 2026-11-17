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
		'object.references++', 'f.release_g13_timestamps(mut references);',
		'if !object.detached || object.references != 0 { continue }', 'f.timestamp_objects[index].references--'] {
		if _ := check_timestamp_capture_local(file, captures.replace(token, ''), gpu) { assert false, token }
	}
	for token in ['object.references != 0', 'manager == unsafe { nil } && (f.timestamp_objects.len != 0 || f.g13_queues.len != 0)',
		'f.timestamp_objects[found_index].detached = true', 'owned.reap_detached_timestamp_objects_locked()'] {
		if _ := check_timestamp_capture_local(file.replace(token, ''), captures, gpu) { assert false, token }
	}
}
