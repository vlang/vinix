// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os
import time

pub const image_repositories_path = '/usr/share/vinix-packages/repositories'
const max_image_repository_indexes = 4096
const image_repository_directory_names = ['usr', 'share', 'vinix-packages']!

struct ImageRepository {
	id string
	text string
	signature string
	index Index
	reviewed_origin string
}

pub struct ImageRepositoryIndex {
pub:
	id string
	index_sha256 string
	origin string // When supplied, require this exact reviewed HTTPS URL.
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
	archived_at i64
mut:
	// capture borrows the owned guard's path; the guard alone closes it.
	capture string
	capture_stage ExportStage
	repositories []ImageRepository
}

struct ImageRepositoriesOptions {
	available_space fn (string) !u64 = free_bytes
	checkpoint fn (string, string) ! = mirror_no_checkpoint
	temporary_directory fn () string = import_temporary_directory
	scratch string
	flush fn (int) int = atomic_flush
	required_indexes []ImageRepositoryIndex
	archived_at i64
}

fn image_repository_objects(index Index) !map[string]Payload {
	return signed_release_objects(index, max_files)
}

fn signed_release_objects(index Index, limit int) !map[string]Payload {
	mut objects := map[string]Payload{}
	mut accepted := false
	defer { if !accepted { unsafe { objects.free() } } }
	for p in index.packages {
		for payload in p.files {
			if payload.sha256 in objects && objects[payload.sha256].bytes != payload.bytes {
				return error('image repository has inconsistent authenticated object lengths')
			}
			objects[payload.sha256] = payload
			if limit > 0 && objects.len > limit { return error('image repository exceeds the bundled object limit') }
		}
	}
	accepted = true
	return objects
}

fn image_repository_copy(source string, target string, repository ImageRepository) ! {
	if C.mkdir(target.str, 0o700) != 0 { return error('cannot create image repository directory') }
	object_path := target + '/objects'
	index_path := target + '/index.json'
	signature_path := target + '/index.sig'
	signed_text := repository.signature + '\n'
	defer { unsafe { object_path.free(); index_path.free(); signature_path.free(); signed_text.free() } }
	if C.mkdir(object_path.str, 0o755) != 0 { return error('cannot create image repository object directory') }
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
	atomic_write_new(index_path, repository.text)!
	atomic_write_new(signature_path, signed_text)!
	verify_release_stage(target, repository.text, repository.signature, objects, false)!
	flush_tree(object_path)!
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
	plan.verify_at(directory, mode, 0)!
}

fn release_index_time(archived_at i64) i64 {
	return if archived_at == 0 { time.now().unix() } else { archived_at }
}

