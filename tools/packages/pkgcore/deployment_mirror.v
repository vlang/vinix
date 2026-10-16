// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import tools.packages.pkgprotocol

fn prepare_deployment_mirror(config Config, directory string, destination string, path string) !PreparedMirror {
	if path == '' || !printable(path, 4096) { return error('deployment mirror requires a valid lock filename') }
	// Read once: the fingerprint, parsed pins and exported bytes must describe
	// the same document even if its external producer replaces the input file.
	text := read_metadata(path)!
	defer { unsafe { text.free() } }
	mut document := decode_deployment(text, config.architecture)!
	defer { document.close() }
	if document.format != 2 || document.packages.len == 0 {
		return error('deployment mirror requires a nonempty format-2 deployment lock')
	}
	catalog := load_catalog(config, directory)!
	mut accepted := false
	defer { if !accepted { close_authenticated_catalog(catalog) } }
	plan := resolve_locked_deployment(config, catalog, State{}, document)!
	defer { unsafe { (&array(&plan.requested)).free(); (&array(&plan.packages)).free() } }
	prepared := prepare_mirror_plan(config, directory, destination, document.packages, plan, path, text)!
	accepted = true
	return PreparedMirror{ ...prepared, catalog: catalog }
}

pub fn (service Service) review_deployment_mirror(destination string, path string) !pkgprotocol.DeploymentMirrorReview {
	directory := service.directory()!
	defer { unsafe { directory.free() } }
	guard := acquire_reader(directory)!
	defer { guard.release() }
	config := service.configuration()!
	defer { close_decoded_configuration(config) }
	mut prepared := prepare_deployment_mirror(config, directory, destination, path)!
	defer { prepared.close() }
	presentation := mirror_review(config, directory, destination, prepared.plan.requested, prepared)!
	mut result := pkgprotocol.DeploymentMirrorReview{
		format: 1, deployment: path.clone(), deployment_sha256: prepared.deployment_sha256.clone(),
		mirror: presentation
	}
	result.validate() or { result.close(); return err }
	return result
}

pub fn (service Service) apply_deployment_mirror(destination string, path string, expected string) ! {
	if !digest_valid(expected) { return error('deployment mirror apply requires a review fingerprint') }
	directory := service.directory()!
	defer { unsafe { directory.free() } }
	guard := acquire(directory)!
	defer { guard.release() }
	config := service.configuration()!; defer { close_decoded_configuration(config) }
	mirror_export(config, directory, destination, [],
		MirrorOptions{ deployment: path, expected_review: expected, progress: service.progress })!
}
