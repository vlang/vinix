// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import tools.packages.pkgprotocol

fn prepare_deployment_mirror(config Config, directory string, destination string, path string) !PreparedMirror {
	if path == '' || !printable(path, 4096) { return error('deployment mirror requires a valid lock filename') }
	// Read once: the fingerprint, parsed pins and exported bytes must describe
	// the same document even if its external producer replaces the input file.
	text := read_metadata(path)!
	document := decode_deployment(text, config.architecture)!
	if document.format != 2 || document.packages.len == 0 {
		return error('deployment mirror requires a nonempty format-2 deployment lock')
	}
	plan := deployment_plan(config, directory, State{}, document)!
	return prepare_mirror_plan(config, directory, destination, document.packages, plan, path, text)
}

pub fn (service Service) review_deployment_mirror(destination string, path string) !pkgprotocol.DeploymentMirrorReview {
	directory := service.directory()!
	guard := acquire_reader(directory)!
	defer { guard.release() }
	config := service.configuration()!
	prepared := prepare_deployment_mirror(config, directory, destination, path)!
	mut result := pkgprotocol.DeploymentMirrorReview{
		format: 1, deployment: path.clone(), deployment_sha256: prepared.deployment_sha256.clone(),
		mirror: mirror_review(config, directory, destination, prepared.plan.requested, prepared)!
	}
	result.validate() or { result.close(); return err }
	return result
}

pub fn (service Service) apply_deployment_mirror(destination string, path string, expected string) ! {
	if !digest_valid(expected) { return error('deployment mirror apply requires a review fingerprint') }
	directory := service.directory()!
	guard := acquire(directory)!
	defer { guard.release() }
	mirror_export(service.configuration()!, directory, destination, [],
		MirrorOptions{ deployment: path, expected_review: expected, progress: service.progress })!
}
