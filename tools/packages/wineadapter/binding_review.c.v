// SPDX-License-Identifier: GPL-2.0-or-later
module wineadapter

import os
import strconv

pub struct BuiltinBinding {
pub:
	name string
	observed string
	replacement string
}

pub struct BindingReview {
pub:
	format int = 1
	scope string = 'read-only structural review; no runtime authentication or migration authorization'
pub mut:
	generation u64
	prior_generation u64
	runtime_id string
	bindings []BuiltinBinding
}

pub fn (mut review BindingReview) close() {
	unsafe {
		for mut entry in review.bindings { entry.name.free(); entry.observed.free(); entry.replacement.free() }
		(&array(&review.bindings)).free()
		review.runtime_id.free()
	}
	review = BindingReview{}
}

fn builtin_generation(store string, path string) !(u64, string) {
	prefix := store + '/generations/'
	defer { unsafe { prefix.free() } }
	if !path.starts_with(prefix) { return error('Wine builtin target is outside the selected package store') }
	rest := path[prefix.len..]
	defer { unsafe { rest.free() } }
	parts := rest.split('/')
	defer { unsafe { parts.free() } }
	if parts.len != 8 || parts[0] == '' || parts[0][0] == `0` || parts[0].len > 20
		|| parts[1] != 'apps' || parts[3] != 'root' || parts[4] != 'usr' || parts[5] != 'lib'
		|| parts[6] != 'wine' || parts[7] != 'x86_64-windows' || parts[2] == '' || parts[2].len > 160 {
		return error('Wine builtin generation path is not canonical')
	}
	for byte in parts[0] { if byte < `0` || byte > `9` { return error('Wine builtin generation is not decimal') } }
	for byte in parts[2] {
		if !(byte >= `a` && byte <= `z`) && !(byte >= `0` && byte <= `9`) && byte !in [`-`, `.`] {
			return error('Wine builtin runtime identity is invalid')
		}
	}
	if parts[2][0] < `a` || parts[2][0] > `z` || parts[2].contains('..') { return error('Wine builtin runtime identity is invalid') }
	generation := strconv.parse_uint(parts[0], 10, 64)!
	return generation, parts[2].clone()
}

fn review_child(parent int, name string) !int {
	fd := C.openat(parent, name.str, C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC)
	if fd < 0 { return error('Wine binding review needs existing directory components without symlinks') }
	directory(fd, u32(C.geteuid()), true) or { C.close(fd); return err }
	return fd
}

fn review_same_child(parent int, name string, held int) ! {
	current := review_child(parent, name)!
	defer { C.close(current) }
	a := directory(held, u32(C.geteuid()), true)!
	b := directory(current, u32(C.geteuid()), true)!
	if a.st_dev != b.st_dev || a.st_ino != b.st_ino { return error('Wine binding review directory identity changed') }
}

