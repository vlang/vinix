// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import crypto.sha256
import json2

pub struct PolicyDocument {
pub:
	format       int = 1
	architecture string
	policy       Policy
}

// Unlike the legacy configuration's defaults, an administration document must
// explicitly declare every policy field. Strict decoding rejects null/coercion.
struct PolicyInput {
	offline        bool         @[required]
	allowed        []string     @[required]
	pins           []Dependency @[required]
	permissions    []string     @[required]
	licenses       []string     @[required]
	allow_firmware bool         @[required]
	reserve_bytes  u64          @[required]
}

struct PolicyFile {
	format       int         @[required]
	architecture string      @[required]
	policy       PolicyInput @[required]
}

pub struct PolicyImpact {
pub:
	id                string @[required]
	name              string @[required]
	version           string @[required]
	kind              string @[required]
	license           string @[required]
	proprietary       bool @[required]
	firmware          bool @[required]
	repository        string @[required]
	public_key        string @[required]
	requested         bool @[required]
	diagnostic_before string @[required]
	diagnostic_after  string @[required]
}

pub struct PolicyReview {
pub:
	format       int = 1        @[required]
	architecture string         @[required]
	generation   u64            @[required]
	fingerprint  string         @[required]
	previous     Policy         @[required]
	proposed     Policy         @[required]
	rows         []PolicyImpact @[required] // all installed packages; dependency denial reaches apps
}

struct PolicyIdentity {
	format   int = 1
	config   Config
	state    State
	proposed PolicyDocument
}

struct PolicyReviewFile {
	format       int            @[required]
	architecture string         @[required]
	generation   u64            @[required]
	fingerprint  string         @[required]
	previous     PolicyInput    @[required]
	proposed     PolicyInput    @[required]
	rows         []PolicyImpact @[required]
}

fn policy_from_input(input PolicyInput) Policy {
	return Policy{ offline: input.offline, allowed: input.allowed, pins: input.pins,
		permissions: input.permissions, licenses: input.licenses,
		allow_firmware: input.allow_firmware, reserve_bytes: input.reserve_bytes }
}

fn canonical_policy(policy Policy) !Policy {
	policy.validate()!
	mut allowed := review_strings(policy.allowed)
	mut permissions := review_strings(policy.permissions)
	mut licenses := review_strings(policy.licenses)
	mut pins := []Dependency{cap: policy.pins.len}
	for pin in policy.pins {
		pins << Dependency{ id: pin.id.clone(), minimum: pin.minimum.clone(), before: pin.before.clone() }
	}
	allowed.sort()
	permissions.sort()
	licenses.sort()
	pins.sort(a.id < b.id)
	return Policy{ ...policy, allowed: allowed, permissions: permissions, licenses: licenses, pins: pins }
}

fn read_policy_document(path string, architecture string) !PolicyDocument {
	text := read_metadata(path)!
	defer { unsafe { text.free() } }
	input := json2.decode[PolicyFile](text, strict: true)!
	defer { unsafe { input.architecture.free() } }
	policy := policy_from_input(input.policy)
	defer { close_owned_policy(policy) }
	document_keys(text, policy_document_field)!
	if input.format != 1 || input.architecture != architecture {
		return error('organization policy format or architecture mismatch')
	}
	return PolicyDocument{ architecture: architecture.clone(), policy: canonical_policy(policy)! }
}

fn policy_document_field(parent string, key string) bool {
	return match parent {
		'' { key in ['format', 'architecture', 'policy']! }
		'policy' { policy_field(key) }
		'pins' { key in ['id', 'minimum', 'before']! }
		else { false }
	}
}

fn policy_field(key string) bool {
	return key in ['offline', 'allowed', 'pins', 'permissions', 'licenses', 'allow_firmware', 'reserve_bytes']!
}

fn policy_review_field(parent string, key string) bool {
	return match parent {
		'' { key in ['format', 'architecture', 'generation', 'fingerprint', 'previous', 'proposed', 'rows']! }
		'previous', 'proposed' { policy_field(key) }
		'pins' { key in ['id', 'minimum', 'before']! }
		'rows' { key in ['id', 'name', 'version', 'kind', 'license', 'proprietary', 'firmware',
			'repository', 'public_key', 'requested', 'diagnostic_before', 'diagnostic_after']! }
		else { false }
	}
}

fn policy_fingerprint(config Config, state State, proposed PolicyDocument) string {
	text := json2.encode(PolicyIdentity{ config: config, state: state, proposed: proposed })
	bytes := text.bytes()
	fingerprint := sha256.sum(bytes).hex()
	unsafe {
		bytes.free()
		text.free()
	}
	return fingerprint
}

