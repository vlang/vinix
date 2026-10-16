// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import crypto.sha256
import json2
import os
import time
import tools.packages.pkgprotocol

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
}

fn C.mkfifo(&char, u32) int


const policy_lifecycle_key = 'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a'
const policy_lifecycle_stale = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'

fn policy_lifecycle_selected(selection string) bool {
	return os.args.len != 3 || os.args[1] != '--policy-lifecycle-case' || os.args[2] == selection
}

fn policy_lifecycle_id(i int, long bool) string {
	digits := (10000 + i).str(); defer { unsafe { digits.free() } }
	prefix := if long { 'i'.repeat(122) } else { 'item'.clone() }; defer { unsafe { prefix.free() } }
	return prefix + '-' + digits
}

// Synthetic installed metadata deliberately has no usable catalog or payloads.
// Policy administration reads provenance, never performs integrity/acquisition.
fn policy_lifecycle_fixture(count int, architecture string, long bool) !(string, Service, string) {
	root := os.temp_dir() + '/vinix-policy-lifecycle-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	configuration := root + '/etc/vinix-packages/config.json'
	os.mkdir_all(os.dir(configuration))!
	mut allowed := []string{cap: count}; mut pins := []Dependency{cap: count}; mut licenses := []string{cap: count}
	mut packages := []Installed{cap: count}; mut requested := []string{cap: 1}
	for i in 0 .. count {
		id := policy_lifecycle_id(i, long); defer { unsafe { id.free() } }
		license := if long { id + 'L'.repeat(128) } else { 'Vendor é🚀'.clone() }
		allowed << id.clone(); pins << Dependency{ id: id.clone(), minimum: '1.0.0', before: '2.0.0' }
		if long || i == 0 { licenses << license.clone() }
		packages << Installed{ package: Package{ id: id.clone(), version: '1.0.0', architecture: 'all',
			name: if long { 'N'.repeat(256) } else { 'Data é🚀' }, kind: 'data', license: license, proprietary: true, firmware: true,
			permissions: [if i == count - 1 { 'network' } else { 'files' }],
			dependencies: [Dependency{ id: policy_lifecycle_id((i + 1) % count, long) }],
			files: [Payload{ path: 'COPYING', bytes: 1, sha256: policy_lifecycle_stale }] },
			repository: if long { 'p'.repeat(128) } else { 'fixture' }, public_key: policy_lifecycle_key, sequence: 7 }
		if i == 0 { requested << id.clone() }
	}
	policy := Policy{ allowed: allowed, pins: pins, licenses: licenses, permissions: ['files', 'network'], allow_firmware: true, reserve_bytes: 17 }
	config := Config{ architecture: architecture, launch_user: 'alex', policy: policy,
		repositories: [Repository{ id: 'other', url: 'file:///offline/unreachable', public_key: policy_lifecycle_stale }] }
	defer { close_decoded_configuration(config) }
	text := encode_administration_document(config, 'fixture configuration too large')!; defer { unsafe { text.free() } }
	os.write_file(configuration, text)!
	path := root + '/policy.json'
	proposal := encode_administration_document(PolicyDocument{ architecture: architecture, policy: policy }, 'fixture policy too large')!
	defer { unsafe { proposal.free() } }; os.write_file(path, proposal)!
	state := State{ architecture: architecture, generation: 7, requested: requested, packages: packages }
	defer { close_decoded_state(state) }
	if count > 0 {
		directory := state_directory(root); defer { unsafe { directory.free() } }
		guard := acquire(directory)!; guard.release()
		generation := directory + '/generations/7'; defer { unsafe { generation.free() } }
		os.mkdir_all(generation)!
		encoded := encode_generation_state(state)!; defer { unsafe { encoded.free() } }
		os.write_file(generation + '/state.json', encoded)!; os.symlink('generations/7', directory + '/current')!
		assert C.mkfifo((directory + '/catalog.json').str, 0o600) == 0
		assert C.mkfifo((directory + '/trust-history.json').str, 0o600) == 0
	}
	return root, Service{ root: root }, path
}

// Independent reference retains the original typed writer and one-shot SHA-256
// identity. It runs outside measured regions and closes loaded owners.
fn policy_lifecycle_legacy_fingerprint(root string, path string) !string {
	config := load_config(root)!; defer { close_decoded_configuration(config) }
	directory := state_directory(root); defer { unsafe { directory.free() } }
	state := read_state(directory, config.architecture)!; defer { if state.generation != 0 { close_decoded_state(state) } }
	mut proposed := read_policy_document(path, config.architecture)!; defer { proposed.close() }
	text := json2.encode(PolicyIdentity{ config: config, state: state, proposed: proposed }); defer { unsafe { text.free() } }
	bytes := text.bytes(); defer { unsafe { bytes.free() } }
	return sha256.sum(bytes).hex()
}

