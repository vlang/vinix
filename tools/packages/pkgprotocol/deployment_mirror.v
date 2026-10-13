// SPDX-License-Identifier: GPL-2.0-or-later
module pkgprotocol

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


pub fn (review &DeploymentMirrorReview) validate() ! {
	review.mirror.validate()!
	if review.format != 1 || review.deployment == '' || !printable(review.deployment, 4096)
		|| !digest(review.deployment_sha256) { return error('invalid deployment mirror review') }
}


pub fn (mut review DeploymentMirrorReview) close() {
	unsafe { review.deployment.free(); review.deployment_sha256.free() }
	review.mirror.close()
	review = DeploymentMirrorReview{}
}
