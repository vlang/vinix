// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os

pub struct ReleaseInfo {
pub:
	format        int = 1
	repository    string
	public_key    string
	sequence      u64
	expires       i64
	index_sha256  string
	directory     string
	package_count int
	object_count  int
}

// Reply metadata owns its strings independently of the publisher and caller.
// Closing a reply preserves signed releases, private keys and sequence floors.
pub fn (mut info ReleaseInfo) close() {
	unsafe { info.repository.free(); info.public_key.free(); info.index_sha256.free(); info.directory.free() }
	info = ReleaseInfo{}
}

struct ReleaseHistory {
	format  int = 1
	indexes []RepositoryFloor
}

struct ReleaseOptions {
	checkpoint fn (string, string) ! = mirror_no_checkpoint
	available_space fn (string) !u64 = free_bytes
}

fn check_publisher_lock(fd int, path string) ! {
	mut opened := C.stat{}
	mut named := C.stat{}
	if C.fstat(fd, unsafe { &opened }) != 0 || opened.st_mode & 0o170000 != 0o100000
		|| opened.st_uid != u32(os.geteuid()) || opened.st_mode & 0o077 != 0 || opened.st_nlink != 1
		|| C.fstatat(C.AT_FDCWD, path.str, unsafe { &named }, C.AT_SYMLINK_NOFOLLOW) != 0
		|| named.st_mode & 0o170000 != 0o100000 || named.st_dev != opened.st_dev || named.st_ino != opened.st_ino {
		return error('publisher lock must be a stable private ordinary file owned by this administrator without hard links')
	}
}

fn publisher_lock(repository string) !Lock {
	mut info := C.stat{}
	if C.lstat(repository.str, unsafe { &info }) != 0 { return error('cannot inspect publisher workspace') }
	if info.st_mode & 0o170000 != 0o040000 || info.st_uid != u32(os.geteuid()) || info.st_mode & 0o022 != 0 {
		return error('publisher workspace must be an ordinary directory owned by this administrator and not writable by other users')
	}
	physical := publisher_real_path(repository)!
	directory := repository + '/.publisher'
	defer { unsafe { physical.free(); directory.free() } }
	check_export_parent(physical, 'publisher workspace')!
	owned_directory(directory, 0o700)!
	sync_directory(repository)!
	path := repository + '/.publisher/lock'
	defer { unsafe { path.free() } }
	fd := C.open(path.str, C.O_RDWR | C.O_CREAT | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK, 0o600)
	if fd < 0 { return error('cannot open publisher release lock') }
	check_publisher_lock(fd, path) or { C.close(fd); return err }
	if C.flock(fd, C.LOCK_EX | C.LOCK_NB) != 0 {
		C.close(fd)
		return error('another publisher release or workspace change is running; try again when it finishes')
	}
	check_publisher_lock(fd, path) or { C.close(fd); return err }
	return Lock{ fd: fd }
}

fn release_history(repository string) !TrustHistory {
	path := repository + '/.publisher/history.json'
	defer { unsafe { path.free() } }
	if history_file_missing(path) { return TrustHistory{} }
	text := read_metadata(path)!
	defer { unsafe { text.free() } }
	if history := decode_history(text, true) { return history } else {
		message := unsafe { (&err).msg() }
		diagnostic := 'invalid publisher release history: ' + message
		unsafe { message.free(); (&err).free() }
		return error(diagnostic)
	}
}