fn test_policy_lifecycle_owned_reviews_and_unchanged_applies() {
	if os.args.len == 3 && os.args[1] == '--policy-lifecycle-case' && !os.args[2].starts_with('owned-') { return }
	for architecture in ['aarch64', 'x86_64']! {
		for count in [0, 1, 64, 4096]! {
			if !policy_lifecycle_selected('owned-' + architecture + '-' + count.str()) { continue }
			root, service, path := policy_lifecycle_fixture(count, architecture, false)!; defer { os.rmdir_all(root) or {} }
			directory := state_directory(root); configuration := root + '/etc/vinix-packages/config.json'
			before := os.read_file(configuration)!; metadata := directory + '/current/state.json'
			state_text := if count == 0 { '' } else { os.read_file(metadata)! }
			expected := policy_lifecycle_legacy_fingerprint(root, path)!
			// The JSON writer publishes immutable per-type field metadata on first
			// use. Warm each shape before measuring repeat-call ownership.
			mut warm := service.review_policy(path)!; assert warm.fingerprint == expected; warm.close()
			tracked := count != 4096; cycles := if tracked { $if track_heap ? { 1000 } $else { 64 } } else { 1 }
			$if track_heap ? { if tracked { C.vinix_heap_begin() } }
			for _ in 0 .. cycles {
				mut review := service.review_policy(path)!
				assert review.architecture == architecture && review.rows.len == count && review.fingerprint == expected
				assert review.proposed.pins.len == count && review.proposed.permissions[0] == 'files'
				if count > 0 { assert review.rows.last().name == 'Data é🚀' && review.rows.last().diagnostic_before.contains('revoked') }
				review.close(); review.close()
			}
			$if track_heap ? { if tracked { kept := C.vinix_heap_end(); assert kept == 0 } }
			if count == 0 { assert !os.exists(directory) }
			// Repeated apply measures the existing store; first creation is checked
			// functionally, separately from the platform mkdir_all implementation.
			guard := acquire(directory)!; guard.release()
			$if track_heap ? { if tracked { C.vinix_heap_begin() } }
			for _ in 0 .. cycles { mut result := service.apply_policy(path, expected)!; assert result.policy.reserve_bytes == 17; result.close(); result.close() }
			$if track_heap ? { if tracked {
				kept := C.vinix_heap_end(); assert kept == 0
				println('POLICY LIFECYCLE ' + architecture + ' ' + count.str() + ' entries: 1000 review and no-op apply cycles retained 0 bytes')
			} }
			assert os.read_file(configuration)! == before
			if count > 0 { assert os.read_file(metadata)! == state_text && os.readlink(directory + '/current')! == 'generations/7' }
			else { assert !os.exists(directory + '/current') }
			if !tracked { continue }
			mut first := service.review_policy(path)!; mut second := (Service{ root: root, offline: true }).review_policy(path)!
			assert first == second && first.proposed.permissions.data != second.proposed.permissions.data
			assert first.architecture.str != second.architecture.str && first.fingerprint.str != second.fingerprint.str
			wire := json2.encode(second)
			mut snapshot := service.state()!
			assert policy_review_minimum(second.previous, second.proposed, snapshot.packages) <= wire.len
			snapshot.close()
			mut client := pkgprotocol.decode_policy_review(wire)!; assert json2.encode(client) == wire; client.close()
			first.close(); os.write_file(configuration, '{retired configuration')!; os.write_file(path, '{retired proposal')!
			if count > 0 { os.write_file(metadata, '{retired state')!; assert second.rows.last().license == 'Vendor é🚀' }
			assert second.architecture == architecture && second.fingerprint == expected && second.proposed.permissions.len == 2
			second.close(); second.close()
		}
	}
	println('POLICY LIFECYCLE both architectures, independent fresh/installed results, exact legacy fingerprints/wire bytes, full 4096 bounds and unchanged no-op state PASS')
}

