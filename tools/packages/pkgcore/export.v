// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os

fn check_export_parent(parent string, kind string) ! {
	mut path := parent.clone()
	defer { unsafe { path.free() } }
	for {
		mut info := C.stat{}
		if C.lstat(path.str, unsafe { &info }) != 0 { return error('cannot inspect export parent: ' + path) }
		// Sticky shared directories protect an exclusive child. Other users must
		// not be able to replace its ancestors while the administrator writes it.
		if info.st_mode & 0o170000 != 0o040000
			|| (info.st_uid != 0 && info.st_uid != u32(os.geteuid()))
			|| (info.st_mode & 0o022 != 0 && info.st_mode & 0o1000 == 0) {
			return error('${kind} parent must be controlled by this administrator; writable shared directories require the sticky bit: ${path}')
		}
		if path == '/' { return }
		next := os.dir(path)
		unsafe { path.free() }
		path = next
	}
}

fn export_target(destination string, kind string) !string {
	if destination == '' || !printable(destination, 4096) || destination.contains('\\') {
		return error('${kind} requires a valid destination path')
	}
	trimmed := destination.trim_right('/')
	name := os.file_name(trimmed)
	defer { unsafe { trimmed.free(); name.free() } }
	if name in ['', '.', '..']! { return error('${kind} destination must be a new directory') }
	if publisher_entry_exists(destination) { return error('${kind} destination must be new') }
	path := os.dir(trimmed)
	defer { unsafe { path.free() } }
	mut existing := mirror_absolute_path(path)!
	defer { unsafe { existing.free() } }
	for !publisher_entry_exists(existing) {
		next := os.dir(existing)
		unsafe { existing.free() }
		existing = next
	}
	mut info := C.stat{}
	if C.fstatat(C.AT_FDCWD, existing.str, unsafe { &info }, 0) != 0 || info.st_mode & 0o170000 != 0o040000 { return error('${kind} parent must be a directory') }
	ancestor := publisher_real_path(existing)!
	defer { unsafe { ancestor.free() } }
	check_export_parent(ancestor, kind)!
	make_package_directories(path, 0o755)!
	parent := publisher_real_path(path)!
	defer { unsafe { parent.free() } }
	check_export_parent(parent, kind)!
	target := if parent == '/' { parent + name } else { parent + '/' + name }
	if publisher_entry_exists(target) { unsafe { target.free() }; return error('${kind} destination must be new') }
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
