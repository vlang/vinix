// SPDX-License-Identifier: GPL-2.0-or-later
// SDK 1 catalog presentation; no package state or privileged operations.
module pkgprotocol

pub struct SoftwareRow {
pub:
	id string
	name string
	description string
	version string
	installed_version string
	installed_name string
	installed_kind string
	installed_permissions []string
	installed_window_protocol int
	architecture string
	kind string
	runtime string
	repository string
	public_key string
	license string
	proprietary bool
	firmware bool
	permissions []string
	requested bool
	updatable bool
	update_action string
	diagnostic string
}

pub struct SoftwareView {
pub:
	format int
	generation u64
	architecture string
	offline bool
	catalog_error string
	update_error string
	rows []SoftwareRow
	launch_user string
}

fn view_account(value string) bool {
	if value == '' { return true }
	if value.len > 32 || value in ['root', 'greeter', 'nobody']!
		|| !((value[0] >= `a` && value[0] <= `z`) || value[0] == `_`) { return false }
	for byte in value { if !((byte >= `a` && byte <= `z`) || (byte >= `0` && byte <= `9`) || byte in [u8(`_`), `-`]!) { return false } }
	return true
}

fn view_permissions(values []string) bool {
	if values.len > 5 { return false }
	for value in values {
		if value !in ['audio', 'display', 'files', 'network', 'process']! { return false }
	}
	return true
}

pub fn (view &SoftwareView) validate() ! {
	if view.format != 1 || view.architecture !in ['aarch64', 'x86_64']! || view.rows.len > 4096
		|| view.catalog_error.len > 4096 || view.update_error.len > 4096 || !view_account(view.launch_user) {
		return error('invalid Software view header')
	}
	mut ids := map[string]bool{}
	defer { unsafe { ids.free() } }
	for row in view.rows {
		if !identifier(row.id) || row.id in ids || row.name == '' || !printable(row.name, 256)
			|| !printable(row.description, 4096) || !version(row.version)
			|| (row.installed_version != '' && !version(row.installed_version))
			|| row.architecture !in [view.architecture, 'all']
			|| row.kind !in ['native', 'linux', 'windows', 'apple', 'runtime', 'data']!
			|| (row.architecture == 'all' && row.kind != 'data')
			|| (row.kind in ['linux', 'windows', 'apple']! && row.runtime == '')
			|| (row.runtime != '' && !identifier(row.runtime)) || !identifier(row.repository)
			|| !digest(row.public_key) || row.license == '' || !printable(row.license, 256)
			|| !view_permissions(row.permissions) || !view_permissions(row.installed_permissions)
			|| row.diagnostic.len > 4096 || row.updatable != (row.update_action != '')
			|| row.update_action !in ['', 'install', 'update', 'remove']!
			|| (row.installed_version == '' && (row.requested || row.update_action in ['update', 'remove']!
				|| row.installed_name != '' || row.installed_kind != '' || row.installed_permissions.len != 0 || row.installed_window_protocol != 0))
			|| (row.installed_version != '' && (view.generation == 0 || row.update_action == 'install'))
			|| (row.update_action == 'remove' && (row.requested || row.version != row.installed_version))
			|| ((view.catalog_error != '' || view.update_error != '') && row.updatable)
			|| row.installed_window_protocol !in [0, 1, 2]! {
			return error('invalid package in Software view')
		}
		if row.installed_kind != '' {
			if row.installed_name == '' || !printable(row.installed_name, 256)
				|| row.installed_kind !in ['native', 'linux', 'windows', 'apple', 'runtime', 'data']!
				|| (row.installed_window_protocol != 0 && (row.installed_kind != 'native' || 'display' !in row.installed_permissions)) {
				return error('invalid installed launch metadata in Software view')
			}
		} else if row.installed_name != '' || row.installed_permissions.len != 0 || row.installed_window_protocol != 0 {
			return error('incomplete installed launch metadata in Software view')
		}
		ids[row.id] = true
	}
}

fn close_software_row(row SoftwareRow) {
	unsafe {
		row.id.free(); row.name.free(); row.description.free(); row.version.free(); row.installed_version.free()
		row.installed_name.free(); row.installed_kind.free(); row.architecture.free(); row.kind.free(); row.runtime.free()
		row.repository.free(); row.public_key.free(); row.license.free(); row.update_action.free(); row.diagnostic.free()
		for value in row.permissions { value.free() }; (&array(&row.permissions)).free()
		for value in row.installed_permissions { value.free() }; (&array(&row.installed_permissions)).free()
	}
}

// Decoded fields and arrays are owned, including partial input on refusal.
pub fn (mut view SoftwareView) close() {
	unsafe {
		view.architecture.free(); view.catalog_error.free(); view.update_error.free(); view.launch_user.free()
		for row in view.rows { close_software_row(row) }; (&array(&view.rows)).free()
	}
	view = SoftwareView{}
}
