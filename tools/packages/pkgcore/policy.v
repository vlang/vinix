// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

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
	return decode_policy_document(text, architecture)
}

fn decode_policy_document(text string, architecture string) !PolicyDocument {
	mut input := read_policy_document_input(text)!
	defer { input.close() }
	if input.format != 1 || input.architecture != architecture {
		return error('organization policy format or architecture mismatch')
	}
	return PolicyDocument{ architecture: architecture.clone(), policy: canonical_policy(input.policy)! }
}

// A lower bound, not a second serializer: escaping, settings/envelope keys,
// diagnostics and false flags can only add bytes. Count required presentation
// fields before cloning/canonicalizing a response that cannot fit its limit.
fn policy_review_minimum(previous Policy, proposed Policy, packages []Installed) int {
	mut bytes := 0
	for policy in [previous, proposed]! {
		for values in [policy.allowed, policy.permissions, policy.licenses]! {
			for value in values { bytes += value.len + 3 }
		}
		for pin in policy.pins {
			bytes += pin.id.len + pin.minimum.len + pin.before.len + '{"id":"","minimum":"","before":""},'.len
		}
	}
	for installed in packages {
		p := installed.package
		bytes += p.id.len + p.name.len + p.version.len + p.kind.len + p.license.len
			+ installed.repository.len + installed.public_key.len
			+ '{"id":"","name":"","version":"","kind":"","license":"","proprietary":true,"firmware":true,"repository":"","public_key":"","requested":true,"diagnostic_before":"","diagnostic_after":""},'.len
	}
	return bytes
}

fn read_review_policy_document(path string, config Config, state State) !PolicyDocument {
	text := read_metadata(path)!
	defer { unsafe { text.free() } }
	mut input := read_policy_document_input(text)!
	defer { input.close() }
	if input.format != 1 || input.architecture != config.architecture {
		return error('organization policy format or architecture mismatch')
	}
	if policy_review_minimum(config.policy, input.policy, state.packages) > max_metadata {
		return error('organization policy review exceeds metadata limit')
	}
	return PolicyDocument{ architecture: config.architecture.clone(), policy: canonical_policy(input.policy)! }
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
	mut bytes := []u8{cap: 2048}
	unsafe { bytes.flags |= .noslices }
	defer { unsafe { bytes.free() } }
	json2.encode_append(PolicyIdentity{ config: config, state: state, proposed: proposed }, mut bytes)
	text := bytes.bytestr()
	defer { unsafe { text.free() } }
	// Preserve the exact existing JSON identity, without a persisted newline or
	// a new combined-document bound. Each input already has its own bound.
	return index_digest(text)
}

fn policy_review_locked(root string, directory string, path string) !PolicyReview {
	config := load_config(root)!
	defer { close_decoded_configuration(config) }
	state := read_state(directory, config.architecture)!
	// A generation-zero state borrows its architecture from configuration.
	defer { if state.generation != 0 { close_decoded_state(state) } }
	mut proposed := read_review_policy_document(path, config, state)!
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
	mut accepted := false
	defer { if !accepted { review.close() } }
	review.validate()!
	mut encoded := []u8{cap: 2048}
	unsafe { encoded.flags |= .noslices }
	defer { unsafe { encoded.free() } }
	json2.encode_append(review, mut encoded)
	if encoded.len > max_metadata { return error('organization policy review exceeds metadata limit') }
	accepted = true
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
	defer { unsafe { directory.free() } }
	if state_requires_lock(directory) {
		guard := acquire_reader(directory)!
		defer { guard.release() }
		return policy_review_locked(service.root, directory, path)
	}
	return policy_review_locked(service.root, directory, path)
}

pub fn (service Service) apply_policy(path string, expected string) !PolicyDocument {
	if !digest_valid(expected) { return error('organization policy apply requires a review fingerprint') }
	directory := service.directory()!
	defer { unsafe { directory.free() } }
	guard := acquire(directory)!
	defer { guard.release() }
	current := load_config(service.root)!
	defer { close_decoded_configuration(current) }
	configuration := writable_configuration(service.root)!
	defer { unsafe { configuration.free() } }
	state := read_state(directory, current.architecture)!
	defer { if state.generation != 0 { close_decoded_state(state) } }
	// Apply accepts only policies whose required review can fit the public
	// response limit. Refuse before canonicalization/fingerprinting as review
	// does, including when a caller supplies a stale but well-formed digest.
	mut proposed := read_review_policy_document(path, current, state)!
	mut transferred := false
	defer { if !transferred { proposed.close() } }
	actual := policy_fingerprint(current, state, proposed)
	defer { unsafe { actual.free() } }
	if expected != actual {
		return error('organization policy review is stale: configuration, installed state or proposed policy changed; review again')
	}
	next := Config{ ...current, policy: proposed.policy }
	next.validate()!
	if current.policy != next.policy {
		save_configuration(configuration, next)!
	}
	transferred = true
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
		validated_version(row.version)!
		previous = row.id
	}
}

pub fn decode_policy_review(text string) !PolicyReview {
	mut review := read_policy_review_input(text)!
	review.validate() or { review.close(); return err }
	return review
}

fn close_policy_impact(row PolicyImpact) {
	unsafe {
		row.id.free(); row.name.free(); row.version.free(); row.kind.free(); row.license.free()
		row.repository.free(); row.public_key.free(); row.diagnostic_before.free(); row.diagnostic_after.free()
	}
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
		for row in review.rows { close_policy_impact(row) }
		(&array(&review.rows)).free()
	}
	close_owned_policy(review.previous)
	close_owned_policy(review.proposed)
	review = PolicyReview{ format: 0, architecture: '', generation: 0, fingerprint: '', rows: []PolicyImpact{},
		previous: Policy{ permissions: []string{} }, proposed: Policy{ permissions: []string{} } }
}
