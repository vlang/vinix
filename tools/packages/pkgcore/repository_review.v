// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import crypto.sha256
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
	text := json2.encode(RepositoryReviewIdentity{
		config:       config
		history:      history
		operation:    operation
		repository:   repository
		index_sha256: digest
	})
	bytes := text.bytes()
	fingerprint := sha256.sum(bytes).hex()
	unsafe {
		bytes.free()
		text.free()
	}
	return fingerprint
}

fn check_repository_review(expected string, actual string) ! {
	if expected != '' && (!digest_valid(expected) || expected != actual) {
		return error('repository review is stale: trust configuration, sequence history or signed metadata changed; review again')
	}
}

fn enrollment_configuration(current Config, repository Repository) !Config {
	mut repositories := current.repositories.filter(it.id != repository.id)
	repositories << repository
	repositories.sort(a.id < b.id)
	next := Config{ ...current, repositories: repositories }
	next.validate()!
	key := admitted_publisher_key(repository.public_key)!
	unsafe { key.free() }
	return next
}

fn enrollment_snapshot(config Config, repository Repository, offline bool, work string) !(Snapshot, Index) {
	fetch(repository.url.trim_right('/') + '/index.json', work + '/index.json', max_metadata, false,
		config.policy.offline || offline)!
	fetch(repository.url.trim_right('/') + '/index.sig', work + '/index.sig', 256, false,
		config.policy.offline || offline)!
	text := read_metadata(work + '/index.json')!
	signature := read_metadata(work + '/index.sig')!
	index := verify_index(repository, text, signature, time.now().unix())!
	return Snapshot{ repository: repository, text: text, signature: signature }, index
}

fn repository_review(config Config, history TrustHistory, operation string, repository Repository, text string, index Index) !pkgprotocol.RepositoryReview {
	previous := config.repositories.filter(it.id == repository.id)
	digest := if operation == 'enroll' { index_digest(text) } else { '' }
	mut remembered := u64(0)
	for floor in history.repositories {
		if floor.id == repository.id && floor.public_key == repository.public_key {
			remembered = floor.sequence
		}
	}
	review := pkgprotocol.RepositoryReview{
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
	review.validate()!
	return review
}

fn read_repository_review(root string, operation string, repository Repository, offline bool) !pkgprotocol.RepositoryReview {
	config := load_config(root)!
	if operation == 'revoke' {
		matches := config.repositories.filter(it.id == repository.id)
		if matches.len != 1 { return error('repository is not enrolled: ${repository.id}') }
		// Revocation never needs a readable catalog/history or a reachable publisher.
		return repository_review(config, TrustHistory{}, operation, matches[0], '', Index{})
	}
	if operation != 'enroll' { return error('unknown repository operation') }
	next := enrollment_configuration(config, repository)!
	directory := state_directory(root)
	history := history_with_snapshots(next, directory, read_snapshots(directory)!)!
	mut template := (os.temp_dir().trim_right('/') + '/vinix-repository-review-XXXXXX').bytes()
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
	check_floor(history, repository, index, index_digest(snapshot.text))!
	return repository_review(config, history, operation, repository, snapshot.text, index)
}

pub fn review_repository(root string, operation string, repository Repository, offline bool) !pkgprotocol.RepositoryReview {
	directory := state_directory(root)
	if state_requires_lock(directory) {
		guard := acquire_reader(directory)!
		defer { guard.release() }
		return read_repository_review(root, operation, repository, offline)
	}
	return read_repository_review(root, operation, repository, offline)
}
