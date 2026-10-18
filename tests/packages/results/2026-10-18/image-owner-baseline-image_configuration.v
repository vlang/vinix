// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os

// A captured, validated image-build input. It never replaces an installed
// configuration or enrolls a demonstration publisher. Close after publishing.
pub struct ImageConfiguration {
	root string
	path string
	architecture string
	text string
	device u64
	inode u64
	existing bool
}

fn image_configuration_root_matches(root string, device u64, inode u64) bool {
	mut info := C.stat{}
	return C.lstat(root.str, unsafe { &info }) == 0 && info.st_mode & 0o170000 == 0o040000
		&& info.st_mode & 0o022 == 0 && (info.st_uid == 0 || info.st_uid == u32(os.geteuid()))
		&& u64(info.st_dev) == device && u64(info.st_ino) == inode
}

fn image_configuration_parents(root string) ! {
	for suffix in ['/etc', '/etc/vinix-packages']! {
		path := root + suffix
		defer { unsafe { path.free() } }
		mut info := C.stat{}
		if C.lstat(path.str, unsafe { &info }) != 0 {
			if C.errno == C.ENOENT { return }
			return error('cannot inspect image package configuration parent')
		}
		if info.st_mode & 0o170000 != 0o040000 || info.st_mode & 0o022 != 0
			|| (info.st_uid != 0 && info.st_uid != u32(os.geteuid())) {
			return error('image package configuration parents must be ordinary controlled directories without shared write access')
		}
	}
}

fn image_configuration_exists(path string) !bool {
	mut info := C.stat{}
	if C.lstat(path.str, unsafe { &info }) == 0 { return true }
	if C.errno != C.ENOENT { return error('cannot inspect image package configuration') }
	return false
}

fn image_configuration_fresh_state(root string) ! {
	for suffix in ['/var', '/var/lib', '/var/lib/vinix-packages']! {
		path := root + suffix
		defer { unsafe { path.free() } }
		mut info := C.stat{}
		if C.lstat(path.str, unsafe { &info }) != 0 {
			if C.errno == C.ENOENT { return }
			return error('cannot inspect image package state')
		}
		if info.st_mode & 0o170000 != 0o040000 || info.st_mode & 0o022 != 0
			|| (info.st_uid != 0 && info.st_uid != u32(os.geteuid())) {
			return error('image package state parents must be ordinary controlled directories without shared write access')
		}
	}
	path := state_directory(root)
	defer { unsafe { path.free() } }
	entries := os.ls(path)!
	defer { unsafe { entries.free() } }
	if entries.len != 0 { return error('package state already exists without configuration; restore its trusted configuration instead of initializing release trust') }
}

fn image_configuration_architecture(root string, architecture string) ! {
	path := rooted_package_path(root, '/etc/vinix-packages/config.json')
	defer { unsafe { path.free() } }
	mut info := C.stat{}
	if C.lstat(path.str, unsafe { &info }) != 0 || info.st_mode & 0o170000 != 0o100000
		|| info.st_mode & 0o022 != 0 || info.st_nlink != 1
		|| (info.st_uid != 0 && info.st_uid != u32(os.geteuid())) {
		return error('existing image package configuration must be an ordinary controlled single-link file without shared write access')
	}
	config := load_config(root)!
	defer { close_decoded_configuration(config) }
	if config.architecture != architecture { return error('existing package configuration targets another architecture') }
}

fn image_configuration_text(source string, architecture string) !string {
	if source == '' {
		config := Config{ architecture: architecture }
		defer { close_owned_policy(config.policy) }
		encoded := json2.encode(config)
		defer { unsafe { encoded.free() } }
		return encoded + '\n'
	}
	input := read_metadata(source)!
	defer { unsafe { input.free() } }
	config := decode_configuration(input)!
	defer { close_decoded_configuration(config) }
	if config.architecture != architecture { return error('release package configuration targets another architecture') }
	// Syntax-only legacy readers permit revocation of invalid old keys. A new
	// image trust root must pass the same curve admission as live enrollment.
	for repository in config.repositories {
		key := admitted_publisher_key(repository.public_key)!
		unsafe { key.free() }
	}
	encoded := json2.encode(config)
	defer { unsafe { encoded.free() } }
	if encoded.len >= max_metadata { return error('canonical image package configuration exceeds the metadata limit') }
	return encoded + '\n'
}

// Preparing reads one bounded input before compilation begins. Later edits or
// removal of that source cannot change the bytes published by this plan.
pub fn prepare_image_configuration(root string, architecture string, source string) !ImageConfiguration {
	if architecture !in ['aarch64', 'x86_64']! { return error('unsupported image package architecture') }
	path := publisher_path(root)!
	defer { unsafe { path.free() } }
	fd := capture_prepared_root(path, 'package image root')!
	defer { C.close(fd) }
	mut info := C.stat{}
	if C.fstat(fd, unsafe { &info }) != 0 || info.st_mode & 0o022 != 0
		|| (info.st_uid != 0 && info.st_uid != u32(os.geteuid())) {
		return error('package image root must be an ordinary controlled directory without shared write access')
	}
	physical := os.real_path(path)
	mut accepted := false
	defer { if !accepted { unsafe { physical.free() } } }
	if physical == '/' { return error('image package staging cannot target the running system root') }
	check_export_parent(physical, 'package image')!
	image_configuration_parents(physical)!
	target := physical + '/etc/vinix-packages/config.json'
	defer { if !accepted { unsafe { target.free() } } }
	existing := image_configuration_exists(target)!
	if existing { image_configuration_architecture(physical, architecture)! }
	else { image_configuration_fresh_state(physical)! }
	text := if existing { '' } else { image_configuration_text(source, architecture)! }
	accepted = true
	return ImageConfiguration{ root: physical, path: target, architecture: architecture.clone(), text: text,
		device: u64(info.st_dev), inode: u64(info.st_ino), existing: existing }
}

// Return true only for a newly published file. Existing configuration is
// validated and retained byte-for-byte, including when --config is supplied.
pub fn (plan &ImageConfiguration) publish() !bool {
	if plan.root == '' || !image_configuration_root_matches(plan.root, plan.device, plan.inode) {
		return error('package image root changed after preparation; restore the staging directory and retry')
	}
	image_configuration_parents(plan.root)!
	if plan.existing {
		image_configuration_architecture(plan.root, plan.architecture)!
		return false
	}
	image_configuration_fresh_state(plan.root)!
	parent := os.dir(plan.path)
	defer { unsafe { parent.free() } }
	os.mkdir_all(parent, mode: 0o755)!
	image_configuration_parents(plan.root)!
	if !image_configuration_root_matches(plan.root, plan.device, plan.inode) { return error('package image root changed before configuration publication') }
	atomic_write_new(plan.path, plan.text)!
	return true
}

pub fn (mut plan ImageConfiguration) close() {
	unsafe { plan.root.free(); plan.path.free(); plan.architecture.free(); plan.text.free() }
	plan = ImageConfiguration{}
}
