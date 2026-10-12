// SPDX-License-Identifier: GPL-2.0-or-later
module pkgprotocol

import json2

fn repository_protocol_review() RepositoryReview {
	return RepositoryReview{
		format:              1
		operation:           'enroll'
		architecture:        'aarch64'
		id:                  'fixture'
		url:                 'file:///media/repository with spaces; $literal'
		public_key:          'a'.repeat(64)
		fingerprint:         'b'.repeat(64)
		index_sha256:        'c'.repeat(64)
		sequence:            2
		expires:             2000000000
		package_count:       17
		remembered_sequence: 1
	}
}

fn test_repository_review_validates_complete_intent_and_closes_owned_fields() {
	valid := repository_protocol_review()
	mut decoded := decode_repository_review(json2.encode(valid))!
	assert decoded.id == valid.id && decoded.url == valid.url && decoded.sequence == 2
	decoded.close()
	assert decoded.id == '' && decoded.fingerprint == '' && decoded.architecture == ''
	for bad in [RepositoryReview{ ...valid, format: 2 },
		RepositoryReview{ ...valid, architecture: 'i386' },
		RepositoryReview{ ...valid, operation: 'run' },
		RepositoryReview{ ...valid, fingerprint: 'missing' },
		RepositoryReview{ ...valid, index_sha256: '' }, RepositoryReview{ ...valid, sequence: 0 },
		RepositoryReview{ ...valid, sequence: 1, remembered_sequence: 2 },
		RepositoryReview{ ...valid, expires: 0 }, RepositoryReview{ ...valid, package_count: 4097 },
		RepositoryReview{ ...valid, previous_url: 'https://example.invalid' },
		RepositoryReview{ ...valid, operation: 'revoke' }] {
		if _ := decode_repository_review(json2.encode(bad)) {
			assert false
		}
	}
	revocation := RepositoryReview{
		format:              1
		operation:           'revoke'
		architecture:        'x86_64'
		id:                  valid.id
		url:                 valid.url
		public_key:          valid.public_key
		previous_url:        valid.url
		previous_public_key: valid.public_key
		fingerprint:         valid.fingerprint
	}
	mut revoke := decode_repository_review(json2.encode(revocation))!
	revoke.close()
	if _ := decode_repository_review(json2.encode(RepositoryReview{ ...revocation, previous_public_key: 'd'.repeat(64) })) {
		assert false
	}
}

fn test_repository_status_bounds_and_identity_validation() {
	repository := Repository{ id: 'fixture', url: 'https://example.invalid/catalog', public_key: 'a'.repeat(64) }
	floor := RepositoryFloor{ id: repository.id, public_key: repository.public_key, sequence: 7, index_sha256: 'b'.repeat(64) }
	valid := RepositoryStatus{ format: 1, architecture: 'aarch64', repositories: [repository], history: [floor] }
	mut decoded := decode_repositories(json2.encode(valid))!
	assert decoded.repositories.len == 1 && decoded.history[0].sequence == 7
	decoded.close()
	assert decoded.repositories.len == 0 && decoded.history.len == 0 && decoded.architecture == ''
	for bad in [RepositoryStatus{ ...valid, format: 0 },
		RepositoryStatus{ ...valid, architecture: 'arm' },
		RepositoryStatus{ ...valid, repositories: [repository, repository] },
		RepositoryStatus{ ...valid, history: [floor, floor] },
		RepositoryStatus{ ...valid, history: [RepositoryFloor{ ...floor, sequence: 0 }] }] {
		if _ := decode_repositories(json2.encode(bad)) {
			assert false
		}
	}
	for url in ['http://example.invalid', 'file://relative', 'file:///a/../b', 'file:///a//b',
		'file:///a/', 'file:///a\\b', 'https://example.invalid?key=x'] {
		if _ := validate_repository(repository.id, url, repository.public_key) {
			assert false
		}
	}
	if _ := validate_repository('bad;command', repository.url, repository.public_key) {
		assert false
	}
	if _ := validate_repository(repository.id, repository.url, 'A'.repeat(64)) {
		assert false
	}
}
