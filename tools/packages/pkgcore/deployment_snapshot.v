// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2

// Own the encoding buffer, including growth, until the caller's independent
// string is ready. Saved documents include their LF in the same size check.
fn encode_deployment_lock(document DeploymentLock, newline bool) !string {
	mut bytes := []u8{cap: 2048}
	unsafe { bytes.flags |= .noslices }
	defer { unsafe { bytes.free() } }
	json2.encode_append(document, mut bytes)
	if newline { bytes << u8(`\n`) }
	if bytes.len > max_metadata { return error('deployment snapshot exceeds metadata limit') }
	return bytes.bytestr()
}

// The returned document owns every presentation field independently of its
// source state/catalog. No payload, configuration or repository is exported.
fn owned_deployment_lock(architecture string, plan Plan) !DeploymentLock {
	owned_architecture := architecture.clone()
	mut roots := review_strings(plan.requested)
	mut locked := []DeploymentPackage{cap: plan.packages.len}
	mut accepted := false
	defer { if !accepted { mut partial := DeploymentLock{ architecture: owned_architecture, packages: roots, locked: locked }; partial.close() } }
	for installed in plan.packages {
		p := installed.package
		digest := package_metadata_digest(p)!
		locked << DeploymentPackage{ id: p.id.clone(), version: p.version.clone(), architecture: p.architecture.clone(),
			repository: installed.repository.clone(), public_key: installed.public_key.clone(),
			minimum_sequence: installed.sequence, metadata_sha256: digest }
	}
	roots.sort()
	locked.sort(a.id < b.id)
	document := DeploymentLock{ architecture: owned_architecture, packages: roots, locked: locked }
	text := encode_deployment_lock(document, false)!
	defer { unsafe { text.free() } }
	accepted = true
	return document
}

fn installed_deployment_plan(current State, names []string) !Plan {
	if names.len > 4096 { return error('deployment snapshot supports at most 4096 roots') }
	mut roots := review_strings(if names.len == 0 { current.requested } else { names })
	mut accepted := false
	defer { if !accepted { for id in roots { unsafe { id.free() } }; unsafe { (&array(&roots)).free() } } }
	roots.sort()
	mut positions := map[string]int{}
	mut reached := map[string]bool{}
	mut pending := []string{cap: current.packages.len}
	mut selected := []Installed{cap: current.packages.len}
	unsafe { pending.flags |= .noslices }
	defer { unsafe { positions.free(); reached.free(); pending.free() } }
	defer { if !accepted { unsafe { (&array(&selected)).free() } } }
	for index, installed in current.packages { positions[installed.package.id] = index }
	for index, id in roots {
		if !identifier(id) || (index > 0 && roots[index - 1] == id) { return error('invalid or duplicate deployment snapshot root: ${id}') }
		if id !in positions { return error('${id}: deployment snapshot root is not installed') }
		reached[id] = true
		pending << id
	}
	mut next := 0
	for next < pending.len {
		id := pending[next]; next++
		installed := current.packages[positions[id]]
		// This temporary plan borrows the decoded state until its caller builds
		// an independently owned lock. A normal push deep-clones manifests.
		pointer := unsafe { &installed }
		unsafe { selected.push_many(pointer, 1) }
		for dependency in installed.package.dependencies {
			if dependency.id in reached { continue }
			reached[dependency.id] = true
			pending << dependency.id
		}
	}
	selected.sort(a.package.id < b.package.id)
	accepted = true
	return Plan{ requested: roots, packages: selected }
}

fn snapshot_deployment_locked(service Service, directory string, names []string) !DeploymentLock {
	config := service.configuration()!
	defer { close_decoded_configuration(config) }
	current := read_state(directory, config.architecture)!
	defer { if current.generation != 0 { close_decoded_state(current) } }
	plan := installed_deployment_plan(current, names)!
	defer {
		unsafe { for id in plan.requested { id.free() }; (&array(&plan.requested)).free(); (&array(&plan.packages)).free() }
	}
	return owned_deployment_lock(config.architecture, plan)
}

// Unlike lock_deployment, this read-only operation cannot select catalog
// replacements. Recorded provenance is historical; apply still authenticates
// exact manifests and checks current policy through deployment_plan.
pub fn (service Service) snapshot_deployment(names []string) !DeploymentLock {
	directory := service.directory()!
	defer { unsafe { directory.free() } }
	if state_requires_lock(directory) {
		guard := acquire_reader(directory)!
		defer { guard.release() }
		return snapshot_deployment_locked(service, directory, names)
	}
	return snapshot_deployment_locked(service, directory, names)
}

pub fn (mut document DeploymentLock) close() {
	unsafe {
		document.architecture.free()
		for id in document.packages { id.free() }
		(&array(&document.packages)).free()
		for item in document.locked {
			item.id.free(); item.version.free(); item.architecture.free(); item.repository.free(); item.public_key.free(); item.metadata_sha256.free()
		}
		(&array(&document.locked)).free()
	}
	document = DeploymentLock{}
}