fn test_policy_lifecycle_changed_applies_and_dependency_disclosure() {
	if !policy_lifecycle_selected('apply') { return }
	for architecture in ['aarch64', 'x86_64']! {
		root, service, path := policy_lifecycle_fixture(2, architecture, false)!; defer { os.rmdir_all(root) or {} }
		configuration := root + '/etc/vinix-packages/config.json'
		original := os.read_file(configuration)!.replace('"id":"other"', '"id":"fixture"').replace(policy_lifecycle_stale, policy_lifecycle_key)
		os.write_file(configuration, original)!
		directory := state_directory(root); state_text := os.read_file(directory + '/current/state.json')!
		path_a := root + '/policy-a.json'; os.write_file(path_a, os.read_file(path)!)!
		text_b := os.read_file(path)!.replace('"permissions":["files","network"]', '"permissions":["files"]')
		os.write_file(path, text_b)!
		mut ab := service.review_policy(path)!; fingerprint_ab := ab.fingerprint.clone()
		assert ab.rows[0].requested && !ab.rows[1].requested && ab.rows[1].firmware && ab.rows[1].proprietary
		assert ab.rows[0].diagnostic_before == '' && ab.rows[1].diagnostic_before == ''
		assert ab.rows[0].diagnostic_after == ab.rows[1].diagnostic_after && ab.rows[0].diagnostic_after.contains('permissions blocked')
		ab.close(); mut applied := service.apply_policy(path, fingerprint_ab)!; applied.close()
		mut ba := service.review_policy(path_a)!; fingerprint_ba := ba.fingerprint.clone(); ba.close()
		mut restored := service.apply_policy(path_a, fingerprint_ba)!; restored.close()
		cycles := $if track_heap ? { 1000 } $else { 64 }
		$if track_heap ? { C.vinix_heap_begin() }
		for _ in 0 .. cycles {
			mut blocked := service.apply_policy(path, fingerprint_ab)!; assert blocked.policy.permissions.len == 1
			mut allowed := service.apply_policy(path_a, fingerprint_ba)!; assert allowed.policy.permissions.len == 2
			assert blocked.policy.permissions.len == 1; blocked.close(); allowed.close()
		}
		$if track_heap ? {
			kept := C.vinix_heap_end(); assert kept == 0
			println('POLICY LIFECYCLE ' + architecture + ' 1000 changed apply pairs retained 0 bytes')
		}
		assert os.read_file(configuration)! == original && os.read_file(directory + '/current/state.json')! == state_text
		assert os.readlink(directory + '/current')! == 'generations/7' && os.ls(directory + '/generations')! == ['7']
		assert os.ls(directory + '/objects')!.len == 0 && os.ls(root + '/etc/vinix-packages')! == ['config.json']
	}
	println('POLICY LIFECYCLE alternating changed apply pairs retire scratch; permission denial crosses dependency cycles, explicit firmware/licenses persist, only configuration changes PASS')
}

fn policy_lifecycle_refusal(service Service, path string, fingerprint string, review bool, expected string) {
	if review {
		if mut result := service.review_policy(path) { result.close(); assert false }
		else { message := err.msg(); assert message.contains(expected), message; unsafe { message.free(); err.free() } }
	}
	if mut result := service.apply_policy(path, fingerprint) { result.close(); assert false }
	else { message := err.msg(); assert message.contains(expected), message; unsafe { message.free(); err.free() } }
}

