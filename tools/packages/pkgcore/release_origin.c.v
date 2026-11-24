// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os
import time
import tools.packages.pkgprotocol

pub struct ReleaseOriginInfo {
pub:
	format  int = 1
	url     string
	release ReleaseInfo
}

pub fn (mut info ReleaseOriginInfo) close() {
	unsafe { info.url.free() }
	mut release := info.release
	release.close()
	info = ReleaseOriginInfo{}
}

// Compare a hosted repository with a complete signed export using the caller's
// independently verified publisher key. Only the private transfer stage is written.
pub fn check_release_origin(directory string, id string, public_key string, url string) !ReleaseOriginInfo {
	if !identifier(id) { return error('invalid release repository ID') }
	if !url.starts_with('https://') || !pkgprotocol.valid_repository_url(url) {
		return error('release origin requires a valid HTTPS repository URL')
	}
	path := publisher_path(directory)!
	defer { unsafe { path.free() } }
	fd := capture_prepared_root(path, 'signed release export')!
	defer { C.close(fd) }
	release := publisher_real_path(path)!
	defer { unsafe { release.free() } }
	mut info := C.stat{}
	if C.fstat(fd, unsafe { &info }) != 0 || !atomic_parent_matches(release, u64(info.st_dev), u64(info.st_ino)) {
		return error('signed release export changed during admission')
	}
	check_export_parent(release, 'signed release export')!
	index_path := release + '/index.json'
	signature_path := release + '/index.sig'
	defer {
		unsafe {
			index_path.free()
			signature_path.free()
		}
	}
	text := read_metadata(index_path)!
	defer { unsafe { text.free() } }
	signature := read_metadata(signature_path)!
	defer { unsafe { signature.free() } }
	index := verify_index(Repository{ id: id, public_key: public_key }, text, signature, time.now().unix())!
	defer { close_decoded_index(index) }
	trimmed := signature.trim_space()
	defer { unsafe { trimmed.free() } }
	objects := signed_release_objects(index, 0)!
	defer { unsafe { objects.free() } }
	release_closures(index, public_key)!
	verify_release_stage(release, text, trimmed, objects, true)!
	check_hosted_release(fd, url, text, signature, objects)!
	if !atomic_parent_matches(release, u64(info.st_dev), u64(info.st_ino)) {
		return error('signed release export changed during origin check')
	}
	check_export_parent(release, 'signed release export')!
	verify_release_stage(release, text, trimmed, objects, true)!
	if index.expires <= time.now().unix() {
		return error('signed release expired during origin check')
	}
	return ReleaseOriginInfo{
		url:     url.clone()
		release: ReleaseInfo{
			repository:    id.clone()
			public_key:    public_key.clone()
			index_sha256:  index_digest(text)
			directory:     release.clone()
			sequence:      index.sequence
			expires:       index.expires
			package_count: index.packages.len
			object_count:  objects.len
		}
	}
}

fn check_hosted_release(source int, url string, text string, signature string, objects map[string]Payload) ! {
	temporary := import_temporary_directory()
	defer { unsafe { temporary.free() } }
	parent := publisher_real_path(temporary)!
	defer { unsafe { parent.free() } }
	publisher_outside_source(source, parent)!
	mut maximum := u64(max_metadata)
	for _, object in objects {
		if object.bytes > maximum { maximum = object.bytes }
	}
	disk_check(free_bytes(parent)!, maximum, 0)!
	mut stage := create_export_stage(parent, '.vinix-release-origin', 'release origin check')!
	defer { stage.close() }
	check_hosted_release_stage(stage, url, text, signature, objects) or { return stage.failure(err) }
	stage.retire()!
}

fn check_hosted_release_stage(stage ExportStage, url string, text string, signature string, objects map[string]Payload) ! {
	base := url.trim_right('/')
	index_url := base + '/index.json'
	signature_url := base + '/index.sig'
	object_prefix := base + '/objects/'
	candidate := stage.path + '/response'
	defer {
		unsafe {
			base.free()
			index_url.free()
			signature_url.free()
			object_prefix.free()
			candidate.free()
		}
	}
	check_origin_metadata(stage, index_url, candidate, text, max_metadata, 'index')!
	check_origin_metadata(stage, signature_url, candidate, signature, 256, 'signature')!
	mut hashes := objects.keys()
	defer { unsafe { hashes.free() } }
	hashes.sort()
	for hash in hashes {
		object := objects[hash]
		object_url := object_prefix + hash
		defer { unsafe { object_url.free() } }
		stage.check()!
		fetch(object_url, candidate, object.bytes, false, false)!
		stage.check()!
		if !verified_file(candidate, object) {
			return error('hosted release object differs from its signed hash or size: ' + hash)
		}
	}
	// Read back the index and signature again after the last object so a host
	// switching releases during verification cannot keep its earlier verdict.
	check_origin_metadata(stage, index_url, candidate, text, max_metadata, 'index')!
	check_origin_metadata(stage, signature_url, candidate, signature, 256, 'signature')!
}

fn check_origin_metadata(stage ExportStage, url string, candidate string, expected string, limit u64, kind string) ! {
	stage.check()!
	fetch(url, candidate, limit, false, false)!
	stage.check()!
	actual := read_metadata(candidate)!
	defer { unsafe { actual.free() } }
	if actual != expected { return error('hosted release ' + kind + ' differs from signed export') }
}