fn policy_review_locked(root string, path string) !PolicyReview {
	config := load_config(root)!
	state := read_state(state_directory(root), config.architecture)!
	mut proposed := read_policy_document(path, config.architecture)!
	defer { proposed.close() }
	next := Config{ ...config, policy: proposed.policy }
	before := package_diagnostics(config, state.packages)
	defer { close_package_diagnostics(before) }
	after := package_diagnostics(next, state.packages)
	defer { close_package_diagnostics(after) }
	mut rows := []PolicyImpact{cap: state.packages.len}
	for installed in state.packages {
		p := installed.package
		rows << PolicyImpact{
			id: p.id.clone(), name: p.name.clone(), version: p.version.clone(), kind: p.kind.clone()
			license: p.license.clone(), proprietary: p.proprietary, firmware: p.firmware
			repository: installed.repository.clone(), public_key: installed.public_key.clone()
			requested: p.id in state.requested
			diagnostic_before: before[p.id].clone()
			diagnostic_after: after[p.id].clone()
		}
	}
	rows.sort(a.id < b.id)
	mut review := PolicyReview{
		format: 1
		architecture: config.architecture.clone(), generation: state.generation
		fingerprint: policy_fingerprint(config, state, proposed)
		previous: canonical_policy(config.policy)!, proposed: canonical_policy(proposed.policy)!, rows: rows
	}
	review.validate() or { review.close(); return err }
	encoded := json2.encode(review)
	defer { unsafe { encoded.free() } }
	if encoded.len > max_metadata { review.close(); return error('organization policy review exceeds metadata limit') }
	return review
}

fn read_current_policy(root string) !PolicyDocument {
	config := load_config(root)!
	defer { close_decoded_configuration(config) }
	policy := canonical_policy(config.policy)!
	return PolicyDocument{ architecture: config.architecture.clone(), policy: policy }
}

pub fn (service Service) policy() !PolicyDocument {
	directory := service.directory()!
	defer { unsafe { directory.free() } }
	if state_requires_lock(directory) {
		guard := acquire_reader(directory)!
		defer { guard.release() }
		return read_current_policy(service.root)
	}
	return read_current_policy(service.root)
}

pub fn (service Service) review_policy(path string) !PolicyReview {
	directory := service.directory()!
	if state_requires_lock(directory) {
		guard := acquire_reader(directory)!
		defer { guard.release() }
		return policy_review_locked(service.root, path)
	}
	return policy_review_locked(service.root, path)
}

pub fn (service Service) apply_policy(path string, expected string) !PolicyDocument {
	if !digest_valid(expected) { return error('organization policy apply requires a review fingerprint') }
	directory := service.directory()!
	guard := acquire(directory)!
	defer { guard.release() }
	current := load_config(service.root)!
	configuration := writable_configuration(service.root)!
	state := read_state(directory, current.architecture)!
	mut proposed := read_policy_document(path, current.architecture)!
	if expected != policy_fingerprint(current, state, proposed) {
		proposed.close()
		return error('organization policy review is stale: configuration, installed state or proposed policy changed; review again')
	}
	next := Config{ ...current, policy: proposed.policy }
	next.validate()!
	if current.policy != next.policy {
		save_configuration(configuration, next) or { proposed.close(); return err }
	}
	return proposed
}

pub fn (review PolicyReview) validate() ! {
	if review.format != 1 || review.architecture !in ['aarch64', 'x86_64'] || !digest_valid(review.fingerprint)
		|| review.rows.len > 4096 || (review.generation == 0 && review.rows.len != 0) {
		return error('unsupported organization policy review')
	}
	review.previous.validate()!
	review.proposed.validate()!
	mut previous := ''
	for row in review.rows {
		if !identifier(row.id) || row.id <= previous || row.name == '' || !printable(row.name, 256)
			|| row.kind !in ['native', 'linux', 'windows', 'apple', 'runtime', 'data']
			|| row.license == '' || !printable(row.license, 256) || !identifier(row.repository)
			|| !digest_valid(row.public_key) || !printable(row.diagnostic_before, 4096) || !printable(row.diagnostic_after, 4096) {
			return error('invalid installed package in organization policy review')
		}
		version_parts(row.version)!
		previous = row.id
	}
}

pub fn decode_policy_review(text string) !PolicyReview {
	if text.len > max_metadata { return error('organization policy review exceeds metadata limit') }
	input := json2.decode[PolicyReviewFile](text, strict: true)!
	mut review := PolicyReview{ format: input.format, architecture: input.architecture,
		generation: input.generation, fingerprint: input.fingerprint,
		previous: policy_from_input(input.previous), proposed: policy_from_input(input.proposed), rows: input.rows }
	document_keys(text, policy_review_field) or { review.close(); return err }
	review.validate() or { review.close(); return err }
	return review
}

fn close_owned_policy(policy Policy) {
	unsafe {
		for value in policy.allowed { value.free() }
		(&array(&policy.allowed)).free()
		for value in policy.permissions { value.free() }
		(&array(&policy.permissions)).free()
		for value in policy.licenses { value.free() }
		(&array(&policy.licenses)).free()
		for pin in policy.pins { pin.id.free(); pin.minimum.free(); pin.before.free() }
		(&array(&policy.pins)).free()
	}
}

pub fn (mut document PolicyDocument) close() {
	unsafe { document.architecture.free() }
	close_owned_policy(document.policy)
	document = PolicyDocument{ policy: Policy{ permissions: []string{} } }
}

pub fn (mut review PolicyReview) close() {
	unsafe {
		review.architecture.free()
		review.fingerprint.free()
		for row in review.rows {
			row.id.free(); row.name.free(); row.version.free(); row.kind.free(); row.license.free()
			row.repository.free(); row.public_key.free(); row.diagnostic_before.free(); row.diagnostic_after.free()
		}
		(&array(&review.rows)).free()
	}
	close_owned_policy(review.previous)
	close_owned_policy(review.proposed)
	review = PolicyReview{ format: 0, architecture: '', generation: 0, fingerprint: '', rows: []PolicyImpact{},
		previous: Policy{ permissions: []string{} }, proposed: Policy{ permissions: []string{} } }
}