// Check structural installability without accepting licenses or changing any
// consumer policy. Force each advertised version so a newer working version
// cannot hide a broken older one. Data declared "all" must resolve on both hosts.
fn release_closures(index Index, public_key string) ! {
	mut licenses := []string{}
	mut candidates := []Installed{}
	unsafe { licenses.flags |= .noslices; candidates.flags |= .noslices }
	defer { unsafe { (&array(&licenses)).free(); (&array(&candidates)).free() } }
	for p in index.packages {
		if p.proprietary && p.license !in licenses {
			pointer := unsafe { &p.license }
			unsafe { licenses.push_many(pointer, 1) }
		}
		candidates << Installed{ package: p, repository: index.repository, public_key: public_key, sequence: index.sequence }
	}
	candidates.sort_with_compare(candidate_order)
	policy := Policy{ licenses: licenses, allow_firmware: true, reserve_bytes: 0 }
	defer { unsafe { (&array(&policy.permissions)).free() } }
	mut fixed := []int{len: 1}
	defer { unsafe { fixed.free() } }
	mut steps := 0
	for root_index, candidate in candidates {
		p := candidate.package
		for architecture in ['aarch64', 'x86_64']! {
			if p.architecture !in [architecture, 'all'] { continue }
			config := Config{ architecture: architecture, policy: policy }
			// Start with this exact root selected, rather than copying the entire
			// catalog once per version (the CLI uses -gc none).
			mut search := &Search{ config: config, candidates: candidates, steps: steps }
			defer { unsafe { search.diagnostic.free(); free(search) } }
			fixed[0] = root_index
			result := search.solve_fixed(p.dependencies, fixed) or {
				cause := err.msg()
				message := 'publisher dependency closure failed for ${p.id}/${p.architecture}/${p.version} on ${architecture}: ${cause}'
				unsafe { cause.free(); err.free() }
				return error(message)
			}
			unsafe { (&array(&result)).free() }
			steps = search.steps
		}
	}
}

pub fn publish_release(repository string, id string, seed_path string, sequence u64, expires i64, destination string) !ReleaseInfo {
	workspace := publisher_workspace(repository, false)!
	defer { unsafe { workspace.free() } }
	guard := publisher_lock(workspace)!
	defer { guard.release() }
	return release_locked(workspace, id, seed_path, sequence, expires, destination, ReleaseOptions{})
}

fn release_locked(repository string, id string, seed_path string, sequence u64, expires i64, destination string, options ReleaseOptions) !ReleaseInfo {
	target := export_target(destination, 'publisher release')!
	defer { unsafe { target.free() } }
	if seed_path == '' || seed_path.contains('\x00') { return error('publisher signing seed requires a valid private-file path') }
	mut seed_info := C.stat{}
	if C.fstatat(C.AT_FDCWD, seed_path.str, unsafe { &seed_info }, C.AT_SYMLINK_NOFOLLOW) == 0 && seed_info.st_mode & 0o170000 == 0o120000 {
		return error('publisher signing seed must be a private ordinary file owned by this administrator')
	}
	// Resolve aliases in the parent, retaining the caller's leaf for the
	// no-follow open. real_path(seed_path) could follow a substituted leaf.
	raw_parent := os.dir(seed_path)
	defer { unsafe { raw_parent.free() } }
	seed_parent := publisher_real_path(raw_parent)!
	seed_name := os.file_name(seed_path)
	defer { unsafe { seed_parent.free(); seed_name.free() } }
	if seed_name in ['', '.', '..']! { return error('publisher signing seed requires a valid private-file path') }
	check_export_parent(seed_parent, 'publisher signing seed')!
	trimmed_parent := seed_parent.trim_right('/')
	defer { unsafe { trimmed_parent.free() } }
	signing_seed := trimmed_parent + '/' + seed_name
	defer { unsafe { signing_seed.free() } }
	seed := read_signing_seed(signing_seed, SigningSeedOptions{})!
	defer { seed.close() }
	options.checkpoint('seed', signing_seed)!
	index, text, signature, public_key := publication_with_seed(repository, id, seed, sequence, expires)!
	defer { close_decoded_index(index); unsafe { text.free(); signature.free(); public_key.free() } }
	identity := Repository{ id: id, public_key: public_key }
	history := release_history(repository)!
	defer { close_decoded_history(history) }
	remembered := remember_index(history, identity, index, text)!
	defer { close_decoded_history(remembered) }
	release_closures(index, public_key)!
	mut objects := map[string]Payload{}
	defer { unsafe { objects.free() } }
	mut needed := mirror_cost(u64(4 * 1024 * 1024), u64(text.len + signature.len))!
	for p in index.packages {
		for payload in p.files {
			if payload.sha256 == seed.file_sha256 { return error('publisher release would include the signing seed as a payload') }
			if payload.sha256 in objects { continue }
			objects[payload.sha256] = payload
			needed = mirror_cost(needed, payload.bytes)!
		}
	}
	parent := os.dir(target)
	defer { unsafe { parent.free() } }
	disk_check(options.available_space(parent)!, needed, 64 * 1024 * 1024)!
	mut exporting := create_export_stage(parent, '.vinix-release', 'publisher release')!
	defer { exporting.close() }
	write_release_stage(repository, text, signature, objects, remembered, options, target, mut exporting) or {
		return exporting.failure(err)
	}
	return ReleaseInfo{ repository: id.clone(), public_key: public_key.clone(), sequence: sequence, expires: expires,
		index_sha256: index_digest(text), directory: target.clone(), package_count: index.packages.len, object_count: objects.len }
}