fn test_policy_lifecycle_refusals_retire_storage_and_allow_restored_retry() {
	if !policy_lifecycle_selected('refusals') { return }
	root, service, path := policy_lifecycle_fixture(2, 'aarch64', false)!; defer { os.rmdir_all(root) or {} }
	configuration := root + '/etc/vinix-packages/config.json'; config_text := os.read_file(configuration)!
	directory := state_directory(root); metadata := directory + '/current/state.json'; state_text := os.read_file(metadata)!
	proposal := os.read_file(path)!
	mut initial := service.review_policy(path)!; fingerprint := initial.fingerprint.clone(); initial.close()
	for failure in ['configuration', 'state', 'proposal', 'proposal-alias', 'proposal-fifo', 'proposal-size', 'stale', 'digest', 'unsafe-file', 'unsafe-parent', 'missing-parent', 'objects', 'generations', 'lock', 'busy']! {
		mut guard := Lock{ fd: -1 }
		match failure {
			'configuration' { os.write_file(configuration, '{bad configuration')! }
			'state' { os.write_file(metadata, '{bad state')! }
			'proposal' { os.write_file(path, '{bad proposal')! }
			'proposal-alias' { os.rm(path)!; os.symlink(configuration, path)! }
			'proposal-fifo' { os.rm(path)!; assert C.mkfifo(path.str, 0o600) == 0 }
			'proposal-size' { os.write_file(path, ' '.repeat(max_metadata + 1))! }
			'unsafe-file' { os.chmod(configuration, 0o666)! }
			'unsafe-parent' { os.chmod(root + '/etc/vinix-packages', 0o777)! }
			'missing-parent' { os.rename(root + '/etc/vinix-packages', root + '/etc/saved')! }
			'objects' { os.rmdir(directory + '/objects')!; os.symlink(root + '/etc', directory + '/objects')! }
			'generations' { os.chmod(directory + '/generations', 0o777)! }
			'lock' { os.rm(directory + '/lock')!; os.symlink(configuration, directory + '/lock')! }
			'busy' { guard = acquire(directory)!; os.write_file(configuration, '{must not be read')! }
			else {}
		}
		review_also := failure !in ['stale', 'digest', 'unsafe-file', 'unsafe-parent', 'objects', 'generations']!
		expected := if failure == 'busy' { 'another package transaction' } else if failure == 'stale' { 'stale' } else { '' }
		confirmation := if failure == 'digest' { 'invalid' } else if failure == 'stale' { policy_lifecycle_stale } else { fingerprint }
		cycles := $if track_heap ? { 1000 } $else { 64 }
		$if track_heap ? { C.vinix_heap_begin() }
		for _ in 0 .. cycles { policy_lifecycle_refusal(service, path, confirmation, review_also, expected) }
		$if track_heap ? {
			kept := C.vinix_heap_end(); assert kept == 0, failure + ' retained ' + kept.str()
			println('POLICY LIFECYCLE ' + failure + ': 1000 refusals retained 0 bytes')
		}
		match failure {
			'proposal-alias', 'proposal-fifo' { os.rm(path)! }
			'unsafe-file' { os.chmod(configuration, 0o644)! }
			'unsafe-parent' { os.chmod(root + '/etc/vinix-packages', 0o755)! }
			'missing-parent' { os.rename(root + '/etc/saved', root + '/etc/vinix-packages')! }
			'objects' { os.rm(directory + '/objects')!; os.mkdir(directory + '/objects')! }
			'generations' { os.chmod(directory + '/generations', 0o755)! }
			'lock' { os.rm(directory + '/lock')!; os.write_file(directory + '/lock', '')!; os.chmod(directory + '/lock', 0o644)! }
			'busy' { guard.release() }
			else {}
		}
		os.write_file(configuration, config_text)!; os.write_file(metadata, state_text)!; os.write_file(path, proposal)!
		mut retry := service.review_policy(path)!; assert retry.fingerprint == fingerprint
		mut saved := service.apply_policy(path, retry.fingerprint)!; saved.close(); retry.close()
		assert os.read_file(configuration)! == config_text && os.read_file(metadata)! == state_text
		assert os.readlink(directory + '/current')! == 'generations/7'
		assert os.ls(directory + '/objects')!.len == 0 && os.ls(root + '/etc/vinix-packages')! == ['config.json']
	}
	println('POLICY LIFECYCLE configuration/state/proposal/stale/ownership/directory/lock/busy refusals retire scratch, preserve activation and permit restored retry PASS')
}

fn test_policy_lifecycle_review_size_refusal_preserves_sources() {
	if !policy_lifecycle_selected('bound') { return }
	// All individual documents fit 8 MiB. Their complete impact disclosure does
	// not. The maximum legitimate live owner set exceeds the tracker's table.
	root, service, path := policy_lifecycle_fixture(4096, 'x86_64', true)!; defer { os.rmdir_all(root) or {} }
	configuration := root + '/etc/vinix-packages/config.json'; before := os.read_file(configuration)!
	directory := state_directory(root); state_text := os.read_file(directory + '/current/state.json')!
	proposal := os.read_file(path)!
	assert before.len < max_metadata && state_text.len < max_metadata && proposal.len < max_metadata
	// A well-formed stale digest must not bypass review-size admission and
	// allocate canonical policy/fingerprint scratch before refusing apply.
	if mut value := service.apply_policy(path, policy_lifecycle_stale) { value.close(); assert false }
	else { message := err.msg(); assert message.contains('review exceeds metadata limit'), message; unsafe { message.free(); err.free() } }
	if mut value := service.review_policy(path) { value.close(); assert false }
	else { message := err.msg(); assert message.contains('review exceeds metadata limit'), message; unsafe { message.free(); err.free() } }
	assert os.read_file(configuration)! == before && os.read_file(path)! == proposal
	assert os.read_file(directory + '/current/state.json')! == state_text && os.readlink(directory + '/current')! == 'generations/7'
	assert os.ls(directory + '/objects')!.len == 0
	guard := acquire(directory)!; guard.release()
	println('POLICY LIFECYCLE oversized review/apply refused before canonicalization; configuration, proposal and installed generation unchanged PASS')
}
