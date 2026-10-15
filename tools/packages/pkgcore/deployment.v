// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import crypto.sha256
import json2
import tools.packages.pkgprotocol

pub struct DeploymentPackage {
pub:
	id               string @[required]
	version          string @[required]
	architecture     string @[required]
	repository       string @[required]
	public_key       string @[required]
	minimum_sequence u64    @[required]
	metadata_sha256  string @[required]
}

pub struct DeploymentLock {
pub:
	format       int = 2
	architecture string
	packages     []string // explicit roots
	locked       []DeploymentPackage // complete dependency/runtime closure
}

struct DeploymentIdentity {
	domain   string = 'vinix-deployment-review-1'
	config   Config
	current  State
	document DeploymentLock
	plan     Plan
	repairs  []string @[omitempty]
}

// Digest every manifest field, including payload hashes, permissions, license,
// runtime entrypoint and launch arguments. Index sequence/expiry are independent.
pub fn package_metadata_digest(p Package) !string {
	canonical := canonical_package(p)!
	defer {
		// Canonicalization owns these four buffers and borrows their fields.
		unsafe {
			(&array(&canonical.files)).free(); (&array(&canonical.dependencies)).free()
			(&array(&canonical.permissions)).free(); (&array(&canonical.associations)).free()
		}
	}
	mut bytes := []u8{cap: 2048}
	unsafe { bytes.flags |= .noslices }
	defer { unsafe { bytes.free() } }
	json2.encode_append(canonical, mut bytes)
	bytes << u8(`\n`)
	mut hash := sha256.new()
	mut sum := []u8{len: sha256.size}
	defer { unsafe { sum.free(); hash.free(); free(hash) } }
	hash.write(bytes)!
	hash.checksum_into(mut sum)
	return sum.hex()
}

fn read_deployment(path string, architecture string) !DeploymentLock {
	text := read_metadata(path)!
	defer { unsafe { text.free() } }
	return decode_deployment(text, architecture)
}

fn decode_deployment(text string, architecture string) !DeploymentLock {
	mut input := pkgprotocol.decode_deployment_document(text)!
	mut accepted := false
	defer { if !accepted { input.close() } }
	document := DeploymentLock{ format: input.format, architecture: input.architecture, packages: input.packages }
	if document.architecture != architecture { return error('deployment architecture mismatch') }
	// Sorting reuses the decoder's owned arrays; copying them would orphan
	// their original buffers. Convert only the wire pin array's element type.
	mut roots := unsafe { document.packages }
	roots.sort()
	for i, id in roots {
		if !identifier(id) || (i > 0 && roots[i - 1] == id) {
			return error('invalid or duplicate deployment root: ${id}')
		}
	}
	mut locked := unsafe { input.locked }
	locked.sort(a.id < b.id)
	for i, pin in locked {
		if !identifier(pin.id) || (i > 0 && locked[i - 1].id == pin.id)
			|| pin.architecture !in [architecture, 'all'] || !identifier(pin.repository)
			|| !digest_valid(pin.public_key) || !digest_valid(pin.metadata_sha256) || pin.minimum_sequence == 0 {
			return error('invalid or duplicate locked deployment package: ${pin.id}')
		}
		validated_version(pin.version)!
	}
	mut pins := []DeploymentPackage{cap: locked.len}
	for pin in locked {
		value := DeploymentPackage{ id: pin.id, version: pin.version, architecture: pin.architecture,
			repository: pin.repository, public_key: pin.public_key, minimum_sequence: pin.minimum_sequence,
			metadata_sha256: pin.metadata_sha256 }
		pointer := unsafe { &value }
		unsafe { pins.push_many(pointer, 1) }
	}
	unsafe { (&array(&input.locked)).free() }
	accepted = true // fields transfer to the returned lock
	return DeploymentLock{ ...document, packages: roots, locked: pins }
}

