// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

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

fn open_image_package_directory(parent int, name string, create bool, kind string) !int {
	if create && C.mkdirat(parent, name.str, 0o755) != 0 && C.errno != C.EEXIST {
		return error('cannot create image package ${kind} directory: ${name}')
	}
	fd := C.openat(parent, name.str, C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK)
	if fd < 0 { return error('cannot open ordinary image package ${kind} directory: ${name}') }
	mut info := C.stat{}
	if C.fstat(fd, unsafe { &info }) != 0 || info.st_mode & 0o022 != 0
		|| (info.st_uid != 0 && info.st_uid != u32(os.geteuid())) {
		C.close(fd)
		return error('image package ${kind} parents must be ordinary controlled directories without shared write access')
	}
	return fd
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
		return publisher_json(config)
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
	text := publisher_json(config)
	if text.len > max_metadata {
		unsafe { text.free() }
		return error('canonical image package configuration exceeds the metadata limit')
	}
	return text
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
	physical := publisher_real_path(path)!
	mut accepted := false
	defer { if !accepted { unsafe { physical.free() } } }
	if physical == '/' { return error('image package staging cannot target the running system root') }
	check_export_parent(physical, 'package image')!
	if !image_configuration_root_matches(physical, u64(info.st_dev), u64(info.st_ino)) {
		return error('package image root changed during configuration preparation')
	}
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
	return plan.publish_configuration_with(AtomicWriteOptions{})
}

fn (plan &ImageConfiguration) publish_configuration_with(options AtomicWriteOptions) !bool {
	if plan.root == '' || !image_configuration_root_matches(plan.root, plan.device, plan.inode) {
		return error('package image root changed after preparation; restore the staging directory and retry')
	}
	image_configuration_parents(plan.root)!
	if !plan.existing { image_configuration_fresh_state(plan.root)! }
	root := capture_prepared_root(plan.root, 'package image configuration')!
	defer { C.close(root) }
	mut info := C.stat{}
	if C.fstat(root, unsafe { &info }) != 0 || u64(info.st_dev) != plan.device || u64(info.st_ino) != plan.inode {
		return error('package image root changed before configuration publication')
	}
	etc := open_image_package_directory(root, 'etc', !plan.existing, 'configuration')!
	defer { C.close(etc) }
	directory := open_image_package_directory(etc, 'vinix-packages', !plan.existing, 'configuration')!
	defer { C.close(directory) }
	etc_path := plan.root + '/etc'
	defer { unsafe { etc_path.free() } }
	parent, name := atomic_file_path(plan.path)!
	defer { unsafe { parent.free(); name.free() } }
	options.checkpoint('prepared', plan.path)!
	image_configuration_parents(plan.root)!
	if plan.existing {
		image_configuration_architecture(plan.root, plan.architecture)!
	} else {
		image_configuration_fresh_state(plan.root)!
	}
	if !image_configuration_root_matches(plan.root, plan.device, plan.inode) { return error('package image root changed before configuration publication') }
	if !atomic_captured_parent_matches(etc_path, etc) || !atomic_captured_parent_matches(parent, directory) {
		return error('image package configuration directory changed before publication')
	}
	if plan.existing { return false }
	atomic_write_at(parent, name, plan.text, AtomicWriteOptions{ ...options, exclusive: true, parent_fd: directory })!
	return true
}

pub fn (mut plan ImageConfiguration) close() {
	unsafe { plan.root.free(); plan.path.free(); plan.architecture.free(); plan.text.free() }
	plan = ImageConfiguration{}
}
