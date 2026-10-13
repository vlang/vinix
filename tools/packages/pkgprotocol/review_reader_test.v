// SPDX-License-Identifier: GPL-2.0-or-later
module pkgprotocol

import json2

fn complete_review_fixture(operation string) Review {
	return Review{ format: 1, operation: operation, names: ['app'], requested: ['app'], architecture: 'aarch64',
		fingerprint: 'a'.repeat(64), rows: [ReviewPackage{ id: 'app', name: 'Application é🚀', description: 'A complete description',
			version: '1.0.0', architecture: 'aarch64', kind: 'native', repository: 'trusted', public_key: 'b'.repeat(64),
			license: 'MIT', requested: true, action: if operation == 'mirror' { 'export' } else { 'install' } }] }
}

fn complete_repository_fixture() RepositoryReview {
	return RepositoryReview{ format: 1, operation: 'enroll', architecture: 'aarch64', id: 'trusted',
		url: 'https://example.invalid/catalog', public_key: 'b'.repeat(64), fingerprint: 'a'.repeat(64),
		index_sha256: 'c'.repeat(64), sequence: 7, expires: 2000000000, package_count: 1, remembered_sequence: 6 }
}

fn complete_status_fixture() RepositoryStatus {
	return RepositoryStatus{ format: 1, architecture: 'x86_64', repositories: [Repository{
		id: 'trusted', url: 'https://example.invalid/catalog', public_key: 'b'.repeat(64) }],
		history: [RepositoryFloor{ id: 'trusted', public_key: 'b'.repeat(64), sequence: 7, index_sha256: 'c'.repeat(64) }] }
}

fn complete_mirror_fixture() MirrorReview {
	return MirrorReview{ format: 1, input_destination: '/media/new é; $literal', destination: '/media/new é; $literal',
		review: complete_review_fixture('mirror'), cache_needed: 512, cache_available: 8192 }
}

fn complete_locked_fixture() DeploymentMirrorReview {
	return DeploymentMirrorReview{ format: 1, deployment: '/company/apps.json', deployment_sha256: 'd'.repeat(64), mirror: complete_mirror_fixture() }
}

fn accepts_metadata(kind int, text string) bool {
	match kind {
		0 { mut value := decode_review(text) or { unsafe { err.free() }; return false }; value.close() }
		1 { mut value := decode_repositories(text) or { unsafe { err.free() }; return false }; value.close() }
		2 { mut value := decode_repository_review(text) or { unsafe { err.free() }; return false }; value.close() }
		3 { mut value := decode_mirror_review(text) or { unsafe { err.free() }; return false }; value.close() }
		4 { mut value := decode_deployment_mirror_review(text) or { unsafe { err.free() }; return false }; value.close() }
		else { panic('unsupported test decoder') }
	}
	return true
}

fn assert_all_fields_required(kind int, object string, prefix string, suffix string) ! {
	fields := json2.decode[json2.Any](object)!.as_map()
	for key, _ in fields {
		mut missing := fields.clone(); missing.delete(key)
		assert !accepts_metadata(kind, prefix + json2.encode(missing) + suffix), key
		mut nulled := fields.clone(); nulled[key] = json2.Null{}
		assert !accepts_metadata(kind, prefix + json2.encode(nulled) + suffix), key
	}
	assert accepts_metadata(kind, prefix + object + suffix)
	assert !accepts_metadata(kind, prefix + '{"unknown":true,' + object[1..] + suffix)
}

fn test_all_review_fields_are_required_with_explicit_json_types_at_every_level() {
	texts := [json2.encode(complete_review_fixture('install')), json2.encode(complete_status_fixture()),
		json2.encode(complete_repository_fixture()), json2.encode(complete_mirror_fixture()), json2.encode(complete_locked_fixture())]
	for kind, text in texts { assert_all_fields_required(kind, text, '', '')! }
	row := json2.encode(complete_review_fixture('install').rows[0])
	position := texts[0].index(row) or { panic('row absent from fixture') }
	assert_all_fields_required(0, row, texts[0][..position], texts[0][position + row.len..])!
	for object in [json2.encode(complete_status_fixture().repositories[0]), json2.encode(complete_status_fixture().history[0])] {
		at := texts[1].index(object) or { panic('identity absent from fixture') }
		assert_all_fields_required(1, object, texts[1][..at], texts[1][at + object.len..])!
	}
	inner := json2.encode(complete_review_fixture('mirror'))
	for kind in [3, 4] {
		at := texts[kind].index(inner) or { panic('review absent from fixture') }
		assert_all_fields_required(kind, inner, texts[kind][..at], texts[kind][at + inner.len..])!
		inner_row := json2.encode(complete_review_fixture('mirror').rows[0])
		row_at := texts[kind].index(inner_row) or { panic('export row absent from fixture') }
		assert_all_fields_required(kind, inner_row, texts[kind][..row_at], texts[kind][row_at + inner_row.len..])!
	}
	mirror := texts[3]
	at := texts[4].index(mirror) or { panic('mirror absent from fixture') }
	assert_all_fields_required(4, mirror, texts[4][..at], texts[4][at + mirror.len..])!
}