fn deployment_plan(config Config, directory string, current State, document DeploymentLock) !Plan {
	if document.format == 1 { return operation_plan(config, directory, current, 'deploy', document.packages) }
	catalog := load_catalog(config, directory)!
	mut accepted := false
	defer { if !accepted { close_authenticated_catalog(catalog) } }
	candidates := locked_deployment_candidates(catalog, document)!
	defer { unsafe { (&array(&candidates)).free() } }
	// The normal solver still enforces architecture, organization policy,
	// installed publisher ownership, dependency ranges and runtime entrypoints.
	// It can only select the exact authenticated packages in this document.
	plan := resolve(Catalog{ packages: candidates }, config, current, document.packages, true)!
	if plan.packages.len != document.locked.len {
		unsafe { (&array(&plan.requested)).free(); (&array(&plan.packages)).free() }
		return error('deployment lock includes packages outside the requested dependency closure')
	}
	accepted = true // returned plan manifests borrow the authenticated catalog
	return plan
}

fn deployment_fingerprint(config Config, current State, document DeploymentLock, plan Plan, repairs []string) string {
	text := json2.encode(DeploymentIdentity{ config: config, current: current, document: document, plan: plan, repairs: repairs })
	bytes := text.bytes()
	fingerprint := sha256.sum(bytes).hex()
	unsafe { bytes.free(); text.free() }
	return fingerprint
}

// Without IDs, export the currently requested set, preferring authenticated
// installed versions. Explicit IDs replace that root set rather than extend it.
pub fn (service Service) lock_deployment(names []string) !DeploymentLock {
	directory := service.directory()!
	defer { unsafe { directory.free() } }
	guard := acquire_reader(directory)!
	defer { guard.release() }
	config := service.configuration()!
	defer { close_decoded_configuration(config) }
	current := read_state(directory, config.architecture)!
	defer { if current.generation != 0 { close_decoded_state(current) } }
	roots := if names.len == 0 { current.requested } else { names }
	catalog := load_catalog(config, directory)!
	defer { close_authenticated_catalog(catalog) }
	plan := resolve(catalog, config, current, roots, false)!
	defer { unsafe { (&array(&plan.requested)).free(); (&array(&plan.packages)).free() } }
	return owned_deployment_lock(config.architecture, plan)
}

pub fn (service Service) review_deployment(path string) !pkgprotocol.Review {
	directory := service.directory()!
	guard := acquire_reader(directory)!
	defer { guard.release() }
	config := service.configuration()!
	current := read_state(directory, config.architecture)!
	document := read_deployment(path, config.architecture)!
	plan := deployment_plan(config, directory, current, document)!
	repairs := transaction_repairs(directory, current, plan, 'deploy')
	defer { close_transaction_repairs(repairs) }
	return review_plan(config, directory, current, 'deploy', document.packages, plan, 0, repairs,
		deployment_fingerprint(config, current, document, plan, repairs))
}

fn (service Service) deploy_document(path string, expected string) !State {
	directory := service.directory()!
	guard := acquire(directory)!
	defer { guard.release() }
	config := service.configuration()!
	current := read_state(directory, config.architecture)!
	document := read_deployment(path, config.architecture)!
	plan := deployment_plan(config, directory, current, document)!
	repairs := transaction_repairs(directory, current, plan, 'deploy')
	defer { close_transaction_repairs(repairs) }
	check_review(expected, deployment_fingerprint(config, current, document, plan, repairs))!
	service.progress(pkgprotocol.Progress{ phase: 'resolve' })
	return activate_repair_plan_locked(config, directory, current, plan, 'deploy', repairs, TransactionOptions{ progress: service.progress })
}

pub fn (service Service) deploy(path string) !State {
	return service.deploy_document(path, '')
}

pub fn (service Service) apply_deployment(path string, expected string) !State {
	if !digest_valid(expected) { return error('deployment apply requires a review fingerprint') }
	return service.deploy_document(path, expected)
}