fn write_release_stage(repository string, text string, signature string, objects map[string]Payload, remembered TrustHistory, options ReleaseOptions, target string, mut exporting ExportStage) ! {
	stage := exporting.path
	options.checkpoint('created', stage)!
	exporting.check()!
	objects_path := stage + '/objects'; index_path := stage + '/index.json'; signature_path := stage + '/index.sig'; signed_text := signature + '\n'
	defer { unsafe { objects_path.free(); index_path.free(); signature_path.free(); signed_text.free() } }
	// The stage is already captured. Create its child directly: os.mkdir's
	// real_path scratch is retained by the pinned manual-free compiler.
	if C.mkdir(objects_path.str, 0o777) != 0 { return error('cannot create publisher release objects directory') }
	mut hashes := objects.keys()
	defer { unsafe { hashes.free() } }
	hashes.sort()
	for hash in hashes {
		payload := objects[hash]
		path := stage + '/objects/' + hash
		source := repository + '/objects/' + hash
		defer { unsafe { path.free(); source.free() } }
		copy_file(source, path, 0, payload.bytes)!
		options.checkpoint('copied', path)!
		exporting.check()!
		if !verified_file(path, payload) { return error('publisher release payload changed while copying: ${hash}') }
		os.chmod(path, 0o644)!
		sync_file(path)!
	}
	atomic_write(index_path, text)!
	atomic_write(signature_path, signed_text)!
	options.checkpoint('staged', stage)!
	exporting.check()!
	verify_release_stage(stage, text, signature, objects, false) or {
		cause := unsafe { (&err).msg() }
		message := 'publisher release verification failed before sequence reservation: ' + cause
		unsafe { cause.free(); (&err).free() }
		return error(message)
	}
	// Keep the root private while flushing children. Even a discoverable hidden
	// staging name must not expose a signed index before history is reserved.
	flush_tree(objects_path)!
	sync_directory(stage)!
	// Reserve this sequence/digest durably before exposing signed bytes. A failed
	// export may retry exactly these inputs, but must not fork the same sequence.
	history_path := repository + '/.publisher/history.json'
	defer { unsafe { history_path.free() } }
	write_administration_document(history_path, ReleaseHistory{ indexes: remembered.repositories },
		'package administration metadata exceeds its size limit') or {
		cause := unsafe { (&err).msg() }
		message := 'cannot durably reserve publisher sequence; check storage and retry the same inputs or choose a newer sequence: ' + cause
		unsafe { cause.free(); (&err).free() }
		return error(message)
	}
	os.chmod(stage, 0o755)!
	sync_directory(stage)!
	options.checkpoint('reserved', stage)!
	exporting.check()!
	verify_release_stage(stage, text, signature, objects, true) or {
		cause := unsafe { (&err).msg() }
		message := 'publisher release verification failed after sequence reservation; retry the same inputs or choose a newer sequence: ' + cause
		unsafe { cause.free(); (&err).free() }
		return error(message)
	}
	exporting.publish(target)!
}
