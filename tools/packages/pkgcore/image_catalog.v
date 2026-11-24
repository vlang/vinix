// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os
import tools.packages.pkgprotocol

// Owns the exact jointly resolved release application lock and input report.
// Publish after the matching repository bundle and configuration; then close.
pub struct ImageApplications {
	root string
	architecture string
	configuration string
	capture_device u64
	capture_inode u64
	text string
	report_text string
}

fn image_applications_action(root string, text string) !string {
	if text == '' { return 'none' }
	ancestor := image_repositories_parents(root)!
	defer { unsafe { ancestor.free() } }
	path := root + pkgprotocol.image_applications_path
	defer { unsafe { path.free() } }
	mut info := C.stat{}
	if C.lstat(path.str, unsafe { &info }) != 0 {
		if C.errno == C.ENOENT { return 'publish' }
		return error('cannot inspect image application deployment')
	}
	if info.st_mode & 0o170000 != 0o100000 || info.st_mode & 0o7777 != 0o644 || info.st_nlink != 1
		|| (info.st_uid != 0 && info.st_uid != u32(os.geteuid())) {
		return error('image application deployment must be an ordinary controlled single-link mode-0644 file')
	}
	existing := read_metadata(path)!
	defer { unsafe { existing.free() } }
	mut after := C.stat{}
	if existing != text || C.lstat(path.str, unsafe { &after }) != 0 || after.st_dev != info.st_dev
		|| after.st_ino != info.st_ino || after.st_mode != info.st_mode || after.st_nlink != 1
		|| after.st_uid != info.st_uid || after.st_size != info.st_size {
		return error('image application deployment differs or changed; existing files are preserved')
	}
	return 'preserve'
}

pub fn (configuration &ImageConfiguration) prepare_applications(repositories &ImageRepositories, required []string) !ImageApplications {
	if required.len == 0 { return error('image applications require at least one application ID') }
	return configuration.plan_inputs(repositories, DeploymentLock{ format: 1, packages: required }, '', ImageDeploymentOutput{})
}

pub fn (configuration &ImageConfiguration) prepare_application_file(repositories &ImageRepositories, source string) !ImageApplications {
	return configuration.plan_application_source(repositories, source, ImageDeploymentOutput{})
}

// Return independently owned JSON, released by the caller.
pub fn (plan &ImageApplications) report() string { return plan.report_text.clone() }

pub fn (plan &ImageApplications) publish(repositories &ImageRepositories) !bool {
	return plan.publish_with(repositories, AtomicWriteOptions{})
}

fn (plan &ImageApplications) publish_with(repositories &ImageRepositories, options AtomicWriteOptions) !bool {
	if plan.root == '' { return false } // no requirements were selected
	if repositories.root != plan.root || repositories.architecture != plan.architecture
		|| repositories.configuration != plan.configuration || repositories.capture == ''
		|| repositories.capture_stage.device != plan.capture_device || repositories.capture_stage.inode != plan.capture_inode {
		return error('image applications require their unchanged root and matching captured repositories')
	}
	repositories.current()!
	target := plan.root + pkgprotocol.image_applications_path
	bundle := plan.root + image_repositories_path
	defer { unsafe { target.free(); bundle.free() } }
	parent, name := atomic_file_path(target)!
	defer { unsafe { parent.free(); name.free() } }
	// Both must already be published. Do not create a declaration pointing at
	// missing trust or media, or initialize consumer package state.
	image_configuration_architecture(plan.root, plan.architecture)!
	ancestor := image_repositories_parents(plan.root)!
	defer { unsafe { ancestor.free() } }
	if ancestor != parent { return error('image application deployment requires its published repository directory') }
	directory := open_atomic_parent(parent)!
	defer { C.close(directory) }
	bundle_directory := open_atomic_parent(bundle)!
	defer { C.close(bundle_directory) }
	repositories.verify(repositories.capture, 0o700)!
	repositories.verify(bundle, 0o755)!
	options.checkpoint('prepared', target)!
	repositories.current()!
	preserve := image_applications_action(plan.root, plan.text)! == 'preserve'
	if !preserve { disk_check(free_bytes(parent)!, u64(plan.text.len), 64 * 1024 * 1024)! }
	if !atomic_captured_parent_matches(parent, directory) {
		return error('image application deployment parent changed during verification')
	}
	if !atomic_captured_parent_matches(bundle, bundle_directory) {
		return error('published image repository directory changed during verification')
	}
	if preserve { return false }
	atomic_write_at(parent, name, plan.text, AtomicWriteOptions{ ...options, exclusive: true, parent_fd: directory })!
	return true
}

pub fn (mut plan ImageApplications) close() {
	unsafe { plan.root.free(); plan.architecture.free(); plan.configuration.free(); plan.text.free(); plan.report_text.free() }
	plan = ImageApplications{}
}
