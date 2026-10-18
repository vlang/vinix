// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import tools.packages.pkgprotocol

// SDK 1 image-input report. This describes the selected trust/policy and the
// complete authenticated bundle, without initializing consumer package state.
struct ImageBundleCheck {
	id string
	sequence u64
	expires i64
	index_sha256 string
	packages int
	aarch64_packages int
	x86_64_packages int
	shared_packages int
	proprietary_packages int
	firmware_packages int
	objects int
	payload_bytes u64
}

struct ImageInputCheck {
	format int = 1
	architecture string
	root string
	configuration_path string
	configuration_action string
	configuration_sha256 string
	configuration Config
	bundle_supplied bool
	bundle_action string
	bundle_required_bytes u64
	bundle_reserve_bytes u64
	bundled_repositories []ImageBundleCheck
	applications_checked bool
	application_requirements_sha256 string
	application_deployment DeploymentLock
	application_deployment_destination string
	application_deployment_sha256 string
	image_application_deployment_path string
	image_application_deployment_action string
	image_application_deployment_sha256 string
	image_application_deployment_bytes u64
}

// Return owned, newline-terminated JSON. Callers close both input plans and
// free the returned text. Report encoding borrows decoded/plan fields only
// while their owners are alive; no private capture paths enter the report.
pub fn (configuration &ImageConfiguration) check_repositories(repositories &ImageRepositories) !string {
	return configuration.check_inputs(repositories, [], '', ImageDeploymentOutput{})
}

// Check an advertised application set together, using only the captured signed
// bundle. The independent format-2 lock in the report can be saved and reviewed
// through the ordinary deployment workflow after installation. This does not
// install packages, enroll remote publishers or authorize a deployment.
pub fn (configuration &ImageConfiguration) check_applications(repositories &ImageRepositories, required []string) !string {
	if required.len == 0 { return error('image application check requires at least one application ID') }
	return configuration.check_inputs(repositories, required, '', ImageDeploymentOutput{})
}

// Format-1 deployment roots are a declarative advertised application set.
// Format-2 locks must never be reduced to IDs, discarding their exact pins.
// Capture once: resolution and the reported digest refer to the same bytes.
pub fn (configuration &ImageConfiguration) check_application_file(repositories &ImageRepositories, source string) !string {
	return configuration.check_application_source(repositories, source, ImageDeploymentOutput{})
}

fn (configuration &ImageConfiguration) check_application_source(repositories &ImageRepositories, source string, output ImageDeploymentOutput) !string {
	mut plan := configuration.plan_application_source(repositories, source, output)!
	defer { plan.close() }
	return unsafe { &plan }.report()
}

fn (configuration &ImageConfiguration) plan_application_source(repositories &ImageRepositories, source string, output ImageDeploymentOutput) !ImageApplications {
	text := read_metadata(source)!
	defer { unsafe { text.free() } }
	mut document := decode_deployment(text, configuration.architecture)!
	defer { document.close() }
	if document.format != 1 { return error('image application requirements need a format-1 root manifest; exact format-2 deployment locks cannot be used as unpinned requirements') }
	if document.packages.len == 0 { return error('image application requirements must name at least one application') }
	digest := index_digest(text)
	defer { unsafe { digest.free() } }
	return configuration.plan_inputs(repositories, document.packages, digest, output)
}

fn (configuration &ImageConfiguration) check_inputs(repositories &ImageRepositories, required []string, requirements_sha256 string, output ImageDeploymentOutput) !string {
	mut plan := configuration.plan_inputs(repositories, required, requirements_sha256, output)!
	defer { plan.close() }
	return unsafe { &plan }.report()
}

