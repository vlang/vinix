// SPDX-License-Identifier: GPL-2.0-or-later
module pkgprotocol

import json2

// Repository identifiers start with lowercase ASCII; this reserved filename
// cannot collide with a repository directory in the exported root.
pub const deployment_mirror_filename = '_deployment.json'

pub struct DeploymentMirrorReview {
pub:
	format int
	deployment string
	deployment_sha256 string
	mirror MirrorReview
}

struct DeploymentMirrorInput {
	format int @[required]
	deployment string @[required]
	deployment_sha256 string @[required]
	mirror MirrorReviewInput @[required]
}

pub fn (review &DeploymentMirrorReview) validate() ! {
	review.mirror.validate()!
	if review.format != 1 || review.deployment == '' || !printable(review.deployment, 4096)
		|| !digest(review.deployment_sha256) { return error('invalid deployment mirror review') }
}

pub fn decode_deployment_mirror_review(text string) !DeploymentMirrorReview {
	if text.len > 8 * 1024 * 1024 { return error('deployment mirror review exceeds metadata limit') }
	input := json2.decode[DeploymentMirrorInput](text, strict: true)!
	mut result := DeploymentMirrorReview{ format: input.format, deployment: input.deployment,
		deployment_sha256: input.deployment_sha256,
		mirror: MirrorReview{ format: input.mirror.format, input_destination: input.mirror.input_destination,
			destination: input.mirror.destination, review: input.mirror.review, cache_needed: input.mirror.cache_needed,
			cache_available: input.mirror.cache_available, shared_disk: input.mirror.shared_disk } }
	result.validate() or { result.close(); return err }
	return result
}

pub fn (mut review DeploymentMirrorReview) close() {
	unsafe { review.deployment.free(); review.deployment_sha256.free() }
	review.mirror.close()
	review = DeploymentMirrorReview{}
}
