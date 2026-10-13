// SPDX-License-Identifier: GPL-2.0-or-later
module pkgprotocol

import json2

fn test_mirror_protocol_requires_export_rows_and_complete_space_and_destination_fields() {
	valid := MirrorReview{ format: 1, input_destination: '/media/new export', destination: '/media/new export',
		review: Review{ format: 1, operation: 'mirror', names: ['app'], requested: ['app'], architecture: 'aarch64',
			fingerprint: 'a'.repeat(64), rows: [ReviewPackage{ id: 'app', name: 'Application', version: '1.0.0',
				architecture: 'aarch64', kind: 'native', repository: 'trusted', public_key: 'b'.repeat(64),
				license: 'MIT', requested: true, action: 'export' }] } }
	mut decoded := decode_mirror_review(json2.encode(valid))!
	decoded.close()
	decoded.close()
	assert decoded.destination == '' && decoded.review.rows.len == 0
	for bad in [MirrorReview{ ...valid, format: 2 }, MirrorReview{ ...valid, destination: 'relative' },
		MirrorReview{ ...valid, destination: '/media/../elsewhere' },
		MirrorReview{ ...valid, review: Review{ ...valid.review, requested: [], rows: [] } },
		MirrorReview{ ...valid, review: Review{ ...valid.review, names: ['app', 'app'], requested: ['app', 'app'] } },
		MirrorReview{ ...valid, review: Review{ ...valid.review, operation: 'install' } },
		MirrorReview{ ...valid, review: Review{ ...valid.review, rows: [ReviewPackage{ ...valid.review.rows[0], action: 'install' }] } }] {
		mut refused := false
		decode_mirror_review(json2.encode(bad)) or { refused = true }
		assert refused
	}
	mut refused := false
	decode_mirror_review(json2.encode(valid).replace('"cache_needed":0,', '')) or { refused = true }
	assert refused
}