fn (configuration &ImageConfiguration) plan_inputs(repositories &ImageRepositories, required []string, requirements_sha256 string, output ImageDeploymentOutput) !ImageApplications {
	if output.destination != '' && required.len == 0 { return error('image deployment export requires selected application requirements') }
	if required.len > 4096 { return error('image application check supports at most 4096 application IDs') }
	mut seen := map[string]bool{}
	defer { unsafe { seen.free() } }
	for id in required {
		if !identifier(id) || id in seen { return error('invalid or duplicate required image application: ${id}') }
		seen[id] = true
	}
	if configuration.root == '' || !image_configuration_root_matches(configuration.root, configuration.device, configuration.inode) {
		return error('package image root changed before input check')
	}
	image_configuration_parents(configuration.root)!
	if configuration.existing { image_configuration_architecture(configuration.root, configuration.architecture)! }
	else {
		if image_configuration_exists(configuration.path)! { return error('image package configuration appeared after preparation; prepare inputs again') }
		image_configuration_fresh_state(configuration.root)!
	}
	text := if configuration.existing { read_metadata(configuration.path)! } else { configuration.text.clone() }
	defer { unsafe { text.free() } }
	config := decode_configuration(text)!
	defer { close_decoded_configuration(config) }
	if config.architecture != configuration.architecture { return error('image input check configuration targets another architecture') }
	mut bundle_action := 'none'
	if repositories.capture != '' {
		if repositories.root != configuration.root || repositories.architecture != configuration.architecture || repositories.configuration != text {
			return error('image input check requires repositories captured for this configuration')
		}
		repositories.current()!
		repositories.verify(repositories.capture, 0o700)!
		parent := image_repositories_parents(configuration.root)!
		unsafe { parent.free() }
		target := configuration.root + image_repositories_path
		defer { unsafe { target.free() } }
		if image_configuration_exists(target)! { repositories.verify(target, 0o755)!; bundle_action = 'preserve' }
		else { bundle_action = 'publish' }
	}
	mut deployment := if required.len > 0 { image_application_deployment(config, repositories, required)! }
		else { DeploymentLock{ architecture: config.architecture.clone() } }
	defer { deployment.close() }
	mut rows := []ImageBundleCheck{cap: repositories.repositories.len}
	defer {
		for row in rows { unsafe { row.index_sha256.free() } }
		unsafe { (&array(&rows)).free() }
	}
	for repository in repositories.repositories {
		objects := image_repository_objects(repository.index)!
		defer { unsafe { objects.free() } }
		mut bytes := u64(0)
		for _, payload in objects { bytes += payload.bytes }
		mut arm := 0; mut x86 := 0; mut shared := 0; mut proprietary := 0; mut firmware := 0
		for p in repository.index.packages {
			if p.architecture == 'aarch64' { arm++ } else if p.architecture == 'x86_64' { x86++ } else { shared++ }
			if p.proprietary { proprietary++ }; if p.firmware { firmware++ }
		}
		row := ImageBundleCheck{ id: repository.id, sequence: repository.index.sequence, expires: repository.index.expires,
			index_sha256: index_digest(repository.text), packages: repository.index.packages.len,
			aarch64_packages: arm, x86_64_packages: x86, shared_packages: shared, proprietary_packages: proprietary,
			firmware_packages: firmware, objects: objects.len, payload_bytes: bytes }
		unsafe { rows.push_many(&row, 1) }
	}
	rows.sort(a.id < b.id)
	digest := index_digest(text)
	defer { unsafe { digest.free() } }
	target := if output.destination != '' { image_deployment_target(configuration.root, output.destination)! } else { '' }
	defer { unsafe { target.free() } }
	lock_text := if required.len > 0 { encode_deployment_lock(deployment, true)! } else { '' }
	defer { unsafe { lock_text.free() } }
	lock_digest := if lock_text != '' { index_digest(lock_text) } else { '' }
	defer { unsafe { lock_digest.free() } }
	image_action := image_applications_action(configuration.root, lock_text)!
	report := publisher_json(ImageInputCheck{ architecture: configuration.architecture, root: configuration.root,
		configuration_path: configuration.path, configuration_action: if configuration.existing { 'preserve' } else { 'initialize' },
		configuration_sha256: digest, configuration: config, bundle_supplied: repositories.capture != '', bundle_action: bundle_action,
		bundle_required_bytes: repositories.needed, bundle_reserve_bytes: if repositories.capture != '' { u64(64 * 1024 * 1024) } else { 0 },
		bundled_repositories: rows, applications_checked: required.len > 0,
		application_requirements_sha256: requirements_sha256, application_deployment: deployment,
		application_deployment_destination: target, application_deployment_sha256: if target != '' { lock_digest } else { '' },
		image_application_deployment_path: if lock_text != '' { pkgprotocol.image_applications_path } else { '' },
		image_application_deployment_action: image_action, image_application_deployment_sha256: lock_digest,
		image_application_deployment_bytes: u64(lock_text.len) })
	mut accepted := false
	defer { if !accepted { unsafe { report.free() } } }
	if target != '' { atomic_write_with(target, lock_text, AtomicWriteOptions{ ...output.options, exclusive: true })! }
	accepted = true
	return ImageApplications{ root: if required.len > 0 { configuration.root.clone() } else { '' },
		architecture: configuration.architecture.clone(), configuration: text.clone(),
		device: configuration.device, inode: configuration.inode, text: lock_text.clone(), report_text: report }
}
