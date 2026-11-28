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
	bundle ?RepositoryMedia
	has_deployment bool
	receipt ?IsoPackageReceipt
	deployment_text string
}

fn (mut batch RepositoryMediaBatch) close() {
	for id, media in batch.sources {
		C.close(media.fd)
		unsafe { id.free(); media.path.free() }
	}
	unsafe { batch.sources.free(); batch.deployment_text.free() }
	if bundle := batch.bundle {
		C.close(bundle.fd)
		unsafe { bundle.path.free() }
	}
}

fn (bundle RepositoryMedia) member_exists(name string) !bool {
	mut info := C.stat{}
	if C.fstatat(bundle.fd, name.str, unsafe { &info }, C.AT_SYMLINK_NOFOLLOW) == 0 { return true }
	if C.errno == C.ENOENT { return false }
	return error('cannot inspect offline media bundle entry: ${name}')
}

fn (mut batch RepositoryMediaBatch) open_bundle(directory string, config Config) ! {
	bundle := open_repository_media(directory)!
	batch.bundle = bundle
	for repository in config.repositories {
		if !bundle.member_exists(repository.id)! { continue }
		bundle.check()!
		path := bundle.path + '/' + repository.id
		defer { unsafe { path.free() } }
		batch.sources[repository.id] = open_repository_media(path)!
	}
	batch.has_deployment = bundle.member_exists(pkgprotocol.deployment_mirror_filename)!
	batch.check_receipt_publishers(config)!
	batch.check_bundle()!
	if batch.sources.len == 0 { return error('offline media bundle contains no enrolled repositories') }
	if receipt := batch.receipt {
		path := bundle.path + '/' + pkgprotocol.deployment_mirror_filename
		defer { unsafe { path.free() } }
		batch.deployment_text = read_release_lock_matching_digest(path, receipt.deployment_sha256)!
	}
}

fn (batch &RepositoryMediaBatch) check_receipt_publishers(config Config) ! {
	if receipt := batch.receipt {
		if receipt.architecture != config.architecture { return error('offline media receipt architecture differs from the installation') }
		if batch.sources.len != receipt.publishers.len { return error('offline media publishers differ from the ISO package receipt') }
		mut seen := map[string]bool{}
		defer { unsafe { seen.free() } }
		for pin in receipt.publishers {
			if pin.id in seen || pin.id !in batch.sources || pin.sequence == 0 || !digest_valid(pin.index_sha256) {
				return error('invalid or missing offline media publisher pin: ${pin.id}')
			}
			if !config.repositories.any(it.id == pin.id && it.public_key == pin.public_key) {
				return error('ISO package receipt publisher key differs from the enrolled key: ${pin.id}')
			}
			seen[pin.id] = true
		}
	}
}

fn (batch &RepositoryMediaBatch) check_bundle() ! {
	if bundle := batch.bundle {
		mut entries := map[string]u64{}
		defer { unsafe { entries.free() } }
		for id, _ in batch.sources {
			defer { unsafe { id.free() } }
			entries[id] = 0
		}
		bundle.check()!
		if batch.has_deployment {
			name := pkgprotocol.deployment_mirror_filename
			entries[name] = 0
			path := bundle.path + '/' + name
			defer { unsafe { path.free() } }
			if batch.deployment_text == '' { export_stage_file(path)! }
			else { export_stage_metadata(path, batch.deployment_text)! }
		} else if batch.receipt != none {
			return error('offline media is missing the ISO package receipt deployment lock')
		}
		export_stage_directory(bundle.path, entries, 0)!
		bundle.check()!
	}
}

fn (batch &RepositoryMediaBatch) check_receipt_deployment(catalog Catalog) ! {
	if receipt := batch.receipt {
		mut document := decode_offline_application_lock(batch.deployment_text, receipt.architecture, receipt.applications)!
		defer { document.close() }
		// The combined catalog can also contain snapshots from earlier imports.
		// Every pin in this release must be backed by one of the delivered indexes.
		for pin in document.locked {
			if pin.repository !in batch.sources {
				return error('${pin.id}: offline media deployment publisher is absent from the bundle: ${pin.repository}')
			}
		}
		candidates := locked_deployment_candidates(catalog, document)!
		unsafe { (&array(&candidates)).free() }
	}
}

fn (batch &RepositoryMediaBatch) check_receipt_snapshot(repository Repository, index Index, text string) ! {
	if receipt := batch.receipt {
		for pin in receipt.publishers {
			if pin.id != repository.id { continue }
			digest := index_digest(text)
			defer { unsafe { digest.free() } }
			if digest != pin.index_sha256 || index.sequence != pin.sequence {
				return error('offline repository index differs from the ISO package receipt: ${repository.id}')
			}
			objects := signed_release_objects(index, 0)!
			defer { unsafe { objects.free() } }
			check_iso_offline_payload_bytes(pin, objects)!
			return
		}
	}
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
	batch.check_bundle()!
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
