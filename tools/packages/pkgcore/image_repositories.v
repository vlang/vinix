// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os
import time

pub const image_repositories_path = '/usr/share/vinix-packages/repositories'

struct ImageRepository {
	id string
	text string
	signature string
	index Index
}

// Owns a private, authenticated capture, independent of later source edits.
// Publish before ImageConfiguration.publish(), then close on every path.
pub struct ImageRepositories {
	root string
	configuration string
	configuration_existing bool
	architecture string
	device u64
	inode u64
	needed u64
mut:
	capture string
	repositories []ImageRepository
}

struct ImageRepositoriesOptions {
	available_space fn (string) !u64 = free_bytes
	checkpoint fn (string, string) ! = mirror_no_checkpoint
}

fn image_repository_objects(index Index) !map[string]Payload {
	mut objects := map[string]Payload{}
	mut accepted := false
	defer { if !accepted { unsafe { objects.free() } } }
	for p in index.packages {
		for payload in p.files {
			if payload.sha256 in objects && objects[payload.sha256].bytes != payload.bytes {
				return error('image repository has inconsistent authenticated object lengths')
			}
			objects[payload.sha256] = payload
			if objects.len > max_files { return error('image repository exceeds the bundled object limit') }
		}
	}
	accepted = true
	return objects
}

fn image_repository_copy(source string, target string, repository ImageRepository) ! {
	os.mkdir(target, mode: 0o700)!
	os.mkdir(target + '/objects', mode: 0o755)!
	objects := image_repository_objects(repository.index)!
	defer { unsafe { objects.free() } }
	for hash, payload in objects {
		path := target + '/objects/' + hash
		input := source + '/objects/' + hash
		defer { unsafe { hash.free(); path.free(); input.free() } }
		copy_file(input, path, 0, payload.bytes)!
		os.chmod(path, 0o644)!
		if !verified_file_with(path, payload, HashReadOptions{ mode: 0o644 }) { return error('image repository payload changed during capture') }
	}
	atomic_write_new(target + '/index.json', repository.text)!
	atomic_write_new(target + '/index.sig', repository.signature + '\n')!
	verify_release_stage(target, repository.text, repository.signature, objects, false)!
	flush_tree(target + '/objects')!
	os.chmod(target, 0o755)!
	sync_directory(target)!
	verify_release_stage(target, repository.text, repository.signature, objects, true)!
}

fn image_repositories_parents(root string) !string {
	for suffix in ['/usr', '/usr/share', '/usr/share/vinix-packages']! {
		path := root + suffix
		defer { unsafe { path.free() } }
		mut info := C.stat{}
		if C.lstat(path.str, unsafe { &info }) != 0 {
			if C.errno == C.ENOENT { return os.dir(path) }
			return error('cannot inspect image repository parent')
		}
		if info.st_mode & 0o170000 != 0o040000 || info.st_mode & 0o022 != 0
			|| (info.st_uid != 0 && info.st_uid != u32(os.geteuid())) {
			return error('image repository parents must be ordinary controlled directories without shared write access')
		}
	}
	return root + '/usr/share/vinix-packages'
}

fn (plan &ImageRepositories) current() ! {
	if !image_configuration_root_matches(plan.root, plan.device, plan.inode) { return error('package image root changed after repository preparation') }
	image_configuration_parents(plan.root)!
	path := plan.root + '/etc/vinix-packages/config.json'
	defer { unsafe { path.free() } }
	if image_configuration_exists(path)! {
		image_configuration_architecture(plan.root, plan.architecture)!
		text := read_metadata(path)!
		defer { unsafe { text.free() } }
		if text != plan.configuration { return error('image package configuration changed after repository preparation') }
	} else {
		if plan.configuration_existing { return error('image package configuration disappeared after repository preparation') }
		image_configuration_fresh_state(plan.root)!
	}
}

fn (plan &ImageRepositories) verify(directory string, mode u32) ! {
	mut entries := map[string]u64{}
	defer { unsafe { entries.free() } }
	for repository in plan.repositories { entries[repository.id] = 0 }
	export_stage_directory(directory, entries, mode)!
	for repository in plan.repositories {
		if repository.index.expires <= time.now().unix() { return error('image repository expired after preparation; obtain a current signed release') }
		path := directory + '/' + repository.id
		defer { unsafe { path.free() } }
		objects := image_repository_objects(repository.index)!
		defer { unsafe { objects.free() } }
		verify_release_stage(path, repository.text, repository.signature, objects, true)!
	}
}

pub fn (configuration &ImageConfiguration) prepare_repositories(source string) !ImageRepositories {
	return configuration.prepare_repositories_with(source, ImageRepositoriesOptions{})
}

