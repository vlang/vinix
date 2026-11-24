// SPDX-License-Identifier: GPL-2.0-or-later
module pkgprotocol

import crypto.sha256

const repository_refresh_domain = 'vinix-package repository refresh 1'

pub struct Repository {
pub:
	id         string
	url        string
	public_key string
}

pub struct RepositoryFloor {
pub:
	id           string
	public_key   string
	sequence     u64
	index_sha256 string
}

pub struct RepositoryStatus {
pub:
	format       int
	architecture string
	repositories []Repository
	history      []RepositoryFloor
}

pub struct RepositoryReview {
pub:
	format              int
	operation           string // enroll or revoke
	architecture        string
	id                  string
	url                 string
	public_key          string
	previous_url        string
	previous_public_key string
	fingerprint         string
	index_sha256        string
	sequence            u64
	expires             i64
	package_count       int
	remembered_sequence u64
}

pub fn validate_repository(id string, url string, public_key string) ! {
	if !identifier(id) {
		return error('Use a lowercase repository ID with letters, digits, dots, hyphens or underscores.')
	}
	if !valid_repository_url(url) {
		return error('Enter an HTTPS URL or an absolute file:// repository path without parent traversal.')
	}
	if !digest(public_key) {
		return error('Enter the 64-character lowercase hexadecimal publisher key obtained through a trusted channel.')
	}
}

// Hash the literal fields of a validated repository. Validated fields exclude
// newlines, so each is delimited without normalizing the URL or key.
pub fn repository_refresh_fingerprint(repository Repository) string {
	mut bytes := []u8{cap: repository_refresh_domain.len + repository.id.len + repository.url.len + repository.public_key.len + 4}
	defer { unsafe { bytes.free() } }
	for part in [repository_refresh_domain, repository.id, repository.url, repository.public_key]! {
		for byte in part { bytes << byte }
		bytes << `\n`
	}
	mut hash := sha256.new()
	mut digest := []u8{len: sha256.size}
	defer { unsafe { hash.free(); free(hash); digest.free() } }
	hash.write(bytes) or { panic(err) }
	hash.checksum_into(mut digest)
	return digest.hex()
}


fn validate_configured_repositories(format int, architecture string, repositories []Repository) ! {
	if format != 1 || architecture !in ['aarch64', 'x86_64'] || repositories.len > 4096 {
		return error('unsupported repository status')
	}
	for i, repository in repositories {
		validate_repository(repository.id, repository.url, repository.public_key)!
		for j in 0 .. i {
			if repositories[j].id == repository.id {
				return error('duplicate repository ID')
			}
		}
	}
}

pub fn (status &RepositoryStatus) validate() ! {
	validate_repository_status(status)!
}

fn validate_repository_status(status RepositoryStatus) ! {
	validate_configured_repositories(status.format, status.architecture, status.repositories)!
	if status.history.len > 4096 { return error('unsupported repository status') }
	for i, floor in status.history {
		if !identifier(floor.id) || !digest(floor.public_key) || !digest(floor.index_sha256)
			|| floor.sequence == 0 {
			return error('invalid repository history')
		}
		for j in 0 .. i {
			if status.history[j].id == floor.id && status.history[j].public_key == floor.public_key {
				return error('duplicate repository history identity')
			}
		}
	}
}


pub fn (review &RepositoryReview) validate() ! {
	validate_repository_review(review)!
}

fn validate_repository_review(review RepositoryReview) ! {
	if review.format != 1 || review.operation !in ['enroll', 'revoke'] || !digest(review.fingerprint)
		|| review.architecture !in ['aarch64', 'x86_64'] {
		return error('unsupported repository review')
	}
	validate_repository(review.id, review.url, review.public_key)!
	if (review.previous_url == '') != (review.previous_public_key == '')
		|| (review.previous_url != '' && (!valid_repository_url(review.previous_url) || !digest(review.previous_public_key))) {
		return error('invalid previous repository identity')
	}
	if review.operation == 'enroll' {
		if !digest(review.index_sha256) || review.sequence == 0 || review.sequence < review.remembered_sequence
			|| review.expires <= 0 || review.package_count < 0 || review.package_count > 4096 {
			return error('incomplete authenticated enrollment review')
		}
	} else if review.index_sha256 != '' || review.sequence != 0 || review.expires != 0
		|| review.package_count != 0 || review.remembered_sequence != 0
		|| review.previous_url != review.url || review.previous_public_key != review.public_key {
		return error('invalid revocation review')
	}
}

fn close_repository(repository Repository) {
	unsafe { repository.id.free(); repository.url.free(); repository.public_key.free() }
}

fn close_repository_floor(floor RepositoryFloor) {
	unsafe { floor.id.free(); floor.public_key.free(); floor.index_sha256.free() }
}

fn close_repositories(repositories []Repository) {
	for repository in repositories { close_repository(repository) }
	unsafe { repositories.free() }
}

fn close_repository_floors(floors []RepositoryFloor) {
	for floor in floors { close_repository_floor(floor) }
	unsafe { floors.free() }
}

fn close_repository_status(status RepositoryStatus) {
	unsafe { status.architecture.free() }
	close_repositories(status.repositories)
	close_repository_floors(status.history)
}

pub fn (mut status RepositoryStatus) close() {
	close_repository_status(status)
	status = RepositoryStatus{}
}

fn close_repository_review(review RepositoryReview) {
	unsafe {
		review.operation.free()
		review.architecture.free()
		review.id.free()
		review.url.free()
		review.public_key.free()
		review.previous_url.free()
		review.previous_public_key.free()
		review.fingerprint.free()
		review.index_sha256.free()
	}
}

pub fn (mut review RepositoryReview) close() {
	close_repository_review(review)
	review = RepositoryReview{}
}
