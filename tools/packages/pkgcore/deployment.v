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

struct DeploymentLockInput {
	format       int                 @[required]
	architecture string              @[required]
	packages     []string            @[required]
	locked       []DeploymentPackage @[required]
}

struct DeploymentHeader {
	format int @[required]
}

struct DeploymentRoots {
	format       int      @[required]
	architecture string   @[required]
	packages     []string @[required]
}

struct DeploymentIdentity {
	domain   string = 'vinix-deployment-review-1'
	config   Config
	current  State
	document DeploymentLock
	plan     Plan
}

// Digest every manifest field, including payload hashes, permissions, license,
// runtime entrypoint and launch arguments. Index sequence/expiry are independent.
pub fn package_metadata_digest(p Package) !string {
	text := json2.encode(canonical_package(p)!) + '\n'
	bytes := text.bytes()
	digest := sha256.sum(bytes).hex()
	unsafe { bytes.free(); text.free() }
	return digest
}

fn read_deployment(path string, architecture string) !DeploymentLock {
	text := read_metadata(path)!
	defer { unsafe { text.free() } }
	header := json2.decode[DeploymentHeader](text)!
	mut document := DeploymentLock{}
	match header.format {
		1 {
			input := json2.decode[DeploymentRoots](text, strict: true)!
			document = DeploymentLock{ format: 1, architecture: input.architecture, packages: input.packages }
		}
		2 {
			input := json2.decode[DeploymentLockInput](text, strict: true)!
			document = DeploymentLock{ format: input.format, architecture: input.architecture, packages: input.packages, locked: input.locked }
		}
		else { return error('unsupported deployment format') }
	}
	deployment_keys(text, document.format)!
	if document.architecture != architecture { return error('deployment architecture mismatch') }
	if document.packages.len > 4096 || document.locked.len > 4096 {
		return error('deployment exceeds its supported package limits')
	}
	mut roots := document.packages.clone()
	roots.sort()
	for i, id in roots {
		if !identifier(id) || (i > 0 && roots[i - 1] == id) {
			return error('invalid or duplicate deployment root: ${id}')
		}
	}
	mut locked := document.locked.clone()
	locked.sort(a.id < b.id)
	for i, pin in locked {
		if !identifier(pin.id) || (i > 0 && locked[i - 1].id == pin.id)
			|| pin.architecture !in [architecture, 'all'] || !identifier(pin.repository)
			|| !digest_valid(pin.public_key) || !digest_valid(pin.metadata_sha256) || pin.minimum_sequence == 0 {
			return error('invalid or duplicate locked deployment package: ${pin.id}')
		}
		version_parts(pin.version)!
	}
	return DeploymentLock{ ...document, packages: roots, locked: locked }
}

// json2 validates syntax/types but intentionally ignores unknown fields and
// accepts duplicate keys. After decoding, inspect object keys without parsing
// values again; the document schema has only a root and flat locked records.
fn deployment_keys(text string, format int) ! {
	root_keys := if format == 1 { ['format', 'architecture', 'packages'] } else { ['format', 'architecture', 'packages', 'locked'] }
	row_keys := ['id', 'version', 'architecture', 'repository', 'public_key', 'minimum_sequence', 'metadata_sha256']
	mut objects := []map[string]bool{}
	mut i := 0
	for i < text.len {
		if text[i] == `{` {
			objects << map[string]bool{}
		} else if text[i] == `}` {
			objects.delete_last()
		} else if text[i] == `"` {
			start := i
			i++
			for i < text.len && text[i] != `"` {
				if text[i] == `\\` { i++ }
				i++
			}
			end := i + 1
			mut next := end
			for next < text.len && text[next] in [u8(` `), `\t`, `\r`, `\n`] { next++ }
			if next < text.len && text[next] == `:` {
				key := json2.decode[[]string]('[' + text[start..end] + ']')![0]
				if objects.len == 0 || objects.len > 2 || (objects.len == 1 && key !in root_keys)
					|| (objects.len == 2 && (format != 2 || key !in row_keys)) {
					return error('unknown deployment field: ${key}')
				}
				mut seen := objects[objects.len - 1]
				if key in seen { return error('duplicate deployment field: ${key}') }
				seen[key] = true
				objects[objects.len - 1] = seen
			}
		}
		i++
	}
}

