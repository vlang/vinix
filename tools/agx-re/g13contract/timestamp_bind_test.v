// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

import g13layout

fn test_timestamp_bind_guards_require_output_only_handles_checked_sum_and_lookup_order() {
	file := read(g13layout.repo_root() + '/kernel/gpu/agx/file/file.v')!
	check_timestamp_bind_local(file)!
	for token in ['|| request.range > ~request.offset', 'request.range == 0 || ', 'return map_code',
		'if object.id > candidate { return candidate, index }', 'if object.id == candidate && !object.detached',
		'f.timestamp_objects[slot] = object',
		'else if !f.reserve_timestamp_entry_locked() { -12 }', 'return publish_code',
		'gpu_manager.lock.acquire()', 'publish_code = -19', 'mut gpu_manager := unsafe { f.timestamp_manager }',
		'if storage == unsafe { nil } { return false }',
		'manager := f.timestamp_manager', 'f.timestamp_objects[found_index].detached = true',
		'f.timestamp_objects.delete(found_index)'] {
		if _ := check_timestamp_bind_local(file.replace(token, '')) { assert false, token }
	}
	if _ := check_timestamp_bind_local(file.replace('if request.range == 0 || request.offset > obj.size',
		'if request.object_handle != 0 || request.range == 0 || request.offset > obj.size')) { assert false }
}

fn test_timestamp_registration_keeps_the_original_manager() {
	root := g13layout.repo_root()
	file := read(root + '/kernel/gpu/agx/file/file.v')!
	drm := read(root + '/kernel/drm/drm.v')!
	driver := read(root + '/kernel/gpu/agx/driver/driver.v')!
	check_timestamp_registration_local(file, drm, driver)!
	if _ := check_timestamp_registration_local(file.replace('dev.driver_data', 'nil'), drm, driver) { assert false }
	if _ := check_timestamp_registration_local(file, drm.replace('driver_data: driver_data', ''), driver) { assert false }
	if _ := check_timestamp_registration_local(file, drm, driver.replace('voidptr(mgr)', 'nil')) { assert false }
}