fn (configuration &ImageConfiguration) prepare_repositories_with(source string, options ImageRepositoriesOptions) !ImageRepositories {
	if source == '' { return ImageRepositories{} }
	if !image_configuration_root_matches(configuration.root, configuration.device, configuration.inode) { return error('package image root changed before repository preparation') }
	text := if configuration.existing { read_metadata(configuration.path)! } else { configuration.text.clone() }
	mut plan := ImageRepositories{ root: configuration.root.clone(), configuration: text,
		configuration_existing: configuration.existing, architecture: configuration.architecture.clone(),
		device: configuration.device, inode: configuration.inode, needed: 4 * 1024 * 1024 }
	mut accepted := false
	defer { if !accepted { plan.close() } }
	unsafe { plan.repositories.flags |= .noslices }
	unsafe { &plan }.current()!
	config := decode_configuration(text)!
	defer { close_decoded_configuration(config) }
	input := publisher_path(source)!
	defer { unsafe { input.free() } }
	fd := capture_prepared_root(input, 'image repository bundle')!
	defer { C.close(fd) }
	physical := os.real_path(input)
	defer { unsafe { physical.free() } }
	mut source_info := C.stat{}
	if C.fstat(fd, unsafe { &source_info }) != 0 || source_info.st_uid != u32(os.geteuid()) || source_info.st_mode & 0o022 != 0
		|| !atomic_parent_matches(physical, u64(source_info.st_dev), u64(source_info.st_ino)) {
		return error('image repository bundle must be a stable owned directory without shared write access')
	}
	check_export_parent(physical, 'image repository bundle')!
	mut expected := map[string]u64{}
	defer { unsafe { expected.free() } }
	for repository in config.repositories {
		if repository.url == 'file://' + image_repositories_path + '/' + repository.id { expected[repository.id] = 0 }
	}
	if expected.len == 0 { return error('image repository bundle needs explicitly configured file repositories under ' + image_repositories_path) }
	export_stage_directory(physical, expected, 0)!
	mut needed := u64(4 * 1024 * 1024)
	for repository in config.repositories {
		if repository.id !in expected { continue }
		path := physical + '/' + repository.id
		defer { unsafe { path.free() } }
		index_text := read_metadata(path + '/index.json')!
		mut item := ImageRepository{ id: repository.id.clone(), text: index_text }
		mut transferred := false
		defer { if !transferred { unsafe { item.id.free(); item.text.free(); item.signature.free() }; close_decoded_index(item.index) } }
		signature := read_metadata(path + '/index.sig')!
		defer { unsafe { signature.free() } }
		item = ImageRepository{ ...item, signature: signature.trim_space() }
		index := verify_index(repository, item.text, item.signature, time.now().unix())!
		item = ImageRepository{ ...item, index: index }
		release_closures(index, repository.public_key)!
		for p in index.packages { check_policy(p, config.policy)! }
		objects := image_repository_objects(index)!
		defer { unsafe { objects.free() } }
		verify_release_stage(path, item.text, item.signature, objects, true)!
		needed = mirror_cost(needed, u64(item.text.len + item.signature.len))!
		for _, payload in objects { needed = mirror_cost(needed, payload.bytes)! }
		pointer := unsafe { &item }
		unsafe { plan.repositories.push_many(pointer, 1) }
		transferred = true
	}
	// Check both filesystems before making a potentially large private capture.
	ancestor := image_repositories_parents(plan.root)!
	temporary := os.real_path(os.temp_dir())
	defer { unsafe { ancestor.free(); temporary.free() } }
	disk_check(options.available_space(ancestor)!, needed, 64 * 1024 * 1024)!
	scratch := if os.stat(ancestor)!.dev == os.stat(temporary)!.dev { mirror_cost(needed, needed)! } else { needed }
	disk_check(options.available_space(temporary)!, scratch, 64 * 1024 * 1024)!
	plan.capture = export_stage(temporary, '.vinix-image-repositories')!
	for item in plan.repositories { image_repository_copy(physical + '/' + item.id, plan.capture + '/' + item.id, item)! }
	unsafe { &plan }.verify(plan.capture, 0o700)!
	options.checkpoint('captured', plan.capture)!
	accepted = true
	return ImageRepositories{ ...plan, needed: needed }
}

pub fn (plan &ImageRepositories) publish() !bool { return plan.publish_with(ImageRepositoriesOptions{}) }

fn (plan &ImageRepositories) publish_with(options ImageRepositoriesOptions) !bool {
	if plan.capture == '' { return false }
	plan.current()!
	ancestor := image_repositories_parents(plan.root)!
	defer { unsafe { ancestor.free() } }
	target := plan.root + image_repositories_path
	parent := os.dir(target)
	defer { unsafe { target.free(); parent.free() } }
	if image_configuration_exists(target)! { plan.verify(target, 0o755)!; return false }
	disk_check(options.available_space(ancestor)!, plan.needed, 64 * 1024 * 1024)!
	os.mkdir_all(parent, mode: 0o755)!
	checked := image_repositories_parents(plan.root)!
	unsafe { checked.free() }
	stage := export_stage(parent, '.vinix-image-repositories')!
	mut published := false
	defer { if !published { os.rmdir_all(stage) or {} }; unsafe { stage.free() } }
	for item in plan.repositories { image_repository_copy(plan.capture + '/' + item.id, stage + '/' + item.id, item)! }
	options.checkpoint('staged', stage)!
	plan.verify(stage, 0o700)!
	plan.current()!
	checked_parent := image_repositories_parents(plan.root)!
	unsafe { checked_parent.free() }
	os.chmod(stage, 0o755)!
	sync_directory(stage)!
	plan.verify(stage, 0o755)!
	publish_new_directory(stage, target, 'image repositories')!
	published = true
	sync_directory(parent) or { return error('image repositories saved, but parent flush failed; inspect the staged image before retrying') }
	return true
}

pub fn (mut plan ImageRepositories) close() {
	if plan.capture != '' { os.rmdir_all(plan.capture) or {} }
	for item in plan.repositories {
		unsafe { item.id.free(); item.text.free(); item.signature.free() }
		close_decoded_index(item.index)
	}
	unsafe { plan.root.free(); plan.configuration.free(); plan.architecture.free(); plan.capture.free(); plan.repositories.free() }
	plan = ImageRepositories{}
}