fn (plan &ImageRepositories) verify_at(directory string, mode u32, archived_at i64) ! {
	if directory == plan.capture && plan.capture != '' { plan.capture_stage.check()! }
	mut entries := map[string]u64{}
	defer { unsafe { entries.free() } }
	for repository in plan.repositories { entries[repository.id] = 0 }
	export_stage_directory(directory, entries, mode)!
	for repository in plan.repositories {
		if repository.index.expires <= release_index_time(archived_at) { return error('image repository expired after preparation; obtain a current signed release') }
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

// Pin the authenticated index bytes for selected bundled publishers before
// copying any repository into the private capture.
pub fn (configuration &ImageConfiguration) prepare_repositories_for_indexes(source string,
	required []ImageRepositoryIndex) !ImageRepositories {
	return configuration.prepare_repositories_with(source, ImageRepositoriesOptions{ required_indexes: required })
}

// A reviewed file names one repository ID and index digest per line, followed
// by the HTTPS URL for hosted pins. Entries borrow the captured file bytes.
pub fn (configuration &ImageConfiguration) prepare_repositories_for_index_file(source string,
	index_file string, scratch string) !ImageRepositories {
	if index_file == '' { return configuration.prepare_repositories_in(source, scratch) }
	text := read_metadata(index_file)!
	defer { unsafe { text.free() } }
	mut required := []ImageRepositoryIndex{}
	unsafe { required.flags |= .noslices }
	defer { unsafe { (&array(&required)).free() } }
	mut start := 0
	for end in 0 .. text.len + 1 {
		if end < text.len && text[end] != `\n` { continue }
		if start == text.len { break }
		length := end - start - if end < text.len && end > start && text[end - 1] == `\r` { 1 } else { 0 }
		line := unsafe { tos(text.str + start, length) }
		separator := line.index(' ') or { -1 }
		if separator < 1 || required.len == max_image_repository_indexes {
			return error('image repository index file requires an ID and lowercase SHA-256 digest with an optional HTTPS origin per line, up to 4096 indexes')
		}
		digest_end := line.index_after(' ', separator + 1) or { line.len }
		if digest_end == line.len - 1 {
			return error('image repository index file requires a valid HTTPS origin after the digest')
		}
		required << ImageRepositoryIndex{
			id: unsafe { tos(line.str, separator) }
			index_sha256: unsafe { tos(line.str + separator + 1, digest_end - separator - 1) }
			origin: if digest_end < line.len {
				unsafe { tos(line.str + digest_end + 1, line.len - digest_end - 1) }
			} else { '' }
		}
		start = end + 1
	}
	if required.len == 0 { return error('image repository index file must name at least one index') }
	return configuration.prepare_repositories_with(source, ImageRepositoriesOptions{
		required_indexes: required
		scratch: scratch
	})
}

// Capture into a caller-selected scratch filesystem for temporary image checks.
pub fn (configuration &ImageConfiguration) prepare_repositories_in(source string, scratch string) !ImageRepositories {
	return configuration.prepare_repositories_with(source, ImageRepositoriesOptions{ scratch: scratch })
}

fn (configuration &ImageConfiguration) prepare_repositories_with(source string, options ImageRepositoriesOptions) !ImageRepositories {
	if source == '' {
		if options.required_indexes.len != 0 { return error('required image repository indexes need a signed bundle') }
		return ImageRepositories{}
	}
	if !image_configuration_root_matches(configuration.root, configuration.device, configuration.inode) { return error('package image root changed before repository preparation') }
	text := if configuration.existing { read_metadata(configuration.path)! } else { configuration.text.clone() }
	mut plan := ImageRepositories{ root: configuration.root.clone(), configuration: text,
		configuration_existing: configuration.existing, architecture: configuration.architecture.clone(),
		device: configuration.device, inode: configuration.inode, needed: 4 * 1024 * 1024,
		archived_at: options.archived_at }
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
	physical := publisher_real_path(input)!
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
		url := 'file://' + image_repositories_path + '/' + repository.id
		path := physical + '/' + repository.id
		defer { unsafe { url.free(); path.free() } }
		if repository.url == url || (repository.url.starts_with('https://') && publisher_entry_exists(path)) {
			expected[repository.id] = 0
		}
	}
	if expected.len == 0 { return error('image repository bundle needs configured HTTPS or image file repositories') }
	mut reviewed := map[string]ImageRepositoryIndex{}
	defer { unsafe { reviewed.free() } }
	for required in options.required_indexes {
		if !identifier(required.id) || !digest_valid(required.index_sha256) {
			return error('required image repository index needs a repository ID and lowercase SHA-256 digest')
		}
		if required.origin != '' && !valid_release_origin(required.origin) {
			return error('required image repository index needs a valid HTTPS origin: ${required.id}')
		}
		if required.id in reviewed { return error('duplicate required image repository index: ${required.id}') }
		if required.id !in expected { return error('required image repository is not bundled: ${required.id}') }
		reviewed[required.id] = required
	}
	export_stage_directory(physical, expected, 0)!
	mut needed := u64(4 * 1024 * 1024)
	for repository in config.repositories {
		if repository.id !in expected { continue }
		required := reviewed[repository.id]
		if required.origin != '' && required.origin != repository.url {
			return error('bundled image repository URL differs from the reviewed HTTPS origin: ${repository.id}')
		}
		path := physical + '/' + repository.id
		defer { unsafe { path.free() } }
		index_path := path + '/index.json'
		signature_path := path + '/index.sig'
		defer { unsafe { index_path.free(); signature_path.free() } }
		index_text := read_metadata(index_path)!
		mut item := ImageRepository{ id: repository.id.clone(), text: index_text, reviewed_origin: required.origin.clone() }
		mut transferred := false
		defer { if !transferred { unsafe { item.id.free(); item.text.free(); item.signature.free(); item.reviewed_origin.free() }; close_decoded_index(item.index) } }
		signature := read_metadata(signature_path)!
		defer { unsafe { signature.free() } }
		item = ImageRepository{ ...item, signature: signature.trim_space() }
		index := verify_index(repository, item.text, item.signature, release_index_time(options.archived_at))!
		item = ImageRepository{ ...item, index: index }
		if required.index_sha256 != '' {
			actual := index_digest(item.text)
			defer { unsafe { actual.free() } }
			if actual != required.index_sha256 { return error('bundled image repository index differs from the reviewed digest: ${repository.id}') }
		}
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
	defer { unsafe { ancestor.free() } }
	temporary_path := if options.scratch == '' { options.temporary_directory() } else { options.scratch.clone() }
	defer { unsafe { temporary_path.free() } }
	temporary := publisher_real_path(temporary_path)!
	defer { unsafe { temporary.free() } }
	disk_check(options.available_space(ancestor)!, needed, 64 * 1024 * 1024)!
	mut output_info := C.stat{}
	mut temporary_info := C.stat{}
	if C.fstatat(C.AT_FDCWD, ancestor.str, unsafe { &output_info }, 0) != 0
		|| C.fstatat(C.AT_FDCWD, temporary.str, unsafe { &temporary_info }, 0) != 0 {
		return error('cannot inspect image repository capture filesystems')
	}
	scratch := if output_info.st_dev == temporary_info.st_dev { mirror_cost(needed, needed)! } else { needed }
	disk_check(options.available_space(temporary)!, scratch, 64 * 1024 * 1024)!
	mut capturing := create_export_stage(temporary, '.vinix-image-repositories', 'image repository capture')!
	mut transferred := false
	defer { if !transferred { capturing.close() } }
	unsafe { &plan }.capture_from(physical, options, mut capturing) or { return capturing.failure(err) }
	plan.capture_stage = capturing
	plan.capture = capturing.path
	transferred = true
	accepted = true
	return ImageRepositories{ ...plan, needed: needed }
}

fn (plan &ImageRepositories) capture_from(source string, options ImageRepositoriesOptions, mut capturing ExportStage) ! {
	for item in plan.repositories {
		input := source + '/' + item.id
		target := capturing.path + '/' + item.id
		defer { unsafe { input.free(); target.free() } }
		image_repository_copy(input, target, item)!
	}
	plan.verify_at(capturing.path, 0o700, options.archived_at)!
	options.checkpoint('captured', capturing.path)!
	capturing.check()!
	plan.verify_at(capturing.path, 0o700, options.archived_at)!
}

pub fn (plan &ImageRepositories) publish() !bool { return plan.publish_with(ImageRepositoriesOptions{}) }

// Open the selected range of package directories through an already held
// ancestor. Only the remaining components may need to be created.
fn open_image_repository_directories(ancestor int, start int, end int, create bool) !int {
	mut directory := C.openat(ancestor, c'.', C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW)
	if directory < 0 { return error('cannot retain image repository ancestor') }
	mut accepted := false
	defer { if !accepted { C.close(directory) } }
	for i in start .. end {
		next := open_image_package_directory(directory, image_repository_directory_names[i], create, 'repository')!
		C.close(directory)
		directory = next
	}
	accepted = true
	return directory
}

fn (plan &ImageRepositories) publish_with(options ImageRepositoriesOptions) !bool {
	if plan.capture == '' { return false }
	plan.current()!
	plan.verify(plan.capture, 0o700)!
	ancestor := image_repositories_parents(plan.root)!
	defer { unsafe { ancestor.free() } }
	target := plan.root + image_repositories_path
	parent := os.dir(target)
	defer { unsafe { target.free(); parent.free() } }
	root := capture_prepared_root(plan.root, 'image repositories')!
	defer { C.close(root) }
	mut info := C.stat{}
	if C.fstat(root, unsafe { &info }) != 0 || u64(info.st_dev) != plan.device || u64(info.st_ino) != plan.inode {
		return error('package image root changed before repository publication')
	}
	depth := ancestor.count('/') - plan.root.count('/')
	ancestor_fd := open_image_repository_directories(root, 0, depth, false)!
	defer { C.close(ancestor_fd) }
	if !atomic_captured_parent_matches(ancestor, ancestor_fd) {
		return error('image repository ancestor changed before publication')
	}
	if image_configuration_exists(target)! {
		if ancestor != parent { return error('image repository parent appeared during publication; retry') }
		directory := open_image_package_directory(ancestor_fd, 'repositories', false, 'repository')!
		defer { C.close(directory) }
		if !atomic_captured_parent_matches(target, directory) {
			return error('published image repository directory changed before verification')
		}
		plan.verify(target, 0o755)!
		options.checkpoint('verified-existing', target)!
		plan.current()!
		checked := image_repositories_parents(plan.root)!
		unsafe { checked.free() }
		if !atomic_captured_parent_matches(parent, ancestor_fd) || !atomic_captured_parent_matches(target, directory) {
			return error('published image repository directory changed during verification')
		}
		return false
	}
	disk_check(options.available_space(ancestor)!, plan.needed, 64 * 1024 * 1024)!
	plan.current()!
	checked := image_repositories_parents(plan.root)!
	unsafe { checked.free() }
	if !atomic_captured_parent_matches(ancestor, ancestor_fd) {
		return error('image repository ancestor changed before publication')
	}
	directory := open_image_repository_directories(ancestor_fd, depth, image_repository_directory_names.len, true)!
	defer { C.close(directory) }
	mut exporting := create_export_stage_with_parent(parent, '.vinix-image-repositories', 'image repositories', directory)!
	defer { exporting.close() }
	plan.write_stage(target, options, mut exporting) or { return exporting.failure(err) }
	return true
}

fn (plan &ImageRepositories) write_stage(target string, options ImageRepositoriesOptions, mut exporting ExportStage) ! {
	stage := exporting.path
	plan.capture_stage.check()!
	for item in plan.repositories {
		input := plan.capture + '/' + item.id
		target_path := stage + '/' + item.id
		defer { unsafe { input.free(); target_path.free() } }
		image_repository_copy(input, target_path, item)!
	}
	options.checkpoint('staged', stage)!
	exporting.check()!
	plan.verify(plan.capture, 0o700)!
	plan.verify(stage, 0o700)!
	exporting.check()!
	if C.fchmod(exporting.root, 0o755) != 0 { return error('cannot set published image repository directory mode') }
	sync_directory(stage)!
	plan.verify(stage, 0o755)!
	plan.current()!
	checked_parent := image_repositories_parents(plan.root)!
	unsafe { checked_parent.free() }
	exporting.publish_with(target, options.flush)!
}

// Report refusal while always closing descriptors/metadata. Replaced recovery
// trees remain on disk for inspection. close() retains its best-effort contract.
pub fn (mut plan ImageRepositories) retire() ! {
	defer { plan.close_metadata() }
	if plan.capture != '' {
		plan.capture_stage.retire() or {
			cause := unsafe { (&err).msg() }
			message := 'image repository capture cleanup refused at ' + plan.capture + ': ' + cause + '; retain recovery data for inspection'
			unsafe { cause.free(); (&err).free() }
			return error(message)
		}
	}
}

pub fn (mut plan ImageRepositories) close() {
	plan.retire() or { message := err.msg(); unsafe { message.free(); err.free() } }
}

fn (mut plan ImageRepositories) close_metadata() {
	for item in plan.repositories {
		unsafe { item.id.free(); item.text.free(); item.signature.free(); item.reviewed_origin.free() }
		close_decoded_index(item.index)
	}
	plan.capture_stage.close()
	unsafe { plan.root.free(); plan.configuration.free(); plan.architecture.free(); plan.repositories.free() }
	plan = ImageRepositories{}
}
