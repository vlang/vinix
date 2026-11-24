// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import tools.packages.pkgprotocol

pub struct RepositoryMediaSource {
pub:
	id string
	directory string
}

struct RepositoryMedia {
	path string
	fd int
}

struct RepositoryMediaBatch {
mut:
	sources map[string]RepositoryMedia
}

fn (mut batch RepositoryMediaBatch) close() {
	for id, media in batch.sources {
		C.close(media.fd)
		unsafe { id.free(); media.path.free() }
	}
	unsafe { batch.sources.free() }
}

fn (batch &RepositoryMediaBatch) snapshot(repository Repository, previous []Snapshot) !Snapshot {
	if source := batch.sources[repository.id] { return source.snapshot(repository) }
	return clone_matching_snapshot(previous, repository)
}

fn open_repository_media(directory string) !RepositoryMedia {
	path := publisher_path(directory)!
	defer { unsafe { path.free() } }
	fd := capture_prepared_root(path, 'offline repository media')!
	mut accepted := false
	defer { if !accepted { C.close(fd) } }
	physical := publisher_real_path(path)!
	media := RepositoryMedia{ path: physical, fd: fd }
	media.check() or { unsafe { physical.free() }; return err }
	accepted = true
	return media
}

fn (media RepositoryMedia) check() ! {
	check_bundle_directory(media.path)!
	if !atomic_captured_parent_matches(media.path, media.fd) {
		return error('offline repository media directory changed during import')
	}
}

fn (media RepositoryMedia) snapshot(repository Repository) !Snapshot {
	media.check()!
	index_path := media.path + '/index.json'
	signature_path := media.path + '/index.sig'
	defer { unsafe { index_path.free(); signature_path.free() } }
	text := read_metadata(index_path)!
	mut accepted := false
	defer { if !accepted { unsafe { text.free() } } }
	raw_signature := read_metadata(signature_path)!
	defer { unsafe { raw_signature.free() } }
	media.check()!
	accepted = true
	return Snapshot{ repository: repository, text: text, signature: raw_signature.trim_space() }
}

struct MediaPayload {
	installed Installed
	payload Payload
}

// Check space before acquisition and cache only variants this installation can
// use under its current policy. The catalog stays complete for later reviews.
fn (batch &RepositoryMediaBatch) import_payloads(config Config, directory string, catalog Catalog,
	report fn (pkgprotocol.Progress)) ! {
	mut seen := map[string]u64{}
	defer { unsafe { seen.free() } }
	mut missing := []MediaPayload{}
	unsafe { missing.flags |= .noslices }
	defer { unsafe { missing.free() } }
	mut needed := u64(0)
	for installed in catalog.packages {
		p := installed.package
		if installed.repository !in batch.sources || p.architecture !in [config.architecture, 'all']! { continue }
		check_policy(p, config.policy) or { unsafe { err.free() }; continue }
		for payload in p.files {
			if payload.sha256 in seen {
				if seen[payload.sha256] != payload.bytes { return error('offline media object has inconsistent signed lengths') }
				continue
			}
			seen[payload.sha256] = payload.bytes
			path := directory + '/objects/' + payload.sha256
			defer { unsafe { path.free() } }
			if verified_file(path, payload) { continue }
			needed = mirror_cost(needed, payload.bytes)!
			entry := MediaPayload{ installed: installed, payload: payload }
			unsafe { missing.push_many(&entry, 1) }
		}
	}
	if missing.len > 0 {
		objects := directory + '/objects'
		defer { unsafe { objects.free() } }
		disk_check(free_bytes(objects)!, needed, config.policy.reserve_bytes)!
	}
	mut start := 0
	for start < missing.len {
		id := missing[start].installed.repository
		mut end := start + 1
		for end < missing.len && missing[end].installed.repository == id { end++ }
		source := batch.sources[id] or { return error('missing offline repository media: ${id}') }
		source.import_group(config, directory, unsafe { missing[start..end] }, report)!
		start = end
	}
	for id, source in batch.sources {
		defer { unsafe { id.free() } }
		source.check()!
	}
}

fn (media RepositoryMedia) import_group(config Config, directory string, missing []MediaPayload,
	report fn (pkgprotocol.Progress)) ! {
	media_objects := media.path + '/objects'
	url := 'file://' + media.path
	defer { unsafe { media_objects.free(); url.free() } }
	media.check()!
	objects_fd := capture_prepared_root(media_objects, 'offline repository objects')!
	defer { C.close(objects_fd) }
	local := [Repository{ id: missing[0].installed.repository, url: url, public_key: missing[0].installed.public_key }]
	defer { unsafe { local.free() } }
	local_config := Config{ ...config, policy: Policy{ ...config.policy, offline: true },
		repositories: local }
	for entry in missing {
		media.check()!
		check_bundle_directory(media_objects)!
		if !atomic_captured_parent_matches(media_objects, objects_fd) {
			return error('offline repository objects directory changed during import')
		}
		path := cached_payload_progress(local_config, entry.installed, entry.payload, directory, report)!
		unsafe { path.free() }
	}
	media.check()!
	if !atomic_captured_parent_matches(media_objects, objects_fd) {
		return error('offline repository objects directory changed during import')
	}
}
