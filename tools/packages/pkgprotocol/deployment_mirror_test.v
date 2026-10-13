// SPDX-License-Identifier: GPL-2.0-or-later
module pkgprotocol

import json2

fn test_deployment_mirror_protocol_requires_complete_intent_and_closes_nested_ownership() {
	base := Review{ format: 1, operation: 'mirror', names: ['app'], requested: ['app'], architecture: 'aarch64',
		fingerprint: 'a'.repeat(64), rows: [ReviewPackage{ id: 'app', name: 'Application', version: '1.0.0',
			architecture: 'aarch64', kind: 'native', repository: 'trusted', public_key: 'b'.repeat(64),
			license: 'MIT', requested: true, action: 'export' }] }
	valid := DeploymentMirrorReview{ format: 1, deployment: '/etc/company/apps.json', deployment_sha256: 'c'.repeat(64),
		mirror: MirrorReview{ format: 1, input_destination: '/media/new', destination: '/media/new', review: base } }
	mut decoded := decode_deployment_mirror_review(json2.encode(valid))!
	decoded.close()
	decoded.close()
	assert decoded.deployment == '' && decoded.mirror.review.rows.len == 0
	for bad in [DeploymentMirrorReview{ ...valid, format: 2 }, DeploymentMirrorReview{ ...valid, deployment: '' },
		DeploymentMirrorReview{ ...valid, deployment_sha256: 'not a digest' }] {
		mut refused := false
		decode_deployment_mirror_review(json2.encode(bad)) or { refused = true }
		assert refused
	}
	text := json2.encode(valid)
	for missing in [text.replace('"cache_needed":0,', ''), text.replace('"shared_disk":false', '"other":false')] {
		mut refused := false
		decode_deployment_mirror_review(missing) or { refused = true }
		assert refused
	}
}