fn test_reviews_reject_escaped_duplicates_coercion_overflow_and_malformed_unicode() {
	text := json2.encode(complete_review_fixture('install'))
	for bad in [text.replace('"format":1', '"format":1,"fo\\u0072mat":1'),
		text.replace('"firmware":false', '"firmware":true,"firm\\u0077are":false'),
		text.replace('"proprietary":false', '"proprietary":"false"'), text.replace('"requested":true', '"requested":1'),
		text.replace('"generation":0', '"generation":18446744073709551616'), text.replace('"generation":0', '"generation":-1'),
		text.replace('"disk_needed":0', '"disk_needed":01'), text.replace('"disk_needed":0', '"disk_needed":1e2'),
		text.replace('Application é🚀', '\\ud800'), text.replace('Application é🚀', '\xff'), text + ' trailing',
		text.replace('"permissions":[]', '"permissions":[false]')] { assert !accepts_metadata(0, bad) }
	mut decoded := decode_review(text.replace('Application é🚀', 'Application \\u00e9\\ud83d\\ude80'))!
	assert decoded.rows[0].name == 'Application é🚀'; decoded.close()
	repository := json2.encode(complete_repository_fixture())
	for bad in [repository.replace('"expires":2000000000', '"expires":9223372036854775808'),
		repository.replace('"package_count":1', '"package_count":4097'), repository.replace('"remembered_sequence":6', '"remembered_sequence":6.0'),
		repository.replace('"remembered_sequence":6', '"remembered_sequence":6,"remembered_sequ\\u0065nce":6'),
		repository.replace('"sequence":7', '"sequence":"7"')] { assert !accepts_metadata(2, bad) }
	maximum := text.replace('"generation":0', '"generation":18446744073709551615')
	mut huge_generation := decode_review(maximum)!
	assert huge_generation.generation == ~u64(0); huge_generation.close()
}

fn test_review_bounds_are_checked_during_collection_and_scalar_decoding() {
	base := complete_review_fixture('install')
	mut rows := []ReviewPackage{cap: 8193}
	for index in 0 .. 8193 {
		digits := index.str()
		rows << ReviewPackage{ ...base.rows[0], id: 'app-' + '0000'[..4 - digits.len] + digits, requested: index == 0 }
	}
	wide := Review{ ...base, names: ['app-0000'], requested: ['app-0000'], rows: rows }
	assert !accepts_metadata(0, json2.encode(wide))
	assert accepts_metadata(0, json2.encode(Review{ ...wide, rows: rows[..8192] }))
	mut names := []string{cap: 4097}
	for index in 0 .. 4097 { names << 'app-' + index.str() }
	assert !accepts_metadata(0, json2.encode(Review{ ...base, names: names }))
	assert !accepts_metadata(0, json2.encode(Review{ ...base, rows: [ReviewPackage{ ...base.rows[0], description: 'x'.repeat(4097) }] }))
	assert !accepts_metadata(0, json2.encode(Review{ ...base, rows: [ReviewPackage{ ...base.rows[0], permissions: ['audio', 'display', 'files', 'network', 'process', 'files'] }] }))
	mut repositories := []Repository{cap: 4097}
	for index in 0 .. 4097 { repositories << Repository{ ...complete_status_fixture().repositories[0], id: 'publisher-' + index.str() } }
	assert !accepts_metadata(1, json2.encode(RepositoryStatus{ ...complete_status_fixture(), repositories: repositories }))
	assert accepts_metadata(1, json2.encode(RepositoryStatus{ ...complete_status_fixture(), repositories: repositories[..4096] }))
}
