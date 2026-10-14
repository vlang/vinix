// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os
import time
import tools.packages.pkgprotocol

fn C.mkdtemp(&char) &char

struct RepositoryReviewIdentity {
	format       int = 1
	config       Config
	history      TrustHistory
	operation    string
	repository   Repository
	index_sha256 string
}

fn repository_fingerprint(config Config, history TrustHistory, operation string, repository Repository, digest string) string {
	mut bytes := []u8{cap: 2048}
	unsafe { bytes.flags |= .noslices }
	defer { unsafe { bytes.free() } }
	json2.encode_append(RepositoryReviewIdentity{
		config:       config
		history:      history
		operation:    operation
		repository:   repository
		index_sha256: digest
	}, mut bytes)
	// Review identities combine independently bounded documents. Hash the exact
	// existing JSON without adding the persisted-document newline or size limit.
	text := bytes.bytestr()
	defer { unsafe { text.free() } }
	return index_digest(text)
}

fn check_repository_review(expected string, actual string) ! {
	if expected != '' && (!digest_valid(expected) || expected != actual) {
		return error('repository review is stale: trust configuration, sequence history or signed metadata changed; review again')
	}
}

fn enrollment_configuration(current Config, repository Repository) !Config {
	mut repositories := current.repositories.filter(it.id != repository.id)
	unsafe { repositories.flags |= .noslices }
	owned := Repository{ id: repository.id.clone(), url: repository.url.clone(), public_key: repository.public_key.clone() }
	mut accepted := false
	defer { if !accepted { unsafe { owned.id.free(); owned.url.free(); owned.public_key.free(); repositories.free() } } }
	pointer := unsafe { &owned }
	unsafe { repositories.push_many(pointer, 1) }
	repositories.sort(a.id < b.id)
	next := Config{ ...current, repositories: repositories }
	next.validate()!
	key := admitted_publisher_key(repository.public_key)!
	unsafe { key.free() }
	accepted = true
	return next
}

// A proposal owns its array and the new publisher's strings. Retained publisher
// fields and policy still borrow current; only temporary proposals use this.
fn close_enrollment_configuration(config Config, id string) {
	unsafe {
		for repository in config.repositories {
			if repository.id == id { repository.id.free(); repository.url.free(); repository.public_key.free(); break }
		}
		(&array(&config.repositories)).free()
	}
}

fn enrollment_snapshot(config Config, repository Repository, offline bool, work string) !(Snapshot, Index) {
	base := repository.url.trim_right('/')
	index_url := base + '/index.json'
	signature_url := base + '/index.sig'
	index_path := work + '/index.json'
	signature_path := work + '/index.sig'
	defer { unsafe { base.free(); index_url.free(); signature_url.free(); index_path.free(); signature_path.free() } }
	fetch(index_url, index_path, max_metadata, false,
		config.policy.offline || offline)!
	fetch(signature_url, signature_path, 256, false,
		config.policy.offline || offline)!
	return read_enrollment_snapshot(repository, index_path, signature_path)
}

// Transfer both loaded strings only after authentication and metadata admission.
// The decoded index owns independent fields; publisher identity remains borrowed.
fn read_enrollment_snapshot(repository Repository, index_path string, signature_path string) !(Snapshot, Index) {
	text := read_metadata(index_path)!
	mut accepted := false
	defer { if !accepted { unsafe { text.free() } } }
	signature := read_metadata(signature_path)!
	defer { if !accepted { unsafe { signature.free() } } }
	index := verify_index(repository, text, signature, time.now().unix())!
	accepted = true
	return Snapshot{ repository: repository, text: text, signature: signature }, index
}

fn repository_review(config Config, history TrustHistory, operation string, repository Repository, text string, index Index) !pkgprotocol.RepositoryReview {
	previous := config.repositories.filter(it.id == repository.id)
	defer { unsafe { (&array(&previous)).free() } }
	digest := if operation == 'enroll' { index_digest(text) } else { '' }
	mut remembered := u64(0)
	for floor in history.repositories {
		if floor.id == repository.id && floor.public_key == repository.public_key {
			remembered = floor.sequence
		}
	}
	mut review := pkgprotocol.RepositoryReview{
		format:              1
		architecture:        config.architecture.clone()
		operation:           operation.clone()
		id:                  repository.id.clone()
		url:                 repository.url.clone()
		public_key:          repository.public_key.clone()
		previous_url:        if previous.len == 0 { '' } else { previous[0].url.clone() }
		previous_public_key: if previous.len == 0 { '' } else { previous[0].public_key.clone() }
		fingerprint:         repository_fingerprint(config, history, operation, repository, digest)
		index_sha256:        digest
		sequence:            if operation == 'enroll' { index.sequence } else { u64(0) }
		expires:             if operation == 'enroll' { index.expires } else { i64(0) }
		package_count:       if operation == 'enroll' { index.packages.len } else { 0 }
		remembered_sequence: remembered
	}
	mut accepted := false
	defer { if !accepted { review.close() } }
	review.validate()!
	accepted = true
	return review
}

fn read_repository_review(root string, operation string, repository Repository, offline bool) !pkgprotocol.RepositoryReview {
	config := load_config(root)!
	defer { close_decoded_configuration(config) }
	if operation == 'revoke' {
		matches := config.repositories.filter(it.id == repository.id)
		defer { unsafe { (&array(&matches)).free() } }
		if matches.len != 1 { return error('repository is not enrolled: ${repository.id}') }
		// Revocation never needs a readable catalog/history or a reachable publisher.
		return repository_review(config, TrustHistory{}, operation, matches[0], '', Index{})
	}
	if operation != 'enroll' { return error('unknown repository operation') }
	next := enrollment_configuration(config, repository)!
	defer { close_enrollment_configuration(next, repository.id) }
	directory := state_directory(root)
	defer { unsafe { directory.free() } }
	snapshots := read_snapshots(directory)!
	defer { close_decoded_snapshots(snapshots) }
	history := history_with_snapshots(next, directory, snapshots)!
	defer { close_decoded_history(history) }
	mut template := (os.temp_dir().trim_right('/') + '/vinix-repository-review-XXXXXX').bytes()
	unsafe { template.flags |= .noslices }
	template << u8(0)
	defer { unsafe { template.free() } }
	if C.mkdtemp(&char(template.data)) == unsafe { nil } {
		return error('cannot create a private repository review workspace')
	}
	work := unsafe { cstring_to_vstring(&char(template.data)).clone() }
	defer {
		os.rmdir_all(work) or {}
		unsafe { work.free() }
	}
	snapshot, index := enrollment_snapshot(config, repository, offline, work)!
	defer { close_decoded_index(index); unsafe { snapshot.text.free(); snapshot.signature.free() } }
	digest := index_digest(snapshot.text)
	defer { unsafe { digest.free() } }
	check_floor(history, repository, index, digest)!
	return repository_review(config, history, operation, repository, snapshot.text, index)
}

pub fn review_repository(root string, operation string, repository Repository, offline bool) !pkgprotocol.RepositoryReview {
	directory := state_directory(root)
	defer { unsafe { directory.free() } }
	if state_requires_lock(directory) {
		guard := acquire_reader(directory)!
		defer { guard.release() }
		return read_repository_review(root, operation, repository, offline)
	}
	return read_repository_review(root, operation, repository, offline)
}