// Run as the prefix owner. Capture directories without following links and
// inspect link text only. Never create directories, load a DLL, or rewrite a
// binding. This is not a snapshot against concurrent mutation. An apply
// operation still needs authenticated inputs, idle-server
// admission, serialization, fresh rechecks and an interruption recovery policy.
pub fn review_prefix_bindings(data string, builtins string, store string) !BindingReview {
	store_fd := absolute_directory(store)!
	defer { C.close(store_fd) }
	generation, runtime := builtin_generation(store, builtins)!
	mut review := BindingReview{generation: generation, runtime_id: runtime}
	mut accepted := false
	defer { if !accepted { review.close() } }
	data_fd := absolute_directory(data)!
	mut prefix := Prefix{path: data + '/wine', data: data_fd}
	defer { prefix.close() }
	directory(prefix.data, u32(C.geteuid()), true)!
	prefix.directory = review_child(prefix.data, 'wine')!
	info := directory(prefix.directory, u32(C.geteuid()), true)!
	prefix.device = u64(info.st_dev); prefix.inode = u64(info.st_ino)
	drive := review_child(prefix.directory, 'drive_c')!
	defer { C.close(drive) }
	windows := review_child(drive, 'windows')!
	defer { C.close(windows) }
	system := review_child(windows, 'system32')!
	defer { C.close(system) }
	assets := absolute_directory(builtins)!
	defer { C.close(assets) }
	mut names := os.ls(builtins)!
	defer { unsafe { names.free() } }
	if names.len < 1 || names.len > 900 { return error('Wine binding review inventory is empty or too large') }
	names.sort()
	review.bindings = []BuiltinBinding{cap: names.len}
	for name in names {
		if !component(name) || !(name.ends_with('.dll') || name.ends_with('.exe')
			|| name.ends_with('.sys') || name.ends_with('.cpl') || name.ends_with('.drv')
			|| name.ends_with('.ocx') || name.ends_with('.ax') || name.ends_with('.tlb')
			|| name.ends_with('.ds') || name.ends_with('.com') || name.ends_with('.acm')
			|| name.ends_with('.msstyles')) { return error('Wine binding review name is invalid') }
		fd := C.openat(assets, name.str, C.O_RDONLY | C.O_NOFOLLOW | C.O_CLOEXEC | C.O_NONBLOCK)
		if fd < 0 { return error('Wine binding review asset is linked or unavailable') }
		mut asset := C.stat{}
		ordinary := C.fstat(fd, unsafe { &asset }) == 0 && u32(asset.st_mode) & 0o170000 == 0o100000
		C.close(fd)
		if !ordinary { return error('Wine binding review asset is not ordinary') }
		mut buffer := [4097]u8{}
		length := C.readlinkat(system, name.str, &char(&buffer[0]), 4096)
		if length < 1 || length >= 4096 { return error('Wine binding review requires existing bounded symlinks') }
		observed := unsafe { tos(&buffer[0], int(length)) }.clone()
		mut retained := false
		defer { if !retained { unsafe { observed.free() } } }
		suffix := '/' + name
		defer { unsafe { suffix.free() } }
		if !observed.ends_with(suffix) { return error('Wine builtin target basename differs') }
		old_directory := observed[..observed.len - suffix.len]
		defer { unsafe { old_directory.free() } }
		old, identity := builtin_generation(store, old_directory)!
		defer { unsafe { identity.free() } }
		if identity != runtime { return error('Wine builtin belongs to a different runtime') }
		if old != generation {
			if review.prior_generation != 0 && review.prior_generation != old { return error('Wine builtin links span multiple prior generations') }
			review.prior_generation = old
		}
		review.bindings << BuiltinBinding{name: name.clone(), observed: observed, replacement: builtins + suffix}
		retained = true
	}
	// A removed builtin is absent from the new inventory. Do not silently
	// approve a review which would leave its generation link behind. Personal
	// files and links outside the package generation namespace remain private.
	system_path := data + '/wine/drive_c/windows/system32'
	defer { unsafe { system_path.free() } }
	mut existing := os.ls(system_path)!
	defer { unsafe { existing.free() } }
	if existing.len > 4096 { return error('Wine binding review prefix inventory is too large') }
	existing.sort()
	generations := store + '/generations/'
	defer { unsafe { generations.free() } }
	for name in existing {
		if name in names { continue }
		mut buffer := [4097]u8{}
		length := C.readlinkat(system, name.str, &char(&buffer[0]), 4096)
		if length < 0 {
			if C.errno == C.EINVAL { continue }
			return error('Wine binding review cannot inspect extra prefix entry')
		}
		if length < 1 || length >= 4096 { return error('Wine binding review extra link is not bounded') }
		observed := unsafe { tos(&buffer[0], int(length)) }
		if observed.starts_with(generations) {
			return error('Wine prefix has a package-generation link absent from the selected builtin inventory')
		}
	}
	prefix.recheck(data)!
	review_same_child(prefix.directory, 'drive_c', drive)!
	review_same_child(drive, 'windows', windows)!
	review_same_child(windows, 'system32', system)!
	current_assets := absolute_directory(builtins)!
	defer { C.close(current_assets) }
	a := directory(assets, u32(C.geteuid()), false)!
	b := directory(current_assets, u32(C.geteuid()), false)!
	if a.st_dev != b.st_dev || a.st_ino != b.st_ino { return error('Wine binding review asset directory changed') }
	accepted = true
	return review
}
