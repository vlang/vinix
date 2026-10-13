// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os

fn check_export_parent(parent string, kind string) ! {
	mut path := parent
	for {
		info := os.lstat(path)!
		// Sticky shared directories protect an exclusive child. Other users must
		// not be able to replace its ancestors while the administrator writes it.
		if os.is_link(path) || !os.is_dir(path)
			|| (info.uid != 0 && info.uid != u32(os.geteuid()))
			|| (info.mode & 0o022 != 0 && info.mode & 0o1000 == 0) {
			return error('${kind} parent must be controlled by this administrator; writable shared directories require the sticky bit: ${path}')
		}
		if path == '/' { return }
		path = os.dir(path)
	}
}

fn export_target(destination string, kind string) !string {
	if destination == '' || !printable(destination, 4096) || destination.contains('\\') {
		return error('${kind} requires a valid destination path')
	}
	trimmed := destination.trim_right('/')
	name := os.file_name(trimmed)
	if name in ['', '.', '..'] { return error('${kind} destination must be a new directory') }
	if os.exists(destination) || os.is_link(destination) { return error('${kind} destination must be new') }
	path := os.dir(trimmed)
	mut existing := os.abs_path(path)
	for !os.exists(existing) && !os.is_link(existing) { existing = os.dir(existing) }
	if !os.is_dir(existing) { return error('${kind} parent must be a directory') }
	check_export_parent(os.real_path(existing), kind)!
	os.mkdir_all(path, mode: 0o755)!
	parent := os.real_path(path)
	check_export_parent(parent, kind)!
	target := parent.trim_right('/') + '/' + name
	if os.exists(target) || os.is_link(target) { return error('${kind} destination must be new') }
	return target
}

fn export_stage(parent string, prefix string) !string {
	mut template := (parent + '/' + prefix + '-XXXXXX').bytes()
	template << u8(0)
	defer { unsafe { template.free() } }
	if C.mkdtemp(unsafe { &char(template.data) }) == unsafe { nil } {
		return error('cannot create private ${prefix} staging directory')
	}
	return unsafe { cstring_to_vstring(&char(template.data)).clone() }
}