fn deployment_plan(config Config, directory string, current State, document DeploymentLock) !Plan {
	if document.format == 1 { return operation_plan(config, directory, current, 'deploy', document.packages) }
	catalog := load_catalog(config, directory)!
	mut candidates := []Installed{cap: document.locked.len}
	for pin in document.locked {
		matches := catalog.packages.filter(it.package.id == pin.id && it.package.version == pin.version
			&& it.package.architecture == pin.architecture && it.repository == pin.repository && it.public_key == pin.public_key)
		if matches.len != 1 {
			return error('${pin.id}: locked ${pin.version}/${pin.architecture} publisher is absent from the authenticated catalog; restore the approved repository or regenerate the deployment lock')
		}
		candidate := matches[0]
		if candidate.sequence < pin.minimum_sequence || package_metadata_digest(candidate.package)! != pin.metadata_sha256 {
			return error('${pin.id}: locked publisher sequence or package metadata changed; review a new deployment lock')
		}
		candidates << candidate
	}
	// The normal solver still enforces architecture, organization policy,
	// installed publisher ownership, dependency ranges and runtime entrypoints.
	// It can only select the exact authenticated packages in this document.
	plan := resolve(Catalog{ packages: candidates }, config, current, document.packages, true)!
	if plan.packages.len != document.locked.len {
		return error('deployment lock includes packages outside the requested dependency closure')
	}
	return plan
}

fn deployment_fingerprint(config Config, current State, document DeploymentLock, plan Plan) string {
	text := json2.encode(DeploymentIdentity{ config: config, current: current, document: document, plan: plan })
	bytes := text.bytes()
	fingerprint := sha256.sum(bytes).hex()
	unsafe { bytes.free(); text.free() }
	return fingerprint
}

// Without IDs, export the currently requested set, preferring authenticated
// installed versions. Explicit IDs replace that root set rather than extend it.
pub fn (service Service) lock_deployment(names []string) !DeploymentLock {
	directory := service.directory()!
	guard := acquire_reader(directory)!
	defer { guard.release() }
	config := service.configuration()!
	current := read_state(directory, config.architecture)!
	roots := if names.len == 0 { current.requested } else { names }
	plan := resolve(load_catalog(config, directory)!, config, current, roots, false)!
	mut locked := []DeploymentPackage{cap: plan.packages.len}
	for installed in plan.packages {
		p := installed.package
		locked << DeploymentPackage{ id: p.id, version: p.version, architecture: p.architecture,
			repository: installed.repository, public_key: installed.public_key,
			minimum_sequence: installed.sequence, metadata_sha256: package_metadata_digest(p)! }
	}
	return DeploymentLock{ architecture: config.architecture, packages: plan.requested, locked: locked }
}

pub fn (service Service) review_deployment(path string) !pkgprotocol.Review {
	directory := service.directory()!
	guard := acquire_reader(directory)!
	defer { guard.release() }
	config := service.configuration()!
	current := read_state(directory, config.architecture)!
	document := read_deployment(path, config.architecture)!
	plan := deployment_plan(config, directory, current, document)!
	return review_plan(config, directory, current, 'deploy', document.packages, plan, 0,
		deployment_fingerprint(config, current, document, plan))
}

fn (service Service) deploy_document(path string, expected string) !State {
	directory := service.directory()!
	guard := acquire(directory)!
	defer { guard.release() }
	config := service.configuration()!
	current := read_state(directory, config.architecture)!
	document := read_deployment(path, config.architecture)!
	plan := deployment_plan(config, directory, current, document)!
	check_review(expected, deployment_fingerprint(config, current, document, plan))!
	return activate_plan_locked(config, directory, current, plan, 'deploy', TransactionOptions{})
}

pub fn (service Service) deploy(path string) !State {
	return service.deploy_document(path, '')
}

pub fn (service Service) apply_deployment(path string, expected string) !State {
	if !digest_valid(expected) { return error('deployment apply requires a review fingerprint') }
	return service.deploy_document(path, expected)
}
