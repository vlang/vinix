// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import tools.packages.pkgprotocol

fn compare_deployment(expected DeploymentLock, installed DeploymentLock, generation u64, digest string, mode DeploymentMode) !pkgprotocol.DeploymentAudit {
	mut targets := map[string]int{}; mut actual := map[string]int{}
	mut ids := []string{cap: expected.locked.len + installed.locked.len}
	// ids borrows the records' IDs; free only its buffer.
	defer { unsafe { targets.free(); actual.free(); (&array(&ids)).free() } }
	for i, pin in expected.locked { targets[pin.id] = i; ids << pin.id }
	for root in expected.packages { if root !in targets { return error('deployment audit root is absent from its locked records: ${root}') } }
	for i, pin in installed.locked {
		actual[pin.id] = i
		if mode == .exact && pin.id !in targets { ids << pin.id }
	}
	for root in installed.packages {
		if root !in actual { return error('installed snapshot root is absent from its locked records: ${root}') }
	}
	ids.sort()
	mut rows := []pkgprotocol.DeploymentAuditRow{cap: ids.len}
	mut accepted := false
	defer { if !accepted { mut partial := pkgprotocol.DeploymentAudit{ rows: rows }; partial.close() } }
	mut matches := true
	absent := DeploymentPackage{ id: '', version: '', architecture: '', repository: '', public_key: '', minimum_sequence: 0, metadata_sha256: '' }
	for id in ids {
		wanted := if id in targets { expected.locked[targets[id]] } else { absent }
		found := if id in actual { installed.locked[actual[id]] } else { absent }
		mut differences := []string{cap: 7}
		if wanted.id != '' && found.id != '' {
			if wanted.architecture != found.architecture { differences << 'architecture'.clone() }
			if wanted.metadata_sha256 != found.metadata_sha256 { differences << 'metadata_sha256'.clone() }
			if wanted.public_key != found.public_key { differences << 'public_key'.clone() }
			if wanted.repository != found.repository { differences << 'repository'.clone() }
			requested := id in expected.packages
			if (mode == .exact || requested) && requested != (id in installed.packages) {
				differences << 'requested'.clone()
			}
			if found.minimum_sequence < wanted.minimum_sequence { differences << 'sequence'.clone() }
			if wanted.version != found.version { differences << 'version'.clone() }
		}
		status := if wanted.id == '' { 'unexpected' } else if found.id == '' { 'missing' }
			else if differences.len > 0 { 'changed' } else { 'match' }
		if status != 'match' { matches = false }
		rows << pkgprotocol.DeploymentAuditRow{ id: id.clone(), status: status.clone(),
			expected_version: wanted.version.clone(), installed_version: found.version.clone(), differences: differences }
	}
	report := pkgprotocol.DeploymentAudit{ generation: generation, architecture: installed.architecture.clone(),
		deployment_sha256: digest.clone(), matches: matches, rows: rows }
	report.validate() or { mut discarded := report; discarded.close(); accepted = true; return err }
	accepted = true
	return report
}

fn audit_deployment_locked(service Service, directory string, path string, mode DeploymentMode) !pkgprotocol.DeploymentAudit {
	config := service.configuration()!; defer { close_decoded_configuration(config) }
	// Read exactly once. The report's digest identifies the same bytes decoded
	// here, even if the pathname is replaced before the comparison finishes.
	text := read_metadata(path)!; defer { unsafe { text.free() } }
	mut expected := decode_deployment(text, config.architecture)!; defer { expected.close() }
	if expected.format != 2 { return error('deployment audit requires an exact format-2 lock; export deployment-lock or deployment-snapshot first') }
	if mode == .additions && expected.packages.len == 0 {
		return error('deployment coverage requires at least one application root')
	}
	current := read_state(directory, config.architecture)!
	defer { if current.generation != 0 { close_decoded_state(current) } }
	mut installed := owned_deployment_lock(config.architecture, Plan{ requested: current.requested, packages: current.packages })!
	defer { installed.close() }
	digest := index_digest(text); defer { unsafe { digest.free() } }
	return compare_deployment(expected, installed, current.generation, digest, mode)
}

// Inspect one coherent installed generation without catalog, cache, replay or
// payload access. This is drift detection, not trust or integrity attestation.
pub fn (service Service) audit_deployment(path string) !pkgprotocol.DeploymentAudit {
	return service.audit_deployment_mode(path, .exact)
}

// Compare every locked pin and requested root while allowing additional
// installed packages and explicitly requested dependencies.
pub fn (service Service) audit_deployment_additions(path string) !pkgprotocol.DeploymentAudit {
	return service.audit_deployment_mode(path, .additions)
}

fn (service Service) audit_deployment_mode(path string, mode DeploymentMode) !pkgprotocol.DeploymentAudit {
	directory := service.directory()!; defer { unsafe { directory.free() } }
	if state_requires_lock(directory) {
		guard := acquire_reader(directory)!; defer { guard.release() }
		return audit_deployment_locked(service, directory, path, mode)
	}
	return audit_deployment_locked(service, directory, path, mode)
}

// Read the original lock bytes whose digest was checked by ISO verification.
// The caller owns the returned text.
pub fn read_release_lock_matching_digest(path string, expected_sha256 string) !string {
	text := read_metadata(path)!
	digest := index_digest(text)
	defer { unsafe { digest.free() } }
	if digest != expected_sha256 {
		unsafe { text.free() }
		return error('captured release lock differs from the ISO package receipt')
	}
	return text
}

// Compare saved metadata using the two reviewed digests. The snapshot receipt
// supplies its recorded generation and counts, and grants no package authority.
pub fn audit_saved_deployment_coverage(release_path string, release_sha256 string, snapshot_path string, saved pkgprotocol.DeploymentSnapshotSaved) !pkgprotocol.DeploymentAudit {
	saved.validate()!
	release_text := read_release_lock_matching_digest(release_path, release_sha256)!
	defer { unsafe { release_text.free() } }
	mut expected := decode_deployment(release_text, saved.architecture)!
	defer { expected.close() }
	if expected.format != 2 || expected.packages.len == 0 {
		return error('installed release verification requires a nonempty format-2 release lock')
	}
	snapshot_text := read_metadata(snapshot_path)!
	defer { unsafe { snapshot_text.free() } }
	snapshot_digest := index_digest(snapshot_text)
	defer { unsafe { snapshot_digest.free() } }
	if snapshot_digest != saved.sha256 { return error('installed snapshot SHA-256 differs from its saved receipt') }
	mut installed := decode_deployment(snapshot_text, saved.architecture)!
	defer { installed.close() }
	if installed.format != 2 { return error('installed snapshot requires a format-2 document') }
	if u64(installed.packages.len) != saved.roots || u64(installed.locked.len) != saved.packages {
		return error('installed snapshot counts differ from its saved receipt')
	}
	return compare_deployment(expected, installed, saved.generation, release_sha256, .additions)
}
