// SPDX-License-Identifier: GPL-2.0-or-later
module pkgprotocol

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

fn repository_url(url string) bool {
	if !printable(url, 4096) || url.contains('?') || url.contains('#') { return false }
	if url.starts_with('https://') { return true }
	if !url.starts_with('file:///') || url.len <= 8 { return false }
	mut start := 8
	for i in 8 .. url.len + 1 {
		if i < url.len && url[i] == `\\` { return false }
		if i == url.len || url[i] == `/` {
			length := i - start
			if length == 0 || (length == 1 && url[start] == `.`)
				|| (length == 2 && url[start] == `.` && url[start + 1] == `.`) {
				return false
			}
			start = i + 1
		}
	}
	return true
}

pub fn validate_repository(id string, url string, public_key string) ! {
	if !identifier(id) {
		return error('Use a lowercase repository ID with letters, digits, dots, hyphens or underscores.')
	}
	if !repository_url(url) {
		return error('Enter an HTTPS URL or an absolute file:// repository path without parent traversal.')
	}
	if !digest(public_key) {
		return error('Enter the 64-character lowercase hexadecimal publisher key obtained through a trusted channel.')
	}
}


pub fn (status &RepositoryStatus) validate() ! {
	if status.format != 1 || status.architecture !in ['aarch64', 'x86_64']
		|| status.repositories.len > 4096 || status.history.len > 4096 {
		return error('unsupported repository status')
	}
	for i, repository in status.repositories {
		validate_repository(repository.id, repository.url, repository.public_key)!
		for j in 0 .. i {
			if status.repositories[j].id == repository.id {
				return error('duplicate repository ID')
			}
		}
	}
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
	if review.format != 1 || review.operation !in ['enroll', 'revoke'] || !digest(review.fingerprint)
		|| review.architecture !in ['aarch64', 'x86_64'] {
		return error('unsupported repository review')
	}
	validate_repository(review.id, review.url, review.public_key)!
	if (review.previous_url == '') != (review.previous_public_key == '')
		|| (review.previous_url != '' && (!repository_url(review.previous_url) || !digest(review.previous_public_key))) {
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

pub fn (mut status RepositoryStatus) close() {
	unsafe {
		status.architecture.free()
		for repository in status.repositories { close_repository(repository) }
		(&array(&status.repositories)).free()
		for floor in status.history { close_repository_floor(floor) }
		(&array(&status.history)).free()
	}
	status = RepositoryStatus{}
}

pub fn (mut review RepositoryReview) close() {
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
	review = RepositoryReview{}
}
